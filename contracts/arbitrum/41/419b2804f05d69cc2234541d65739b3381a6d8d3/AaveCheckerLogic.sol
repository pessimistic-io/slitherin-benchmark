// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPool} from "./IPool.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";

import {BaseContract} from "./BaseContract.sol";

import {IAaveCheckerLogic} from "./IAaveCheckerLogic.sol";

/// @title AaveCheckerLogic
contract AaveCheckerLogic is IAaveCheckerLogic, BaseContract {
    IPoolAddressesProvider private immutable poolAddressesProvider;

    uint128 constant E18 = 1e18;

    constructor(IPoolAddressesProvider _poolAddressesProvider) {
        poolAddressesProvider = _poolAddressesProvider;
    }

    // =========================
    // Storage
    // =========================

    /// @dev Fetches the checker storage without initialization check.
    /// @dev Uses inline assembly to point to the specific storage slot.
    /// Be cautious while using this.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for AaveCheckerStorage structure.
    function _getStorageUnsafe(
        bytes32 pointer
    ) internal pure returns (AaveCheckerStorage storage s) {
        assembly ("memory-safe") {
            s.slot := pointer
        }
    }

    /// @dev Fetches the checker storage after checking initialization.
    /// @dev Reverts if the strategy is not initialized.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for AaveCheckerStorage structure.
    function _getStorage(
        bytes32 pointer
    ) internal view returns (AaveCheckerStorage storage s) {
        s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            revert AaveChecker_NotInitialized();
        }
    }

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IAaveCheckerLogic
    function aaveCheckerInitialize(
        uint128 lowerHFBoundary,
        uint128 upperHFBoundary,
        address user,
        bytes32 pointer
    ) external onlyVaultItself {
        AaveCheckerStorage storage s = _getStorageUnsafe(pointer);

        if (s.initialized) {
            revert AaveChecker_AlreadyInitialized();
        }

        _validateHealthFactors(lowerHFBoundary, upperHFBoundary);

        s.initialized = true;

        s.lowerHFBoundary = lowerHFBoundary;
        s.upperHFBoundary = upperHFBoundary;
        s.user = user;

        emit AaveCheckerInitialized();
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IAaveCheckerLogic
    function checkHF(bytes32 pointer) external view returns (bool) {
        AaveCheckerStorage storage s = _getStorage(pointer);

        IPool aavePool = IPool(poolAddressesProvider.getPool());

        (, , , , , uint256 healthFactor) = aavePool.getUserAccountData(s.user);
        return (healthFactor <= s.lowerHFBoundary ||
            healthFactor >= s.upperHFBoundary);
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc IAaveCheckerLogic
    function setHFBoundaries(
        uint128 lowerHFBoundary,
        uint128 upperHFBoundary,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _validateHealthFactors(lowerHFBoundary, upperHFBoundary);

        AaveCheckerStorage storage s = _getStorage(pointer);

        s.lowerHFBoundary = lowerHFBoundary;
        s.upperHFBoundary = upperHFBoundary;
        emit AaveCheckerSetNewHF(lowerHFBoundary, upperHFBoundary);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IAaveCheckerLogic
    function getHFBoundaries(
        bytes32 pointer
    ) external view returns (uint256 lowerHFBoundary, uint256 upperHFBoundary) {
        AaveCheckerStorage storage s = _getStorage(pointer);

        return (s.lowerHFBoundary, s.upperHFBoundary);
    }

    /// @inheritdoc IAaveCheckerLogic
    function getLocalAaveCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            uint256 lowerHFBoundary,
            uint256 upperHFBoundary,
            address user,
            bool initialized
        )
    {
        AaveCheckerStorage storage s = _getStorageUnsafe(pointer);

        return (s.lowerHFBoundary, s.upperHFBoundary, s.user, s.initialized);
    }

    // =========================
    // Internal functions
    // =========================

    /// @dev Helper function to validate health factors.
    /// @param lowerHFBoundary Lower health factor boundary.
    /// @param upperHFBoundary Upper health factor boundary.
    function _validateHealthFactors(
        uint256 lowerHFBoundary,
        uint256 upperHFBoundary
    ) internal pure {
        if (lowerHFBoundary < E18 || upperHFBoundary <= lowerHFBoundary) {
            revert AaveChecker_IncorrectHealthFators();
        }
    }
}

