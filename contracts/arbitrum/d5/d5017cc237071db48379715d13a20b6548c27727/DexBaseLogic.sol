// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

import {IWETH9} from "./IWETH9.sol";
import {IV3SwapRouter} from "./IV3SwapRouter.sol";
import {IDexBaseLogic} from "./IDexBaseLogic.sol";

import {TransferHelper} from "./TransferHelper.sol";
import {DexLogicLib} from "./DexLogicLib.sol";

/// @title DexBaseLogic
/// @notice This contract provides a set of functions for interacting with Uniswap V3
contract DexBaseLogic is IDexBaseLogic {
    // =========================
    // Constructor and constants
    // =========================

    uint128 private constant E18 = 1e18;
    uint32 private constant PERIOD = 60; // in seconds

    INonfungiblePositionManager internal immutable dexNftPositionManager;
    IV3SwapRouter private immutable dexRouter;
    IUniswapV3Factory private immutable dexFactory;
    IWETH9 private immutable wrappedNative;

    /// @notice Sets the immutable variables for the contract.
    /// @param _dexNftPositionManager Instance of the Nonfungible Position Manager.
    /// @param _dexRouter Instance of the V3 Swap Router.
    /// @param _dexFactory Instance of the V3 Factory.
    /// @param _wrappedNative wrapped nutive currency of the network.
    constructor(
        INonfungiblePositionManager _dexNftPositionManager,
        IV3SwapRouter _dexRouter,
        IUniswapV3Factory _dexFactory,
        IWETH9 _wrappedNative
    ) {
        dexNftPositionManager = _dexNftPositionManager;
        dexRouter = _dexRouter;
        dexFactory = _dexFactory;
        wrappedNative = _wrappedNative;
    }

    // =========================
    // Main functions
    // =========================

    /// @dev Burns the current position and mints a new one with the specified ticks
    /// @param newLowerTick The new lower tick for the position
    /// @param newUpperTick The new upper tick for the position
    /// @param nftId The NFT ID of the position to change
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    /// @return The NFT ID of the new position
    function _changeTickRange(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 nftId,
        uint256 deviationThresholdE18
    ) internal returns (uint256) {
        if (newLowerTick > newUpperTick) {
            (newLowerTick, newUpperTick) = (newUpperTick, newLowerTick);
        }

        address token0;
        address token1;
        uint24 poolFee;
        uint256 token0Amount;
        uint256 token1Amount;
        IUniswapV3Pool dexPool;

        {
            int24 tickLower;
            int24 tickUpper;
            uint128 liquidity;

            (
                token0,
                token1,
                poolFee,
                tickLower,
                tickUpper,
                liquidity,
                dexPool
            ) = _getData(nftId);

            if (tickLower == newLowerTick && tickUpper == newUpperTick) {
                return nftId;
            }

            DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

            // burn previos nft
            (token0Amount, token1Amount) = DexLogicLib
                .withdrawPositionMEVUnsafe(
                    nftId,
                    liquidity,
                    dexNftPositionManager
                );
            dexNftPositionManager.burn(nftId);
        }

        (token0Amount, token1Amount) = DexLogicLib.swapToTargetRMEVUnsafe(
            newLowerTick,
            newUpperTick,
            token0Amount,
            token1Amount,
            dexPool,
            token0,
            token1,
            poolFee,
            dexRouter
        );

        return
            DexLogicLib.mintNftMEVUnsafe(
                token0Amount,
                token1Amount,
                newLowerTick,
                newUpperTick,
                token0,
                token1,
                poolFee,
                dexNftPositionManager
            );
    }

    /// @dev Mints a new position in the given pool with the specified ticks
    /// @param dexPool The Uniswap V3 pool to interact with
    /// @param newLowerTick The lower tick for the position
    /// @param newUpperTick The upper tick for the position
    /// @param token0Amount Amount of token0 to add to the position
    /// @param token1Amount Amount of token1 to add to the position
    /// @param useFullTokenBalancesFromVault If true, uses the full token balances of the contract
    /// @param swap If true, attempts to swap tokens to achieve a balanced position
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    /// @return The NFT ID of the minted position
    function _mintNft(
        IUniswapV3Pool dexPool,
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 token0Amount,
        uint256 token1Amount,
        bool useFullTokenBalancesFromVault,
        bool swap,
        uint256 deviationThresholdE18
    ) internal returns (uint256) {
        if (newLowerTick > newUpperTick) {
            (newLowerTick, newUpperTick) = (newUpperTick, newLowerTick);
        }

        address token0 = dexPool.token0();
        address token1 = dexPool.token1();

        DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

        if (useFullTokenBalancesFromVault) {
            token0Amount = TransferHelper.safeGetBalance(token0, address(this));
            token1Amount = TransferHelper.safeGetBalance(token1, address(this));
        } else {
            DexLogicLib.validateTokenBalance(token0, token0Amount);
            DexLogicLib.validateTokenBalance(token1, token1Amount);
        }

        uint24 poolFee = dexPool.fee();

        if (swap) {
            IUniswapV3Pool _dexPool = dexPool;

            (token0Amount, token1Amount) = DexLogicLib.swapToTargetRMEVUnsafe(
                newLowerTick,
                newUpperTick,
                token0Amount,
                token1Amount,
                _dexPool,
                token0,
                token1,
                poolFee,
                dexRouter
            );
        }

        return
            DexLogicLib.mintNftMEVUnsafe(
                token0Amount,
                token1Amount,
                newLowerTick,
                newUpperTick,
                token0,
                token1,
                poolFee,
                dexNftPositionManager
            );
    }

    /// @dev Adds the specified amount of tokens to the position
    /// @param nftId The NFT ID of the position to add liquidity to
    /// @param token0Amount Amount of token0 to add to the position
    /// @param token1Amount Amount of token1 to add to the position
    /// @param useFullTokenBalancesFromVault If true, uses the full token balances of the contract
    /// @param swap If true, attempts to swap tokens to achieve a balanced position
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    function _addLiquidity(
        uint256 nftId,
        uint256 token0Amount,
        uint256 token1Amount,
        bool useFullTokenBalancesFromVault,
        bool swap,
        uint256 deviationThresholdE18
    ) internal {
        (
            address token0,
            address token1,
            uint24 poolFee,
            int24 tickLower,
            int24 tickUpper,
            ,
            IUniswapV3Pool dexPool
        ) = _getData(nftId);

        DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

        if (useFullTokenBalancesFromVault) {
            token0Amount = TransferHelper.safeGetBalance(token0, address(this));
            token1Amount = TransferHelper.safeGetBalance(token1, address(this));
        } else {
            DexLogicLib.validateTokenBalance(token0, token0Amount);
            DexLogicLib.validateTokenBalance(token1, token1Amount);
        }

        if (swap) {
            (token0Amount, token1Amount) = DexLogicLib.swapToTargetRMEVUnsafe(
                tickLower,
                tickUpper,
                token0Amount,
                token1Amount,
                dexPool,
                token0,
                token1,
                poolFee,
                dexRouter
            );
        }

        // To avoid passing token addresses to the _increaseLiquidity method, the approve is done here
        TransferHelper.safeApprove(
            token0,
            address(dexNftPositionManager),
            token0Amount
        );
        TransferHelper.safeApprove(
            token1,
            address(dexNftPositionManager),
            token1Amount
        );

        DexLogicLib.increaseLiquidityMEVUnsafe(
            nftId,
            token0Amount,
            token1Amount,
            dexNftPositionManager
        );
    }

    /// @dev Collects fees and adds them as liquidity to the position
    /// @param nftId The ID of the NFT representing the position.
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    function _autoCompound(
        uint256 nftId,
        uint256 deviationThresholdE18
    ) internal {
        // first check for nftId existence
        (
            address token0,
            address token1,
            uint24 poolFee,
            int24 tickLower,
            int24 tickUpper,
            ,
            IUniswapV3Pool dexPool
        ) = _getData(nftId);

        DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

        // collect all fees
        (uint256 amount0, uint256 amount1) = _collectFees(nftId);

        (amount0, amount1) = DexLogicLib.swapToTargetRMEVUnsafe(
            tickLower,
            tickUpper,
            amount0,
            amount1,
            dexPool,
            token0,
            token1,
            poolFee,
            dexRouter
        );

        // To avoid passing token addresses to the _increaseLiquidity method, the approve is done here
        TransferHelper.safeApprove(
            token0,
            address(dexNftPositionManager),
            amount0
        );
        TransferHelper.safeApprove(
            token1,
            address(dexNftPositionManager),
            amount1
        );

        // adds liquidity to the NFT
        DexLogicLib.increaseLiquidityMEVUnsafe(
            nftId,
            amount0,
            amount1,
            dexNftPositionManager
        );
    }

    /// @notice Executes a swap on dex with exact input amount for a `tokens[0]`.
    /// @param tokens Addresses of the tokens for swap.
    /// @param poolFees Fee tiers array of the pools.
    /// @param amountIn Exact amount of input token to swap.
    /// @param useFullBalanceOfTokenInFromVault Whether to use the full balance of
    ///        the input token from the vault.
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    /// @return amountOut Returns the amount of the output token.
    function _swapExactInput(
        address[] calldata tokens,
        uint24[] calldata poolFees,
        uint256 amountIn,
        bool useFullBalanceOfTokenInFromVault,
        bool unwrapInTheEnd,
        uint256 deviationThresholdE18
    ) internal returns (uint256) {
        if (tokens.length < 2) {
            revert DexLogicLogic_WrongLengthOfTokensArray();
        }

        if (poolFees.length + 1 != tokens.length) {
            revert DexLogicLogic_WrongLengthOfPoolFeesArray();
        }

        if (useFullBalanceOfTokenInFromVault) {
            amountIn = TransferHelper.safeGetBalance(tokens[0], address(this));
        } else {
            DexLogicLib.validateTokenBalance(tokens[0], amountIn);
        }

        if (amountIn == 0) {
            return 0;
        }

        uint256 _amountIn = amountIn;

        address tokenIn;
        address tokenOut;
        uint24 poolFee;

        for (uint256 i; i < poolFees.length; ) {
            unchecked {
                tokenIn = tokens[i];
                tokenOut = tokens[i + 1];
                poolFee = poolFees[i];

                ++i;
            }

            IUniswapV3Pool dexPool = DexLogicLib.dexPool(
                tokenIn,
                tokenOut,
                poolFee,
                dexFactory
            );
            DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

            amountIn = DexLogicLib.swapExactInputMEVUnsafe(
                tokenIn,
                tokenOut,
                poolFee,
                amountIn,
                dexRouter
            );
        }

        if (unwrapInTheEnd && tokenOut == address(wrappedNative)) {
            wrappedNative.withdraw(amountIn);
        }

        emit DexSwap(tokens[0], _amountIn, tokenOut, amountIn);

        return amountIn;
    }

    /// @dev Executes a swap on dex with exact output for a single token.
    /// @param tokenIn Address of the input token.
    /// @param tokenOut Address of the output token.
    /// @param poolFee Fee tier of the pool.
    /// @param amountOut Exact amount of output token desired.
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    /// @return amountIn Returns the amount of the input token spent.
    function _swapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountOut,
        uint256 deviationThresholdE18
    ) internal returns (uint256 amountIn) {
        if (amountOut == 0) {
            return 0;
        }

        IUniswapV3Pool dexPool = DexLogicLib.dexPool(
            tokenIn,
            tokenOut,
            poolFee,
            dexFactory
        );
        DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

        uint256 tokenInBalance = TransferHelper.safeGetBalance(
            tokenIn,
            address(this)
        );
        TransferHelper.safeApprove(tokenIn, address(dexRouter), tokenInBalance);

        amountIn = DexLogicLib.swapExactOutputMEVUnsafe(
            tokenIn,
            tokenOut,
            poolFee,
            amountOut,
            dexRouter
        );

        emit DexSwap(tokenIn, amountIn, tokenOut, amountOut);
    }

    /// @dev Swaps tokens to achieve a target ratio (R) for pool liquidity.
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    /// @param dexPool The dex pool to interact with.
    /// @param token0Amount Amount of token0.
    /// @param token1Amount Amount of token1.
    /// @param targetRE18 Target reserve ratio.
    /// @return Returns the amounts of token0 and token1 after the swap.
    function _swapToTargetR(
        uint256 deviationThresholdE18,
        IUniswapV3Pool dexPool,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 targetRE18
    ) internal returns (uint256, uint256) {
        DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

        address token0 = dexPool.token0();
        address token1 = dexPool.token1();
        uint24 poolFee = dexPool.fee();

        DexLogicLib.validateTokenBalance(token0, token0Amount);
        DexLogicLib.validateTokenBalance(token1, token1Amount);

        uint256 amount1Target = DexLogicLib.token1AmountAfterSwapForTargetRE18(
            DexLogicLib.getCurrentSqrtRatioX96(dexPool),
            token0Amount,
            token1Amount,
            targetRE18,
            poolFee
        );

        return
            DexLogicLib.swapAssetsMEVUnsafe(
                token0Amount,
                token1Amount,
                amount1Target,
                targetRE18,
                token0,
                token1,
                poolFee,
                dexRouter
            );
    }

    /// @dev Withdraws liquidity from a dex position based on shares.
    /// @param nftId The ID of the NFT representing the position.
    /// @param sharesE18 Amount of shares to determine the amount of liquidity to withdraw.
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    function _withdrawPositionByShares(
        uint256 nftId,
        uint128 sharesE18,
        uint256 deviationThresholdE18
    ) internal {
        if (sharesE18 > E18) {
            sharesE18 = E18;
        }

        uint128 liquidity = DexLogicLib.getLiquidity(
            nftId,
            dexNftPositionManager
        );

        unchecked {
            liquidity = (liquidity * sharesE18) / E18;
        }

        _withdrawPositionByLiquidity(nftId, liquidity, deviationThresholdE18);
    }

    /// @dev Withdraws a specified amount of liquidity from a dex position.
    /// @param nftId The ID of the NFT representing the position.
    /// @param liquidity Amount of liquidity to withdraw.
    /// @param deviationThresholdE18 Maximum allowed spotPrice deviation from the oracle price.
    function _withdrawPositionByLiquidity(
        uint256 nftId,
        uint128 liquidity,
        uint256 deviationThresholdE18
    ) internal {
        uint128 totalLiquidity = DexLogicLib.getLiquidity(
            nftId,
            dexNftPositionManager
        );
        if (liquidity > totalLiquidity) {
            liquidity = totalLiquidity;
        }

        (, , , , , , IUniswapV3Pool dexPool) = _getData(nftId);

        DexLogicLib.MEVCheck(deviationThresholdE18, dexPool, PERIOD);

        DexLogicLib.withdrawPositionMEVUnsafe(
            nftId,
            liquidity,
            dexNftPositionManager
        );
    }

    /// @dev Collects fees accumulated in a dex position.
    /// @param nftId The ID of the NFT representing the position.
    function _collectFees(
        uint256 nftId
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = DexLogicLib.collectFees(
            nftId,
            dexNftPositionManager
        );
        emit DexCollectFees(amount0, amount1);
    }

    // =========================
    // Private functions
    // =========================

    /// @dev Internal function to get the NFT data and associated pool
    /// @param nftId The NFT ID to fetch data for
    /// @return token0 The address of token0
    /// @return token1 The address of token1
    /// @return poolFee The pool's fee rate
    /// @return tickLower The lower tick of the position
    /// @return tickUpper The upper tick of the position
    /// @return liquidity The liquidity of the position
    /// @return dexPool The Uniswap V3 pool associated with the position
    function _getData(
        uint256 nftId
    )
        private
        view
        returns (
            address token0,
            address token1,
            uint24 poolFee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            IUniswapV3Pool dexPool
        )
    {
        (token0, token1, poolFee, tickLower, tickUpper, liquidity) = DexLogicLib
            .getNftData(nftId, dexNftPositionManager);

        dexPool = DexLogicLib.dexPool(token0, token1, poolFee, dexFactory);
    }
}

