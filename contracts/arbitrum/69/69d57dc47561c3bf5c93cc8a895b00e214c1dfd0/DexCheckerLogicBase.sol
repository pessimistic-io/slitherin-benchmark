// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

import {PositionValueMod} from "./PositionValueMod.sol";
import {BaseContract} from "./BaseContract.sol";
import {DexLogicLib} from "./DexLogicLib.sol";

import {IDexCheckerLogicBase} from "./IDexCheckerLogicBase.sol";

/// @title DexCheckerLogicPancakeswap
contract DexCheckerLogicBase is IDexCheckerLogicBase, BaseContract {
    // =========================
    // Constructor
    // =========================

    IUniswapV3Factory private immutable dexFactory;
    INonfungiblePositionManager private immutable dexNftPositionManager;

    constructor(
        IUniswapV3Factory _dexFactory,
        INonfungiblePositionManager _dexNftPositionManager
    ) {
        dexFactory = _dexFactory;
        dexNftPositionManager = _dexNftPositionManager;
    }

    // =========================
    // Storage
    // =========================

    /// @dev Fetches the checker storage without initialization check.
    /// @dev Uses inline assembly to point to the specific storage slot.
    /// Be cautious while using this.
    /// @param pointer Pointer to the storage location.
    /// @return s The storage slot for DexCheckerStorage structure.
    function _getStorageUnsafe(
        bytes32 pointer
    ) internal pure returns (DexCheckerStorage storage s) {
        assembly ("memory-safe") {
            s.slot := pointer
        }
    }

    /// @dev Fetches the checker storage after checking initialization.
    /// @dev Reverts if the strategy is not initialized.
    /// @param pointer Pointer to the strategy's storage location.
    /// @return s The storage slot for DexCheckerStorage structure.
    function _getStorage(
        bytes32 pointer
    ) internal view returns (DexCheckerStorage storage s) {
        s = _getStorageUnsafe(pointer);

        if (!s.initialized) {
            revert DexChecker_NotInitialized();
        }
    }

    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the DexChecker with the given NFT ID and pointer.
    /// @dev This function sets the initialization flag and assigns the provided NFT ID to the storage.
    /// It reverts if the DexChecker is already initialized.
    /// @param nftId The ID of the NFT to be associated with the DexChecker.
    /// @param pointer The pointer referencing the DexChecker's storage.
    function _dexCheckerInitialize(
        uint256 nftId,
        bytes32 pointer
    ) internal onlyVaultItself {
        DexCheckerStorage storage s = _getStorageUnsafe(pointer);

        if (s.initialized) {
            revert DexChecker_AlreadyInitialized();
        }
        s.initialized = true;

        s.nftId = nftId;

        emit DexCheckerInitialized();
    }

    // =========================
    // Main functions
    // =========================

    /// @dev Retrieves the NFT data using the DexLogicLib, and the current tick of the dex pool.
    /// @param pointer The pointer referencing the DexChecker's storage.
    /// @return Returns lowerTick and upperTick of the nft and current tick of the dex pool.
    function _getTickRangeAndCurrentTick(
        bytes32 pointer
    ) internal view returns (int24, int24, int24) {
        DexCheckerStorage storage s = _getStorage(pointer);

        (
            address token0,
            address token1,
            uint24 poolFee,
            int24 tickLower,
            int24 tickUpper,

        ) = DexLogicLib.getNftData(s.nftId, dexNftPositionManager);

        IUniswapV3Pool dexPool = DexLogicLib.dexPool(
            token0,
            token1,
            poolFee,
            dexFactory
        );

        (, bytes memory data) = address(dexPool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, uint16, uint16, uint16, uint256, bool)
        );

        return (tickLower, tickUpper, currentTick);
    }

    /// @dev Checks if fees exist for the NFT position in the Uniswap V3 pool.
    /// @dev This function retrieves the NFT data using the DexLogicLib and checks if there are any fees
    /// accumulated for the NFT position in the Uniswap V3 pool.
    /// @param pointer The pointer referencing the DexChecker's storage.
    /// @return Returns true if either of the fees (amount0 or amount1) is greater than 0, otherwise returns false.
    function _checkFeesExistence(bytes32 pointer) internal view returns (bool) {
        DexCheckerStorage storage s = _getStorage(pointer);

        uint256 nftId = s.nftId;

        (address token0, address token1, uint24 poolFee, , , ) = DexLogicLib
            .getNftData(nftId, dexNftPositionManager);

        IUniswapV3Pool dexPool = DexLogicLib.dexPool(
            token0,
            token1,
            poolFee,
            dexFactory
        );

        (uint256 amount0, uint256 amount1) = PositionValueMod.fees(
            dexNftPositionManager,
            nftId,
            dexPool
        );

        return amount0 > 0 || amount1 > 0;
    }
}

