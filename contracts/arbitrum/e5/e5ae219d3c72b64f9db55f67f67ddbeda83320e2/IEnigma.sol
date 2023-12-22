// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;
//pragma abicoder v2;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

import {IMulticall} from "./IMulticall.sol";
import {ISelfPermit} from "./ISelfPermit.sol";
import "./IERC20.sol";

interface IEnigma {
    /// @notice Emitted when liquidity is decreased via withdrawal
    /// @param sender The msg.sender address
    event Deposit(address indexed sender);

    /// @param tickLower lower tick of the uniV3 position
    /// @param tickUpper upper tick of the uniV3 position
    /// @param feeTier upper tick of the uniV3 position
    /// @param distribution upper tick of the uniV3 position
    struct Range {
        int24 tickLower;
        int24 tickUpper;
        int24 feeTier;
        uint256 distribution;
    }

    struct PositionLiquidity {
        uint128 liquidity;
        Range range;
    }

    struct SwapPayload {
        bytes payload;
        address router;
        uint256 amountIn;
        uint256 expectedMinReturn;
        bool zeroForOne;
    }

    struct Rebalance {
        PositionLiquidity[] burns;
        PositionLiquidity[] mints;
        SwapPayload swap;
        uint256 minBurn0;
        uint256 minBurn1;
        uint256 minDeposit0;
        uint256 minDeposit1;
    }

    struct Withdraw {
        uint256 fee0;
        uint256 fee1;
        uint256 burn0;
        uint256 burn1;
    }

    /// @param key The Bunni position's key
    /// @param amount0Desired The desired amount of token0 to be spent,
    /// @param amount1Desired The desired amount of token1 to be spent,
    /// @param amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// @param amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// @param deadline The time by which the transaction must be included to effect the change
    /// @param from The sender of the tokens share tokens
    /// @param recipient The recipient of the minted share tokens
    struct DepositParams {
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        address from;
        address recipient;
    }

    struct BurnParams {
        address _pool;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        address to;
        bool collectAll;
    }

    function getFactory() external view returns (address factory_);

    function deposit(DepositParams calldata params)
        external
        payable
        returns (uint256 shares, uint256 amount0, uint256 amount1);
}

