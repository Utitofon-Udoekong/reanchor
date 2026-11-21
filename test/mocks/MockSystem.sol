// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @notice Test double etched onto the Reactive system-contract address.
///         Records `requestCallbackV_1_0` and accepts subscriptions.
contract MockSystem is ISystemContract {
    uint256 public callbackCount;
    uint256 public lastChainId;
    address public lastRecipient;
    uint64 public lastGasLimit;
    bytes public lastPayload;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external override { }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external override { }

    function requestCallback(CallbackVersion, bytes memory) external override { }

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external override {
        callbackCount += 1;
        lastChainId = config_.chainId;
        lastRecipient = config_.recipient;
        lastGasLimit = config_.gasLimit;
        lastPayload = config_.payload;
    }

    function debt(address) external pure override returns (uint256) {
        return 0;
    }

    receive() external payable override { }
}
