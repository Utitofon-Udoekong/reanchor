// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { INonfungiblePositionManager } from "./interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3PoolImmutables } from "./interfaces/IUniswapV3PoolImmutables.sol";

/// @title ReanchorExecutor
/// @notice Destination contract for Reanchor. Authenticates the Reactive
///         callback, records the timestamps of one measured loop, then exits
///         a registered position and mints a new range around the delivered tick.
/// @dev Inherits AbstractCallback, Ownable2Step, and ReentrancyGuard.
///      `onRangeExit` is `onlyServiceProvider`, `onlyCallbackSender`, and `nonReentrant`.
///      The exit sequence is the periphery order: `decreaseLiquidity`, `collect`, `burn`,
///      then `mint`. `burn` requires zero liquidity and a prior collect.
///      https://github.com/Uniswap/v3-periphery/blob/main/contracts/NonfungiblePositionManager.sol
contract ReanchorExecutor is AbstractCallback, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev TickMath.MIN_TICK / MAX_TICK from Uniswap v3-core `TickMath.sol`.
    int24 internal constant MIN_TICK = -887_272;
    int24 internal constant MAX_TICK = 887_272;

    /// @dev Slippage is expressed in basis points. 10_000 is 100 percent.
    uint256 internal constant SLIPPAGE_BPS_DENOMINATOR = 10_000;

    struct Observation {
        uint256 originChainId;
        address pool;
        int24 tick;
        int24 tickLower;
        int24 tickUpper;
        uint256 originBlockNumber;
        uint256 originTxHash;
        uint256 reactiveTimestamp;
        uint256 callbackTimestamp;
    }

    /// @notice The NFT a provider has approved this executor to manage.
    /// @dev `tokenId` 0 means no position. Uniswap's manager starts ids at 1.
    struct Registration {
        address provider;
        uint256 tokenId;
        address token0;
        address token1;
        uint24 fee;
    }

    Observation public latest;
    uint256 public observationCount;

    INonfungiblePositionManager public positionManager;
    Registration public registration;
    uint256 public slippageBps = 50;

    event Reanchored(
        address indexed pool,
        int24 tick,
        uint256 originBlockNumber,
        uint256 reactiveTimestamp,
        uint256 callbackTimestamp
    );
    event PositionManagerSet(address indexed positionManager);
    event SlippageSet(uint256 slippageBps);
    event PositionRegistered(address indexed provider, uint256 indexed tokenId);
    event PositionCleared(address indexed provider, uint256 indexed tokenId);
    event PositionRepositioned(
        address indexed provider,
        uint256 indexed oldTokenId,
        uint256 indexed newTokenId,
        int24 tickLower,
        int24 tickUpper
    );

    error ZeroAddress();
    error SlippageTooHigh(uint256 slippageBps);
    error NoPositionManager();
    error NotPositionOwner(address caller, address owner);
    error NotApproved(address provider);
    error EmptyPosition(uint256 tokenId);
    error InvalidRange();
    error InvalidSpacing(int24 spacing);
    error PoolMismatch(address pool);

    /// @param callbackProxy_ Callback proxy on this destination chain.
    /// @param callbackSender_ Reactive contract authorized to drive this executor.
    /// @param initialOwner_ Owner of the privileged debt settlement and configuration.
    constructor(IPayable callbackProxy_, address callbackSender_, address initialOwner_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
        Ownable(initialOwner_)
    { }

    /// @notice Records one out-of-range signal, then repositions a registered NFT.
    /// @param reactive_ Injected sender. Pass `address(0)` when requesting the callback.
    function onRangeExit(
        address reactive_,
        uint256 originChainId_,
        address pool_,
        int24 tick_,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 originBlockNumber_,
        uint256 originTxHash_,
        uint256 reactiveTimestamp_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) nonReentrant {
        latest = Observation({
            originChainId: originChainId_,
            pool: pool_,
            tick: tick_,
            tickLower: tickLower_,
            tickUpper: tickUpper_,
            originBlockNumber: originBlockNumber_,
            originTxHash: originTxHash_,
            reactiveTimestamp: reactiveTimestamp_,
            callbackTimestamp: block.timestamp
        });
        observationCount += 1;

        emit Reanchored(pool_, tick_, originBlockNumber_, reactiveTimestamp_, block.timestamp);

        if (registration.tokenId != 0) _reposition(pool_, tick_);
    }

    /// @notice Pays outstanding callback debt from this contract's balance.
    function coverDebt() external onlyOwner nonReentrant {
        _coverDebt();
    }

    /// @notice Position manager used for exit and mint. Owner configuration.
    function setPositionManager(INonfungiblePositionManager positionManager_) external onlyOwner {
        if (address(positionManager_) == address(0)) revert ZeroAddress();
        positionManager = positionManager_;
        emit PositionManagerSet(address(positionManager_));
    }

    /// @notice Mint slippage in basis points. 50 is 0.50 percent. Owner configuration.
    function setSlippageBps(uint256 slippageBps_) external onlyOwner {
        if (slippageBps_ > SLIPPAGE_BPS_DENOMINATOR) revert SlippageTooHigh(slippageBps_);
        slippageBps = slippageBps_;
        emit SlippageSet(slippageBps_);
    }

    /// @notice Register `tokenId` for the caller.
    /// @dev The caller is the provider: they must own the NFT and have granted this
    ///      executor `setApprovalForAll`. Operator approval covers the NFT minted later.
    ///      Single-token `approve` does not, because `mint` issues a new id.
    function registerPosition(uint256 tokenId) external {
        if (address(positionManager) == address(0)) revert NoPositionManager();

        IERC721 nft = IERC721(address(positionManager));
        address provider = nft.ownerOf(tokenId);
        if (provider != msg.sender) revert NotPositionOwner(msg.sender, provider);
        if (!nft.isApprovedForAll(provider, address(this))) revert NotApproved(provider);

        (,, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            positionManager.positions(tokenId);
        if (liquidity == 0 || tickLower >= tickUpper) revert EmptyPosition(tokenId);

        registration = Registration({ provider: provider, tokenId: tokenId, token0: token0, token1: token1, fee: fee });
        emit PositionRegistered(provider, tokenId);
    }

    /// @notice Drop the registration. The provider or the contract owner may call it.
    function clearPosition() external {
        Registration memory current = registration;
        if (current.tokenId == 0) return;
        if (msg.sender != current.provider && msg.sender != owner()) {
            revert NotPositionOwner(msg.sender, current.provider);
        }
        delete registration;
        emit PositionCleared(current.provider, current.tokenId);
    }

    /// @dev Full exit, then a new position of the same width centered on `tick`.
    ///      Deadline is `block.timestamp`, the minimum the periphery `checkDeadline`
    ///      modifier accepts (`deadline >= block.timestamp`). Decrease minimums are
    ///      zero because the burned amounts are only known from the return value.
    ///      Mint minimums apply `slippageBps` to the collected amounts.
    function _reposition(address pool, int24 tick) internal {
        Registration memory current = registration;
        IUniswapV3PoolImmutables v3Pool = IUniswapV3PoolImmutables(pool);
        if (v3Pool.token0() != current.token0 || v3Pool.token1() != current.token1 || v3Pool.fee() != current.fee) {
            revert PoolMismatch(pool);
        }

        int24 spacing = v3Pool.tickSpacing();
        if (spacing <= 0) revert InvalidSpacing(spacing);

        IERC721 nft = IERC721(address(positionManager));
        if (nft.ownerOf(current.tokenId) != current.provider) {
            revert NotPositionOwner(current.provider, nft.ownerOf(current.tokenId));
        }
        if (!nft.isApprovedForAll(current.provider, address(this))) revert NotApproved(current.provider);

        (,,,,, int24 oldLower, int24 oldUpper, uint128 liquidity,,,,) = positionManager.positions(current.tokenId);
        if (liquidity == 0) revert EmptyPosition(current.tokenId);

        uint256 deadline = block.timestamp;
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: current.tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: deadline
            })
        );

        (uint256 amount0, uint256 amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: current.tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        positionManager.burn(current.tokenId);

        (int24 newLower, int24 newUpper) = _centeredRange(tick, oldUpper - oldLower, spacing);
        _mintReplacement(current, amount0, amount1, newLower, newUpper, deadline);
    }

    function _mintReplacement(
        Registration memory current,
        uint256 amount0,
        uint256 amount1,
        int24 newLower,
        int24 newUpper,
        uint256 deadline
    ) internal {
        IERC20(current.token0).forceApprove(address(positionManager), amount0);
        IERC20(current.token1).forceApprove(address(positionManager), amount1);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: current.token0,
            token1: current.token1,
            fee: current.fee,
            tickLower: newLower,
            tickUpper: newUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: _withSlippage(amount0),
            amount1Min: _withSlippage(amount1),
            recipient: current.provider,
            deadline: deadline
        });
        (uint256 newTokenId,,,) = positionManager.mint(params);

        IERC20(current.token0).forceApprove(address(positionManager), 0);
        IERC20(current.token1).forceApprove(address(positionManager), 0);
        _refund(current.token0, current.provider);
        _refund(current.token1, current.provider);

        uint256 oldTokenId = current.tokenId;
        registration.tokenId = newTokenId;
        emit PositionRepositioned(current.provider, oldTokenId, newTokenId, newLower, newUpper);
    }

    /// @dev Floor `tick - width/2` to a multiple of `spacing`, then keep `width`.
    ///      Usable bounds are the multiples of spacing inside TickMath's min and max,
    ///      matching periphery `getMinTick` / `getMaxTick`.
    function _centeredRange(int24 tick, int24 width, int24 spacing) internal pure returns (int24 lower, int24 upper) {
        if (width <= 0 || width % spacing != 0) revert InvalidRange();

        int24 minUsable = _alignUp(int256(MIN_TICK), spacing);
        int24 maxUsable = _alignDown(int256(MAX_TICK), spacing);
        if (int256(width) > int256(maxUsable) - int256(minUsable)) revert InvalidRange();

        int256 rawLower = int256(tick) - (int256(width) / 2);
        lower = _alignDown(rawLower, spacing);
        upper = int24(int256(lower) + int256(width));

        if (upper > maxUsable) {
            upper = maxUsable;
            lower = int24(int256(upper) - int256(width));
        }
        if (lower < minUsable) {
            lower = minUsable;
            upper = int24(int256(lower) + int256(width));
        }
        if (lower >= upper || lower < minUsable || upper > maxUsable) revert InvalidRange();
    }

    /// @dev Floor division for a possibly negative tick. Solidity divides toward zero.
    function _alignDown(int256 tick, int24 spacing) internal pure returns (int24) {
        int256 step = int256(spacing);
        int256 compressed = tick / step;
        if (tick < 0 && tick % step != 0) compressed -= 1;
        return int24(compressed * step);
    }

    function _alignUp(int256 tick, int24 spacing) internal pure returns (int24) {
        int24 down = _alignDown(tick, spacing);
        if (int256(down) == tick) return down;
        return int24(int256(down) + int256(spacing));
    }

    function _withSlippage(uint256 amount) internal view returns (uint256) {
        return amount * (SLIPPAGE_BPS_DENOMINATOR - slippageBps) / SLIPPAGE_BPS_DENOMINATOR;
    }

    function _refund(address token, address provider) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) IERC20(token).safeTransfer(provider, balance);
    }
}
