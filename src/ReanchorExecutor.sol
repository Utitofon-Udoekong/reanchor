// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReanchorExecutor
/// @notice Destination contract for Reanchor. Authenticates the Reactive
///         callback and records the timestamps of one measured loop.
/// @dev Inherits AbstractCallback, Ownable2Step, and ReentrancyGuard.
///      `onRangeExit` is `onlyServiceProvider`, `onlyCallbackSender`, and `nonReentrant`.
contract ReanchorExecutor is AbstractCallback, Ownable2Step, ReentrancyGuard {
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

    Observation public latest;
    uint256 public observationCount;

    event Reanchored(
        address indexed pool,
        int24 tick,
        uint256 originBlockNumber,
        uint256 reactiveTimestamp,
        uint256 callbackTimestamp
    );

    /// @param callbackProxy_ Callback proxy on this destination chain.
    /// @param callbackSender_ Reactive contract authorized to drive this executor.
    /// @param initialOwner_ Owner of the privileged debt settlement. Two-step transfer.
    constructor(IPayable callbackProxy_, address callbackSender_, address initialOwner_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
        Ownable(initialOwner_)
    { }

    /// @notice Records one out-of-range signal. The first argument is overwritten
    ///         by Reactive Network with the reactive contract address.
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
    }

    /// @notice Pays outstanding callback debt from this contract's balance.
    function coverDebt() external onlyOwner nonReentrant {
        _coverDebt();
    }
}
