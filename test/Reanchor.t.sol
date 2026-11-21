// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { ReanchorReactive } from "../src/ReanchorReactive.sol";
import { ReanchorExecutor } from "../src/ReanchorExecutor.sol";
import { MockSystem } from "./mocks/MockSystem.sol";

contract ReanchorTest is Test {
    address internal constant SYSTEM_ADDRESS = 0x8888888888888888888888888888888888888888;

    uint256 internal constant ORIGIN_CHAIN_ID = 84_532;
    uint256 internal constant DESTINATION_CHAIN_ID = 84_532;
    int24 internal constant TICK_LOWER = -100;
    int24 internal constant TICK_UPPER = 100;

    bytes4 internal constant ON_RANGE_EXIT_SELECTOR =
        bytes4(keccak256("onRangeExit(address,uint256,address,int24,int24,int24,uint256,uint256,uint256)"));

    ReanchorReactive internal reactive;
    ReanchorExecutor internal executor;
    address internal pool;
    address internal proxy;
    address internal attacker;

    function setUp() public {
        MockSystem deployed = new MockSystem();
        vm.etch(SYSTEM_ADDRESS, address(deployed).code);

        pool = makeAddr("pool");
        proxy = makeAddr("proxy");
        attacker = makeAddr("attacker");

        reactive = new ReanchorReactive(address(this), ORIGIN_CHAIN_ID, pool, DESTINATION_CHAIN_ID);
        executor = new ReanchorExecutor(IPayable(payable(proxy)), address(reactive), address(this));
        reactive.setExecutor(address(executor));
        reactive.setRange(TICK_LOWER, TICK_UPPER);
    }

    function test_react_rejectsUnauthorizedCaller() public {
        IReactive.LogRecord memory log_ = _swapLog(0);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, attacker, SYSTEM_ADDRESS));
        reactive.react(log_);
    }

    function test_executor_rejectsCallerThatIsNotProxy() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, attacker, proxy));
        executor.onRangeExit(address(reactive), ORIGIN_CHAIN_ID, pool, 100, TICK_LOWER, TICK_UPPER, 1, 2, 3);
    }

    function test_executor_rejectsWrongReactiveAddress() public {
        address wrongReactive = makeAddr("wrongReactive");

        vm.prank(proxy);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractCallback.CallbackNotAuthorized.selector, wrongReactive, address(reactive))
        );
        executor.onRangeExit(wrongReactive, ORIGIN_CHAIN_ID, pool, 100, TICK_LOWER, TICK_UPPER, 1, 2, 3);
    }

    function test_react_requestsCallbackWhenTickIsOutOfRange() public {
        int24 tick = TICK_UPPER;
        IReactive.LogRecord memory log_ = _swapLog(tick);

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(log_);

        MockSystem system = MockSystem(payable(SYSTEM_ADDRESS));
        assertEq(system.callbackCount(), 1);
        assertEq(system.lastChainId(), DESTINATION_CHAIN_ID);
        assertEq(system.lastRecipient(), address(executor));
        assertEq(system.lastGasLimit(), reactive.CALLBACK_GAS_LIMIT());
        assertEq(reactive.lastReactionAt(), block.timestamp);

        bytes memory payload = system.lastPayload();
        assertEq(_selector(payload), ON_RANGE_EXIT_SELECTOR);
        assertEq(_payloadSender(payload), address(0));
    }

    function test_react_returnsWithoutCallbackWhenTickIsInRange() public {
        IReactive.LogRecord memory log_ = _swapLog(0);

        vm.prank(SYSTEM_ADDRESS);
        reactive.react(log_);

        MockSystem system = MockSystem(payable(SYSTEM_ADDRESS));
        assertEq(system.callbackCount(), 0);
        assertEq(reactive.lastReactionAt(), 0);
    }

    function _swapLog(int24 tick) internal view returns (IReactive.LogRecord memory log_) {
        log_.chainId = ORIGIN_CHAIN_ID;
        log_.contractAddress = pool;
        log_.topic0 = reactive.SWAP_TOPIC_0();
        log_.opCode = 3;
        log_.blockNumber = 10;
        log_.txHash = 2;
        log_.data = abi.encode(int256(1), int256(-1), uint160(1), uint128(1), tick);
    }

    function _selector(bytes memory payload) internal pure returns (bytes4 selector) {
        assembly {
            selector := mload(add(payload, 32))
        }
    }

    function _payloadSender(bytes memory payload) internal pure returns (address sender) {
        assembly {
            sender := mload(add(payload, 36))
        }
    }
}
