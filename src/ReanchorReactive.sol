// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReanchorReactive
/// @notice Watches a Uniswap V3-style pool on an origin chain and asks the
///         destination executor to record a re-anchor when price leaves the
///         stored range. Decision logic lives here.
/// @dev Inherits AbstractReactive, Ownable2Step, and ReentrancyGuard.
///      `react` is `onlySystem`. Logs that do not apply are ignored by returning.
contract ReanchorReactive is AbstractReactive, Ownable2Step, ReentrancyGuard {
    /// @notice keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)").
    uint256 public constant SWAP_TOPIC_0 = 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67;

    /// @notice Gas forwarded to the destination executor. Clears the callback
    ///         proxy overhead (`_extraGas` + `_maxChargeGas`) on Base Sepolia
    ///         and Unichain Sepolia and leaves room for the executor write.
    uint64 public constant CALLBACK_GAS_LIMIT = 500_000;

    /// @notice Swap logs carry three topics: the signature, sender, and recipient.
    uint256 private constant _SWAP_TOPIC_COUNT = 3;

    /// @notice Non-indexed Swap payload is five 32-byte words. Tick is the last.
    uint256 private constant _SWAP_DATA_LENGTH = 160;

    uint256 private constant _TICK_WORD_OFFSET = 128;

    uint256 public immutable originChainId;
    address public immutable pool;
    uint256 public immutable destinationChainId;

    address public executor;
    int24 public tickLower;
    int24 public tickUpper;
    int24 public buffer;
    uint256 public cooldown;
    uint256 public lastReactionAt;

    event ExecutorUpdated(address indexed executor);
    event RangeUpdated(int24 tickLower, int24 tickUpper, int24 buffer);
    event CooldownUpdated(uint256 cooldown);
    event ReanchorRequested(int24 indexed tick, address indexed executor, uint256 reactiveTimestamp);

    error ZeroAddress();
    error InvalidChain(uint256 chainId);
    error InvalidRange(int24 tickLower, int24 tickUpper, int24 buffer);

    /// @param initialOwner_ Owner of the privileged setters. Ownership is two-step.
    /// @param originChainId_ Chain that emits the pool Swap logs.
    /// @param pool_ Uniswap V3-style pool to subscribe to.
    /// @param destinationChainId_ Chain that receives the re-anchor callback.
    constructor(address initialOwner_, uint256 originChainId_, address pool_, uint256 destinationChainId_)
        payable
        Ownable(initialOwner_)
    {
        if (pool_ == address(0)) revert ZeroAddress();
        if (originChainId_ == 0) revert InvalidChain(originChainId_);
        if (destinationChainId_ == 0) revert InvalidChain(destinationChainId_);

        originChainId = originChainId_;
        pool = pool_;
        destinationChainId = destinationChainId_;

        SYSTEM.subscribe(originChainId_, pool_, SWAP_TOPIC_0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external override onlySystem {
        if (
            log_.chainId != originChainId || log_.contractAddress != pool || log_.topic0 != SWAP_TOPIC_0
                || log_.opCode != _SWAP_TOPIC_COUNT
        ) {
            return;
        }

        (bool tickOk, int24 tick) = _swapTick(log_.data);
        if (!tickOk || !_outsideRange(tick)) return;
        if (executor == address(0)) return;
        if (lastReactionAt != 0 && block.timestamp - lastReactionAt < cooldown) return;

        lastReactionAt = block.timestamp;
        emit ReanchorRequested(tick, executor, block.timestamp);

        bytes memory payload = abi.encodeWithSignature(
            "onRangeExit(address,uint256,address,int24,int24,int24,uint256,uint256,uint256)",
            address(0),
            log_.chainId,
            log_.contractAddress,
            tick,
            tickLower,
            tickUpper,
            log_.blockNumber,
            log_.txHash,
            block.timestamp
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId, recipient: executor, gasLimit: CALLBACK_GAS_LIMIT, payload: payload
            })
        );
    }

    /// @notice Destination contract that receives `onRangeExit`.
    function setExecutor(address executor_) external onlyOwner nonReentrant {
        if (executor_ == address(0)) revert ZeroAddress();
        executor = executor_;
        emit ExecutorUpdated(executor_);
    }

    /// @notice Active range is half-open: `tickLower <= tick < tickUpper`.
    function setRange(int24 tickLower_, int24 tickUpper_) external onlyOwner nonReentrant {
        _assertRange(tickLower_, tickUpper_, buffer);
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        emit RangeUpdated(tickLower_, tickUpper_, buffer);
    }

    /// @notice Ticks within `buffer` of either edge are treated as out of range.
    function setBuffer(int24 buffer_) external onlyOwner nonReentrant {
        _assertRange(tickLower, tickUpper, buffer_);
        buffer = buffer_;
        emit RangeUpdated(tickLower, tickUpper, buffer_);
    }

    /// @notice Minimum seconds between callback requests. Uses `block.timestamp`.
    function setCooldown(uint256 cooldown_) external onlyOwner nonReentrant {
        cooldown = cooldown_;
        emit CooldownUpdated(cooldown_);
    }

    /// @notice Pays outstanding reactive debt from this contract's balance.
    function coverDebt() external onlyOwner nonReentrant {
        _coverDebt();
    }

    function _outsideRange(int24 tick) internal view returns (bool) {
        if (tickUpper <= tickLower) return false;

        int256 lower = int256(tickLower) + int256(buffer);
        int256 upper = int256(tickUpper) - int256(buffer);
        if (lower >= upper) return false;

        int256 current = int256(tick);
        return current < lower || current >= upper;
    }

    function _assertRange(int24 tickLower_, int24 tickUpper_, int24 buffer_) internal pure {
        if (buffer_ < 0) revert InvalidRange(tickLower_, tickUpper_, buffer_);

        int256 lower = int256(tickLower_) + int256(buffer_);
        int256 upper = int256(tickUpper_) - int256(buffer_);
        if (lower >= upper) revert InvalidRange(tickLower_, tickUpper_, buffer_);
    }

    /// @dev The tick is the fifth ABI word, sign-extended. A word that does not
    ///      fit in int24 is ignored so `react` does not revert on a bad log.
    function _swapTick(bytes calldata data_) internal pure returns (bool ok, int24 tick) {
        if (data_.length != _SWAP_DATA_LENGTH) return (false, 0);

        int256 raw;
        assembly ("memory-safe") {
            raw := calldataload(add(data_.offset, _TICK_WORD_OFFSET))
        }

        if (raw > type(int24).max || raw < type(int24).min) return (false, 0);
        return (true, int24(raw));
    }
}
