// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

import {PriceCheckerLogicBase} from "./PriceCheckerLogicBase.sol";
import {BaseContract} from "./BaseContract.sol";

import {IDittoOracleV3} from "./IDittoOracleV3.sol";
import {IPriceCheckerLogicUniswap} from "./IPriceCheckerLogicUniswap.sol";

/// @title PriceCheckerLogicUniswap
contract PriceCheckerLogicUniswap is
    IPriceCheckerLogicUniswap,
    BaseContract,
    PriceCheckerLogicBase
{
    // =========================
    // Constructor
    // =========================

    constructor(
        IDittoOracleV3 _dittoOracle,
        address _uniswapFactory
    ) PriceCheckerLogicBase(_dittoOracle, _uniswapFactory) {}

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IPriceCheckerLogicUniswap
    function priceCheckerUniswapInitialize(
        IUniswapV3Pool uniswapPool,
        uint256 targetRate,
        bytes32 pointer
    ) external onlyVaultItself {
        _priceCheckerInitialize(uniswapPool, targetRate, pointer);
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IPriceCheckerLogicUniswap
    function uniswapCheckGTTargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkGTTargetRate(pointer);
    }

    /// @inheritdoc IPriceCheckerLogicUniswap
    function uniswapCheckGTETargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkGTETargetRate(pointer);
    }

    /// @inheritdoc IPriceCheckerLogicUniswap
    function uniswapCheckLTTargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkLTTargetRate(pointer);
    }

    /// @inheritdoc IPriceCheckerLogicUniswap
    function uniswapCheckLTETargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkLTETargetRate(pointer);
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc IPriceCheckerLogicUniswap
    function uniswapChangeTokensAndFeePriceChecker(
        IUniswapV3Pool uniswapPool,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changeTokensAndFeePriceChecker(uniswapPool, pointer);
    }

    /// @inheritdoc IPriceCheckerLogicUniswap
    function uniswapChangeTargetRate(
        uint256 targetRate,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changeTargetRate(targetRate, pointer);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IPriceCheckerLogicUniswap
    function uniswapGetLocalPriceCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint256 targetRate,
            bool initialized
        )
    {
        PriceCheckerStorage storage pcs = _getStorageUnsafe(pointer);

        return (
            pcs.token0,
            pcs.token1,
            pcs.fee,
            pcs.targetRate,
            pcs.initialized
        );
    }
}

