// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {IV3SwapRouter} from "./IV3SwapRouter.sol";
import {IWETH9} from "./IWETH9.sol";

import {BaseContract} from "./BaseContract.sol";

import {DexBaseLogic} from "./DexBaseLogic.sol";

import {IUniswapLogic} from "./IUniswapLogic.sol";

/// @title UniswapLogic.
/// @notice This contract contains logic for operations related to Uniswap V3.
contract UniswapLogic is IUniswapLogic, DexBaseLogic, BaseContract {
    // =========================
    // Constructor
    // =========================

    /// @notice Sets the immutable variables for the contract.
    /// @param _uniNftPositionManager Instance of the Uniswap Nonfungible Position Manager.
    /// @param _uniswapRouter Instance of the Uniswap V3 Swap Router.
    /// @param _uniswapFactory Instance of the Uniswap V3 Factory.
    constructor(
        INonfungiblePositionManager _uniNftPositionManager,
        IV3SwapRouter _uniswapRouter,
        IUniswapV3Factory _uniswapFactory,
        IWETH9 _wNative
    )
        DexBaseLogic(
            _uniNftPositionManager,
            _uniswapRouter,
            _uniswapFactory,
            _wNative
        )
    {}

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IUniswapLogic
    function uniswapChangeTickRange(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 nftId,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256) {
        uint256 newNftId = _changeTickRange(
            newLowerTick,
            newUpperTick,
            nftId,
            deviationThresholdE18
        );

        emit UniswapChangeTickRange(nftId, newNftId);

        return newNftId;
    }

    /// @inheritdoc IUniswapLogic
    function uniswapMintNft(
        IUniswapV3Pool uniswapPool,
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 token0Amount,
        uint256 token1Amount,
        bool useFullTokenBalancesFromVault,
        bool swap,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256) {
        uint256 newNftId = _mintNft(
            uniswapPool,
            newLowerTick,
            newUpperTick,
            token0Amount,
            token1Amount,
            useFullTokenBalancesFromVault,
            swap,
            deviationThresholdE18
        );

        emit UniswapMintNft(newNftId);

        return newNftId;
    }

    /// @inheritdoc IUniswapLogic
    function uniswapAddLiquidity(
        uint256 nftId,
        uint256 token0Amount,
        uint256 token1Amount,
        bool useFullTokenBalancesFromVault,
        bool swap,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _addLiquidity(
            nftId,
            token0Amount,
            token1Amount,
            useFullTokenBalancesFromVault,
            swap,
            deviationThresholdE18
        );
        emit UniswapAddLiquidity(nftId);
    }

    /// @inheritdoc IUniswapLogic
    function uniswapAutoCompound(
        uint256 nftId,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _autoCompound(nftId, deviationThresholdE18);

        emit UniswapAutoCompound(nftId);
    }

    /// @inheritdoc IUniswapLogic
    function uniswapSwapExactInput(
        address[] calldata tokens,
        uint24[] calldata poolFees,
        uint256 amountIn,
        bool useFullBalanceOfTokenInFromVault,
        bool unwrapInTheEnd,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256 amountOut) {
        amountOut = _swapExactInput(
            tokens,
            poolFees,
            amountIn,
            useFullBalanceOfTokenInFromVault,
            unwrapInTheEnd,
            deviationThresholdE18
        );
    }

    /// @inheritdoc IUniswapLogic
    function uniswapSwapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountOut,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256 amountIn) {
        amountIn = _swapExactOutputSingle(
            tokenIn,
            tokenOut,
            poolFee,
            amountOut,
            deviationThresholdE18
        );
    }

    /// @inheritdoc IUniswapLogic
    function uniswapSwapToTargetR(
        uint256 deviationThresholdE18,
        IUniswapV3Pool uniswapPool,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 targetRE18
    ) external onlyVaultItself returns (uint256, uint256) {
        (token0Amount, token1Amount) = _swapToTargetR(
            deviationThresholdE18,
            uniswapPool,
            token0Amount,
            token1Amount,
            targetRE18
        );

        return (token0Amount, token1Amount);
    }

    /// @inheritdoc IUniswapLogic
    function uniswapWithdrawPositionByShares(
        uint256 nftId,
        uint128 sharesE18,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _withdrawPositionByShares(nftId, sharesE18, deviationThresholdE18);

        emit UniswapWithdraw(nftId);
    }

    /// @inheritdoc IUniswapLogic
    function uniswapWithdrawPositionByLiquidity(
        uint256 nftId,
        uint128 liquidity,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _withdrawPositionByLiquidity(nftId, liquidity, deviationThresholdE18);

        emit UniswapWithdraw(nftId);
    }

    /// @inheritdoc IUniswapLogic
    function uniswapCollectFees(uint256 nftId) external onlyVaultItself {
        _collectFees(nftId);
    }
}

