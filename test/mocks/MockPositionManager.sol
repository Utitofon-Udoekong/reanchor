// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { INonfungiblePositionManager } from "../../src/interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3PoolImmutables } from "../../src/interfaces/IUniswapV3PoolImmutables.sol";
import { ReanchorExecutor } from "../../src/ReanchorExecutor.sol";

/// @notice Pool immutables the executor reads. No swap logic.
contract MockV3Pool is IUniswapV3PoolImmutables {
    address public token0;
    address public token1;
    uint24 public fee;
    int24 public tickSpacing;

    constructor(address token0_, address token1_, uint24 fee_, int24 tickSpacing_) {
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickSpacing = tickSpacing_;
    }
}

/// @notice ERC-20 that records approvals and can hold a balance for the refund path.
contract MockERC20 {
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public balanceOf;

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

/// @notice Records the periphery calls Reanchor makes. Implements the official signatures.
contract MockPositionManager is INonfungiblePositionManager {
    struct Position {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    uint256 public constant BURNED_AMOUNT0 = 1_000_000;
    uint256 public constant BURNED_AMOUNT1 = 2_000_000;
    uint256 public nextTokenId = 2;

    mapping(uint256 => Position) internal _positions;
    mapping(uint256 => address) public ownerOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    ReanchorExecutor public executor;
    uint256 public observationCountAtDecrease;

    DecreaseLiquidityParams public lastDecrease;
    CollectParams public lastCollect;
    uint256 public burnedTokenId;
    MintParams public lastMint;
    uint8 public callStep;

    function setExecutor(ReanchorExecutor executor_) external {
        executor = executor_;
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function addPosition(uint256 tokenId, address owner, Position memory position) external {
        _positions[tokenId] = position;
        ownerOf[tokenId] = owner;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        token0 = position.token0;
        token1 = position.token1;
        fee = position.fee;
        tickLower = position.tickLower;
        tickUpper = position.tickUpper;
        liquidity = position.liquidity;
        nonce = 0;
        operator = address(0);
        feeGrowthInside0LastX128 = 0;
        feeGrowthInside1LastX128 = 0;
        tokensOwed0 = 0;
        tokensOwed1 = 0;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {
        callStep = 1;
        lastDecrease = params;
        if (address(executor) != address(0)) observationCountAtDecrease = executor.observationCount();
        amount0 = BURNED_AMOUNT0;
        amount1 = BURNED_AMOUNT1;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {
        callStep = 2;
        lastCollect = params;
        amount0 = BURNED_AMOUNT0;
        amount1 = BURNED_AMOUNT1;
    }

    function burn(uint256 tokenId) external payable {
        callStep = 3;
        burnedTokenId = tokenId;
        ownerOf[tokenId] = address(0);
        _positions[tokenId].liquidity = 0;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        callStep = 4;
        lastMint = params;
        tokenId = nextTokenId;
        ownerOf[tokenId] = params.recipient;
        liquidity = 1;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        nextTokenId += 1;
    }
}
