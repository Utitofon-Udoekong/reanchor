// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title ReanchorSwapSource
/// @notice Origin-chain helper that emits the Uniswap V3 pool `Swap` event.
///         ReanchorReactive subscribes to this log and treats it as a pool swap.
contract ReanchorSwapSource {
    /// @dev Same signature as `IUniswapV3PoolEvents.Swap`.
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    /// @notice Emits one Swap at `tick_`. `sqrtPriceX96` is 2^96, a price of 1.
    function emitSwap(int24 tick_) external {
        emit Swap(msg.sender, msg.sender, int256(1), int256(-1), uint160(1 << 96), uint128(1), tick_);
    }
}
