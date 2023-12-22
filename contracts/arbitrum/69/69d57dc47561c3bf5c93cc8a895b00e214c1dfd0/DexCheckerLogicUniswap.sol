// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

import {IDexCheckerLogicUniswap} from "./IDexCheckerLogicUniswap.sol";
import {DexCheckerLogicBase} from "./DexCheckerLogicBase.sol";

/// @title DexCheckerLogicUniswap
contract DexCheckerLogicUniswap is
    IDexCheckerLogicUniswap,
    DexCheckerLogicBase
{
    constructor(
        IUniswapV3Factory _uniswapFactory,
        INonfungiblePositionManager _uniswapNftPositionManager
    ) DexCheckerLogicBase(_uniswapFactory, _uniswapNftPositionManager) {}

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IDexCheckerLogicUniswap
    function uniswapDexCheckerInitialize(
        uint256 nftId,
        bytes32 pointer
    ) external onlyVaultItself {
        _dexCheckerInitialize(nftId, pointer);
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IDexCheckerLogicUniswap
    function uniswapCheckOutOfTickRange(
        bytes32 pointer
    ) external view returns (bool) {
        (
            int24 lowerTick,
            int24 upperTick,
            int24 currentTick
        ) = _getTickRangeAndCurrentTick(pointer);

        return (currentTick < lowerTick || currentTick > upperTick);
    }

    /// @inheritdoc IDexCheckerLogicUniswap
    function uniswapCheckInTickRange(
        bytes32 pointer
    ) external view returns (bool) {
        (
            int24 lowerTick,
            int24 upperTick,
            int24 currentTick
        ) = _getTickRangeAndCurrentTick(pointer);

        return (currentTick >= lowerTick && currentTick <= upperTick);
    }

    /// @inheritdoc IDexCheckerLogicUniswap
    function uniswapCheckFeesExistence(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkFeesExistence(pointer);
    }

    // =========================
    // Getter
    // =========================

    /// @inheritdoc IDexCheckerLogicUniswap
    function uniswapGetLocalDexCheckerStorage(
        bytes32 pointer
    ) external view returns (uint256 nftId) {
        return _getStorageUnsafe(pointer).nftId;
    }
}

