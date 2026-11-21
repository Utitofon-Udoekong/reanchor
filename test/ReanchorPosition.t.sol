// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { INonfungiblePositionManager } from "../src/interfaces/INonfungiblePositionManager.sol";
import { ReanchorExecutor } from "../src/ReanchorExecutor.sol";
import { MockERC20, MockPositionManager, MockV3Pool } from "./mocks/MockPositionManager.sol";

contract ReanchorPositionTest is Test {
    int24 internal constant TICK_LOWER = -120;
    int24 internal constant TICK_UPPER = 120;
    int24 internal constant SPACING = 60;
    uint24 internal constant FEE = 3000;
    uint256 internal constant TOKEN_ID = 1;

    ReanchorExecutor internal executor;
    MockPositionManager internal npm;
    MockV3Pool internal pool;
    MockERC20 internal token0;
    MockERC20 internal token1;

    address internal proxy;
    address internal reactive;
    address internal provider;
    address internal stranger;

    function setUp() public {
        proxy = makeAddr("proxy");
        reactive = makeAddr("reactive");
        provider = makeAddr("provider");
        stranger = makeAddr("stranger");

        token0 = new MockERC20();
        token1 = new MockERC20();
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        pool = new MockV3Pool(address(token0), address(token1), FEE, SPACING);
        npm = new MockPositionManager();
        executor = new ReanchorExecutor(IPayable(payable(proxy)), reactive, address(this));
        npm.setExecutor(executor);

        executor.setPositionManager(INonfungiblePositionManager(address(npm)));
        npm.addPosition(
            TOKEN_ID,
            provider,
            MockPositionManager.Position({
                token0: address(token0),
                token1: address(token1),
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                liquidity: 1000
            })
        );
    }

    function test_register_rejectsCallerThatDoesNotOwnTheNft() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ReanchorExecutor.NotPositionOwner.selector, stranger, provider));
        executor.registerPosition(TOKEN_ID);
    }

    function test_register_rejectsOwnerWithoutOperatorApproval() public {
        vm.prank(provider);
        vm.expectRevert(abi.encodeWithSelector(ReanchorExecutor.NotApproved.selector, provider));
        executor.registerPosition(TOKEN_ID);
    }

    function test_configuration_isOwnerOnly() public {
        vm.prank(stranger);
        vm.expectRevert();
        executor.setSlippageBps(100);

        vm.prank(stranger);
        vm.expectRevert();
        executor.setPositionManager(INonfungiblePositionManager(address(npm)));
    }

    function test_onRangeExit_recordsWithoutCallingTheManagerWhenNothingIsRegistered() public {
        _exit(100);

        assertEq(executor.observationCount(), 1);
        assertEq(npm.callStep(), 0);
        (,, int24 tick,,,,,, uint256 callbackTimestamp) = executor.latest();
        assertEq(tick, 100);
        assertEq(callbackTimestamp, block.timestamp);
    }

    function test_onRangeExit_exitsThenMintsACenteredRange() public {
        _register();

        uint256 started = block.timestamp;
        _exit(100);

        assertEq(npm.observationCountAtDecrease(), 1, "observation is stored before the exit");
        assertEq(executor.observationCount(), 1);
        (,,,,,,,, uint256 callbackTimestamp) = executor.latest();
        assertEq(callbackTimestamp, started);

        (uint256 decreasedId, uint128 liquidity, uint256 amount0Min, uint256 amount1Min, uint256 deadline) =
            npm.lastDecrease();
        assertEq(decreasedId, TOKEN_ID);
        assertEq(liquidity, 1000);
        assertEq(amount0Min, 0);
        assertEq(amount1Min, 0);
        assertEq(deadline, started);

        (uint256 collectedId, address recipient, uint128 amount0Max, uint128 amount1Max) = npm.lastCollect();
        assertEq(collectedId, TOKEN_ID);
        assertEq(recipient, address(executor));
        assertEq(amount0Max, type(uint128).max);
        assertEq(amount1Max, type(uint128).max);
        assertEq(npm.burnedTokenId(), TOKEN_ID);
        assertEq(npm.callStep(), 4);

        _assertMint(started);

        (address registeredProvider, uint256 registeredId,,,) = executor.registration();
        assertEq(registeredProvider, provider);
        assertEq(registeredId, 2);
    }

    function test_onRangeExit_revertsWhenThePoolDoesNotMatchThePosition() public {
        _register();
        MockV3Pool other = new MockV3Pool(address(token1), address(token0), FEE, SPACING);

        vm.prank(proxy);
        vm.expectRevert(abi.encodeWithSelector(ReanchorExecutor.PoolMismatch.selector, address(other)));
        executor.onRangeExit(reactive, 84_532, address(other), 100, -100, 100, 1, 2, 3);
        assertEq(executor.observationCount(), 0);
    }

    function _assertMint(uint256 started) internal view {
        (
            address mint0,
            address mint1,
            uint24 fee,
            int24 lower,
            int24 upper,
            uint256 desired0,
            uint256 desired1,
            uint256 min0,
            uint256 min1,
            address mintRecipient,
            uint256 mintDeadline
        ) = npm.lastMint();
        assertEq(mint0, address(token0));
        assertEq(mint1, address(token1));
        assertEq(fee, FEE);
        // Width 240, spacing 60, tick 100. Floor(100 - 120) is -60. Upper is -60 + 240.
        assertEq(lower, -60);
        assertEq(upper, 180);
        assertEq(lower % SPACING, 0);
        assertEq(upper % SPACING, 0);
        assertEq(desired0, npm.BURNED_AMOUNT0());
        assertEq(desired1, npm.BURNED_AMOUNT1());
        assertEq(min0, npm.BURNED_AMOUNT0() * 9950 / 10_000);
        assertEq(min1, npm.BURNED_AMOUNT1() * 9950 / 10_000);
        assertEq(mintRecipient, provider);
        assertEq(mintDeadline, started);
    }

    function _register() internal {
        vm.prank(provider);
        npm.setApprovalForAll(address(executor), true);
        vm.prank(provider);
        executor.registerPosition(TOKEN_ID);
    }

    function _exit(int24 tick) internal {
        vm.prank(proxy);
        executor.onRangeExit(reactive, 84_532, address(pool), tick, -100, 100, 11, 22, 33);
    }
}
