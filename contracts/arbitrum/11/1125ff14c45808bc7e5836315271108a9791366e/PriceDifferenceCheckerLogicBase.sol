// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IDittoOracleV3} from "./IDittoOracleV3.sol";
import {IPriceDifferenceCheckerLogicBase} from "./IPriceDifferenceCheckerLogicBase.sol";

/// @title PriceDifferenceCheckerLogicBase
abstract contract PriceDifferenceCheckerLogicBase is
    IPriceDifferenceCheckerLogicBase
{
    // =========================
    // Constructor
    // =========================

    IDittoOracleV3 private immutable dittoOracle;
    address private immutable dexFactory;

    uint128 private constant E3 = 1000;
    uint128 private constant _2E3 = 2000;

    constructor(IDittoOracleV3 _dittoOracle, address _dexFactory) {
        dittoOracle = _dittoOracle;
        dexFactory = _dexFactory;
    }

    // =========================
    // Storage
    // =========================

    /// @dev Fetches the checker storage without initialization check.
    /// @dev Uses inline assembly to point to the specific storage slot.
    /// Be cautious while using this.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for PriceDifferenceCheckerStorage structure.
    function _getStorageUnsafe(
        bytes32 pointer
    ) internal pure returns (PriceDifferenceCheckerStorage storage s) {
        assembly ("memory-safe") {
            s.slot := pointer
        }
    }

    /// @dev Fetches the checker storage after checking initialization.
    /// @dev Reverts if the strategy is not initialized.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for strategyStorage structure.
    function _getStorage(
        bytes32 pointer
    ) internal view returns (PriceDifferenceCheckerStorage storage s) {
        s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            revert PriceDifferenceChecker_NotInitialized();
        }
    }

    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the PriceDifferenceChecker contract by setting the token addresses and percentage of difference.
    /// @param dexPool The Uniswap V3 pool from which to check the price.
    /// @param percentageDeviation_E3 The percentage of difference allowed between the two token prices.
    /// @param pointer The bytes32 pointer value.
    function _priceDifferenceCheckerInitialize(
        IUniswapV3Pool dexPool,
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) internal {
        PriceDifferenceCheckerStorage storage s = _getStorageUnsafe(pointer);

        if (s.initialized) {
            revert PriceDifferenceChecker_AlreadyInitialized();
        }

        s.initialized = true;

        _changeTokensAndFee(dexPool, s);
        _setPercentageDeviation(percentageDeviation_E3, s);

        emit PriceDifferenceCheckerInitialized();
    }

    // =========================
    // Main functions
    // =========================

    /// @notice Checks the percentage difference between the current price and the last checked price.
    /// @dev Updates the last recorded price in the state.
    /// @param pointer The bytes32 pointer value.
    /// @return success True if the percentage difference is within an acceptable range.
    function _checkPriceDifference(
        bytes32 pointer
    ) internal returns (bool success) {
        PriceDifferenceCheckerStorage storage s = _getStorage(pointer);

        uint256 currentPrice;
        (success, currentPrice) = _checkPriceDifference(s);
        if (success) {
            s.lastCheckPrice = currentPrice;
        }
    }

    /// @notice Checks the percentage difference between the current price and the last checked price.
    /// @param pointer The bytes32 pointer value.
    /// @return success True if the percentage difference is within an acceptable range.
    function _checkPriceDifferenceView(
        bytes32 pointer
    ) public view returns (bool success) {
        PriceDifferenceCheckerStorage storage s = _getStorage(pointer);
        (success, ) = _checkPriceDifference(s);
    }

    /// @notice Sets the tokens for the pool.
    /// @param dexPool The Uniswap V3 pool from which to check the price.
    /// @param pointer The bytes32 pointer value.
    function _changeTokensAndFeePriceDiffChecker(
        IUniswapV3Pool dexPool,
        bytes32 pointer
    ) internal {
        PriceDifferenceCheckerStorage storage s = _getStorage(pointer);

        _changeTokensAndFee(dexPool, s);
    }

    /// @notice Sets the percentage of difference for the contract.
    /// @param percentageDeviation_E3 The percentage of difference to be set.
    /// @param pointer The bytes32 pointer value.
    function _changePercentageDeviationE3(
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) internal {
        PriceDifferenceCheckerStorage storage s = _getStorage(pointer);

        _setPercentageDeviation(percentageDeviation_E3, s);
    }

    function _getLocalPriceDifferenceCheckerStorage(
        bytes32 pointer
    )
        internal
        pure
        returns (
            PriceDifferenceCheckerStorage memory priceDifferenceCheckerStorage
        )
    {
        priceDifferenceCheckerStorage = _getStorageUnsafe(pointer);
    }

    // =========================
    // Private functions
    // =========================

    /// @dev Fetches the last price rate from uniswapV3 pool.
    /// @param token0 The token0 from the uniswapV3 pool.
    /// @param token1 The token1 from the uniswapV3 pool.
    /// @param fee The feeTier from the uniswapV3 pool.
    function _getLastCheckPrice(
        address token0,
        address token1,
        uint24 fee
    ) private view returns (uint256) {
        IERC20Metadata _token0 = IERC20Metadata(token0);

        uint256 amount;
        unchecked {
            amount = 10 ** _token0.decimals();
        }

        return dittoOracle.consult(token0, amount, token1, fee, dexFactory);
    }

    /// @dev Checks the percentage difference between the current price and the last checked price.
    /// @param s The storage slot for PriceDifferenceCheckerStorage structure.
    /// @return success True if the percentage difference is within an acceptable range.
    /// @return currentPrice The current price of the tokens.
    function _checkPriceDifference(
        PriceDifferenceCheckerStorage storage s
    ) private view returns (bool success, uint256 currentPrice) {
        currentPrice = _getLastCheckPrice(s.token0, s.token1, s.fee);

        uint24 percentageDeviation_E3 = s.percentageDeviation_E3;

        if (percentageDeviation_E3 > E3) {
            unchecked {
                success =
                    currentPrice >
                    (s.lastCheckPrice * (percentageDeviation_E3)) / E3;
            }
        } else {
            unchecked {
                success =
                    currentPrice <
                    (s.lastCheckPrice * (percentageDeviation_E3)) / E3;
            }
        }
    }

    /// @dev Sets the percentage deviation for checker.
    /// @param percentageDeviation_E3 The percentage deviation to be set.
    /// @param s The storage slot for PriceDifferenceCheckerStorage structure.
    function _setPercentageDeviation(
        uint24 percentageDeviation_E3,
        PriceDifferenceCheckerStorage storage s
    ) private {
        if (percentageDeviation_E3 > _2E3) {
            revert PriceDifferenceChecker_InvalidPercentageDeviation();
        }

        s.percentageDeviation_E3 = percentageDeviation_E3;

        emit PriceDifferenceCheckerSetNewDeviationThreshold(
            percentageDeviation_E3
        );
    }

    /// @dev Sets the tokens and feeTier from the pair to checker storage.
    /// @param dexPool The pool to fetch the tokens and fee from.
    /// @param s The storage slot for PriceCheckerStorage structure.
    function _changeTokensAndFee(
        IUniswapV3Pool dexPool,
        PriceDifferenceCheckerStorage storage s
    ) private {
        address token0 = dexPool.token0();
        address token1 = dexPool.token1();
        uint24 fee = dexPool.fee();

        s.token0 = token0;
        s.token1 = token1;
        s.fee = fee;
        s.lastCheckPrice = _getLastCheckPrice(token0, token1, fee);

        emit PriceDifferenceCheckerSetNewTokensAndFee(token0, token1, fee);
    }
}

