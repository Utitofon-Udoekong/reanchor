// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { ReanchorSwapSource } from "../src/ReanchorSwapSource.sol";

contract ReanchorSwapSourceTest is Test {
    bytes32 internal constant SWAP_TOPIC_0 =
        keccak256("Swap(address,address,int256,int256,uint160,uint128,int24)");

    function test_emitSwap_usesUniswapV3Topic() public {
        ReanchorSwapSource source = new ReanchorSwapSource();

        vm.expectEmit(true, true, false, true, address(source));
        emit ReanchorSwapSource.Swap(
            address(this), address(this), int256(1), int256(-1), uint160(1 << 96), uint128(1), 100
        );
        source.emitSwap(100);

        assertEq(SWAP_TOPIC_0, bytes32(0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67));
    }
}
