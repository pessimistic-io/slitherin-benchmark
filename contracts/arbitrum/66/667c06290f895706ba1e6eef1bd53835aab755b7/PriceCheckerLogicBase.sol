// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20Metadata} from "./IERC20Metadata.sol";

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

import {IDittoOracleV3} from "./IDittoOracleV3.sol";
import {IPriceCheckerLogicBase} from "./IPriceCheckerLogicBase.sol";

/// @title PriceCheckerLogicBase
abstract contract PriceCheckerLogicBase is IPriceCheckerLogicBase {
    // =========================
    // Constructor
    // =========================

    IDittoOracleV3 private immutable dittoOracle;
    address private immutable dexFactory;

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
    /// @return s The storage slot for PriceCheckerStorage structure.
    function _getStorageUnsafe(
        bytes32 pointer
    ) internal pure returns (PriceCheckerStorage storage s) {
        assembly ("memory-safe") {
            s.slot := pointer
        }
    }

    /// @dev Fetches the checker storage after checking initialization.
    /// @dev Reverts if the strategy is not initialized.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for PriceCheckerStorage structure.
    function _getStorage(
        bytes32 pointer
    ) internal view returns (PriceCheckerStorage storage s) {
        s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            revert PriceChecker_NotInitialized();
        }
    }

    // =========================
    // Initializer
    // =========================

    /// @dev Initializes the price checker
    /// @param targetRate The target exchange rate between the tokens
    function _priceCheckerInitialize(
        IUniswapV3Pool dexPool,
        uint256 targetRate,
        bytes32 pointer
    ) internal {
        PriceCheckerStorage storage s = _getStorageUnsafe(pointer);

        if (s.initialized) {
            revert PriceChecker_AlreadyInitialized();
        }
        s.initialized = true;

        _changeTokensAndFee(dexPool, s);
        s.targetRate = targetRate;

        emit PriceCheckerInitialized();
    }

    // =========================
    // Main functions
    // =========================

    /// @dev Checks if the current rate is greater than the target rate.
    /// @return true if the current rate is greater than the target rate, otherwise false.
    function _checkGTTargetRate(bytes32 pointer) internal view returns (bool) {
        PriceCheckerStorage storage s = _getStorage(pointer);

        return _currentRate(s) > s.targetRate;
    }

    /// @dev Checks if the current rate is greater than or equal to the target rate.
    /// @return bool indicating whether the current rate is greater than or equal to the target rate.
    function _checkGTETargetRate(bytes32 pointer) internal view returns (bool) {
        PriceCheckerStorage storage s = _getStorage(pointer);

        return _currentRate(s) >= s.targetRate;
    }

    /// @dev Checks if the current rate is less than the target rate.
    /// @return true if the current rate is less than the target rate, otherwise false.
    function _checkLTTargetRate(bytes32 pointer) internal view returns (bool) {
        PriceCheckerStorage storage s = _getStorage(pointer);

        return _currentRate(s) < s.targetRate;
    }

    /// @dev Checks if the current rate is less than or equal to the target rate.
    /// @return bool indicating whether the current rate is less than or equal to the target rate.
    function _checkLTETargetRate(bytes32 pointer) internal view returns (bool) {
        PriceCheckerStorage storage s = _getStorage(pointer);

        return _currentRate(s) <= s.targetRate;
    }

    /// @dev Sets the tokens for the pair
    /// Requirements:
    /// - Caller must have the `OWNER_ROLE`
    function _changeTokensAndFeePriceChecker(
        IUniswapV3Pool dexPool,
        bytes32 pointer
    ) internal {
        PriceCheckerStorage storage s = _getStorage(pointer);

        _changeTokensAndFee(dexPool, s);
    }

    /// @dev Set the target rate of the contract.
    /// @param targetRate The new target rate to be set.
    /// Requirements:
    /// - Caller must have the `OWNER_ROLE`
    function _changeTargetRate(uint256 targetRate, bytes32 pointer) internal {
        _getStorage(pointer).targetRate = targetRate;
        emit PriceCheckerSetNewTarget(targetRate);
    }

    // =========================
    // Private functions
    // =========================

    /// @dev Fetches the current token0 to token1 rate of the pair.
    /// @param s The storage slot for PriceCheckerStorage structure.
    /// @return The current rate of the pair.
    function _currentRate(
        PriceCheckerStorage storage s
    ) private view returns (uint256) {
        address token0 = s.token0;
        IERC20Metadata _token0 = IERC20Metadata(token0);

        uint256 amount;
        unchecked {
            amount = 10 ** _token0.decimals();
        }

        return dittoOracle.consult(token0, amount, s.token1, s.fee, dexFactory);
    }

    /// @dev Sets the tokens and feeTier from the pair to checker storage.
    /// @param dexPool The pool to fetch the tokens and fee from.
    /// @param s The storage slot for PriceCheckerStorage structure.
    function _changeTokensAndFee(
        IUniswapV3Pool dexPool,
        PriceCheckerStorage storage s
    ) private {
        address token0 = dexPool.token0();
        address token1 = dexPool.token1();
        uint24 fee = dexPool.fee();

        s.token0 = token0;
        s.token1 = token1;
        s.fee = fee;

        emit PriceCheckerSetNewTokensAndFee(token0, token1, fee);
    }
}

