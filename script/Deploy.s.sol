// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { ReanchorSwapSource } from "../src/ReanchorSwapSource.sol";
import { ReanchorReactive } from "../src/ReanchorReactive.sol";
import { ReanchorExecutor } from "../src/ReanchorExecutor.sol";

interface ICallbackProxy {
    function depositTo(address contract_) external payable;
}

/// @notice Deployment entry points. Each `run` broadcasts with DEPLOYER_PRIVATE_KEY.
contract DeploySwapSource is Script {
    function run() external returns (ReanchorSwapSource source) {
        vm.startBroadcast(_key());
        source = new ReanchorSwapSource();
        vm.stopBroadcast();
        console.log("SwapSource", address(source));
    }

    function _key() internal view returns (uint256) {
        return vm.envUint("DEPLOYER_PRIVATE_KEY");
    }
}

contract DeployReactive is Script {
    function run() external returns (ReanchorReactive reactive) {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        address pool = vm.envAddress("POOL_ADDRESS");
        uint256 originChainId = vm.envUint("ORIGIN_CHAIN_ID");
        uint256 destinationChainId = vm.envUint("DESTINATION_CHAIN_ID");
        uint256 fund = vm.envUint("REACTIVE_FUND_WEI");

        vm.startBroadcast(key);
        reactive = new ReanchorReactive{ value: fund }(deployer, originChainId, pool, destinationChainId);
        vm.stopBroadcast();

        console.log("Reactive", address(reactive));
        console.log("Owner", reactive.owner());
        console.log("PendingOwner", reactive.pendingOwner());
    }
}

contract DeployExecutor is Script {
    address internal constant BASE_SEPOLIA_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    address internal constant UNICHAIN_SEPOLIA_PROXY = 0x775c9B990ADe401060B78D0e98684eEf8d2466C1;

    function run() external returns (ReanchorExecutor executor) {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        address reactive = vm.envAddress("REACTIVE_ADDRESS");
        uint256 fund = vm.envUint("EXECUTOR_FUND_WEI");
        address proxy = _proxy(block.chainid);

        vm.startBroadcast(key);
        executor = new ReanchorExecutor(IPayable(payable(proxy)), reactive, deployer);
        ICallbackProxy(proxy).depositTo{ value: fund }(address(executor));
        vm.stopBroadcast();

        console.log("Executor", address(executor));
        console.log("Proxy", proxy);
        console.log("Owner", executor.owner());
        console.log("PendingOwner", executor.pendingOwner());
    }

    function _proxy(uint256 chainId) internal pure returns (address) {
        if (chainId == 84_532) return BASE_SEPOLIA_PROXY;
        if (chainId == 1301) return UNICHAIN_SEPOLIA_PROXY;
        revert("unsupported destination");
    }
}

contract ConfigureReactive is Script {
    int24 internal constant TICK_LOWER = -100;
    int24 internal constant TICK_UPPER = 100;

    function run() external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(key);
        ReanchorReactive reactive = ReanchorReactive(payable(vm.envAddress("REACTIVE_ADDRESS")));
        address executor = vm.envAddress("EXECUTOR_ADDRESS");

        vm.startBroadcast(key);
        _acceptIfPending(reactive.pendingOwner(), deployer);
        if (reactive.executor() != executor) reactive.setExecutor(executor);
        if (reactive.tickLower() != TICK_LOWER || reactive.tickUpper() != TICK_UPPER) {
            reactive.setRange(TICK_LOWER, TICK_UPPER);
        }
        vm.stopBroadcast();

        console.log("ExecutorSet", reactive.executor());
        console.log("TickLower", reactive.tickLower());
        console.log("TickUpper", reactive.tickUpper());
        console.log("Owner", reactive.owner());
    }

    /// @dev Ownable2Step only needs acceptOwnership after transferOwnership.
    ///      Deployment passes the deployer as initialOwner, so this is a no-op
    ///      unless a transfer is already pending for this key.
    function _acceptIfPending(address pending, address deployer) internal {
        if (pending == deployer) {
            ReanchorReactive(payable(vm.envAddress("REACTIVE_ADDRESS"))).acceptOwnership();
            console.log("AcceptedOwnership");
        } else {
            console.log("OwnershipAlreadyHeld");
        }
    }
}
