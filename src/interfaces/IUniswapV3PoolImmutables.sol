// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Pool immutables Reanchor reads while aligning a new range.
/// @dev Signatures match Uniswap v3-core
///      `contracts/interfaces/pool/IUniswapV3PoolImmutables.sol`.
///      Tick spacing: ticks can only be used at multiples of this value.
///      https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol
interface IUniswapV3PoolImmutables {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function fee() external view returns (uint24);

    function tickSpacing() external view returns (int24);
}
