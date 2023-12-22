// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

import {BaseContract} from "./BaseContract.sol";
import {PriceDifferenceCheckerLogicBase} from "./PriceDifferenceCheckerLogicBase.sol";

import {IDittoOracleV3} from "./IDittoOracleV3.sol";
import {IPriceDifferenceCheckerLogicUniswap} from "./IPriceDifferenceCheckerLogicUniswap.sol";

/// @title PriceDifferenceCheckerLogicUniswap
contract PriceDifferenceCheckerLogicUniswap is
    IPriceDifferenceCheckerLogicUniswap,
    BaseContract,
    PriceDifferenceCheckerLogicBase
{
    // =========================
    // Constructor
    // =========================

    constructor(
        IDittoOracleV3 _dittoOracle,
        address _uniswapFactory
    ) PriceDifferenceCheckerLogicBase(_dittoOracle, _uniswapFactory) {}

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicUniswap
    function priceDifferenceCheckerUniswapInitialize(
        IUniswapV3Pool uniswapPool,
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) external onlyVaultItself {
        _priceDifferenceCheckerInitialize(
            uniswapPool,
            percentageDeviation_E3,
            pointer
        );
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicUniswap
    function uniswapCheckPriceDifference(
        bytes32 pointer
    ) external onlyVaultItself returns (bool success) {
        return _checkPriceDifference(pointer);
    }

    /// @inheritdoc IPriceDifferenceCheckerLogicUniswap
    function uniswapCheckPriceDifferenceView(
        bytes32 pointer
    ) external view returns (bool success) {
        return _checkPriceDifferenceView(pointer);
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicUniswap
    function uniswapChangeTokensAndFeePriceDiffChecker(
        IUniswapV3Pool uniswapPool,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changeTokensAndFeePriceDiffChecker(uniswapPool, pointer);
    }

    /// @inheritdoc IPriceDifferenceCheckerLogicUniswap
    function uniswapChangePercentageDeviationE3(
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changePercentageDeviationE3(percentageDeviation_E3, pointer);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicUniswap
    function uniswapGetLocalPriceDifferenceCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint24 percentageDeviation_E3,
            uint256 lastCheckPrice,
            bool initialized
        )
    {
        PriceDifferenceCheckerStorage storage pdcs = _getStorageUnsafe(pointer);

        return (
            pdcs.token0,
            pdcs.token1,
            pdcs.fee,
            pdcs.percentageDeviation_E3,
            pdcs.lastCheckPrice,
            pdcs.initialized
        );
    }
}

