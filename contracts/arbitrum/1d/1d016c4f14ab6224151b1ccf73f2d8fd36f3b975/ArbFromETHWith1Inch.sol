// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";

import "./ArbStrategy.sol";

contract ArbFromETHWith1Inch is ArbStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @dev Swap with 1inch and univ2.
     * If selector is 0, buy tokens with univ2 and sell tokens with 1inch.
     * Otherwise, buy tokens with 1inch and sell tokens with univ2.
     * @param oneInch Address of 1inch router
     * @param executor Aggregation executor that executes calls described in data
     * @param desc Swap description in 1inch
     * @param data Encoded calls that caller should execute in between of swaps
     * @param uniV2 Address of univ2 router
     * @param path Array of tokens to swap in univ2
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromETHWith1InchAndUniV2(
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory desc,
        bytes calldata data,
        address uniV2,
        address[] memory path,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused onlyWhitelist returns (uint actualAmountOut) {
        uint amountIn = getBalance();

        if (selector == 0) swapUniV2And1Inch(amountIn, oneInch, executor, desc, data, uniV2, path, deadline);
        else swap1InchAndUniV2(amountIn, oneInch, executor, desc, data, uniV2, path, deadline);

        return _afterSwap(amountIn);
    }

    /**
     * @dev Swap with 1inch and vault.
     * If selector is 0, buy tokens with vault and sell tokens with 1inch.
     * Otherwise, buy tokens with 1inch and sell tokens with vault.
     * @param oneInch Address of 1inch router
     * @param executor Aggregation executor that executes calls described in data
     * @param desc Swap description in 1inch
     * @param data Encoded calls that caller should execute in between of swaps
     * @param vault Address of vault
     * @param swaps BatchSwapStep struct in vault
     * @param assets An array of tokens which are used in the batch swap. This is referenced from within swaps
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromETHWith1InchAndVault(
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory desc,
        bytes calldata data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused onlyWhitelist returns (uint actualAmountOut) {
        uint amountIn = getBalance();

        if (selector == 0) swapVaultAnd1Inch(amountIn, oneInch, executor, desc, data, vault, swaps, assets, deadline);
        else swap1InchAndVault(amountIn, oneInch, executor, desc, data, vault, swaps, assets, deadline);

        return _afterSwap(amountIn);
    }

    /**
     * @dev Swap with 1inch and univ3.
     * If selector is 0, buy tokens with univ3 and sell tokens with 1inch.
     * Otherwise, buy tokens with 1inch and sell tokens with univ3.
     * @param oneInch Address of 1inch router
     * @param executor Aggregation executor that executes calls described in data
     * @param desc Swap description in 1inch
     * @param data Encoded calls that caller should execute in between of swaps
     * @param uniV3 Address of univ3 router
     * @param params Swap Input Parameters in univ3
     * @param selector Selector of the swap method
     */
    function arbFromETHWith1InchAndUniV3(
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory desc,
        bytes calldata data,
        address uniV3,
        ISwapRouter.ExactInputSingleParams memory params,
        uint256 selector
    ) external payable nonReentrant whenNotPaused onlyWhitelist returns (uint actualAmountOut) {
        uint amountIn = getBalance();

        if (selector == 0) swapUniV3And1Inch(amountIn, oneInch, executor, desc, data, uniV3, params);
        else swap1InchAndUniV3(amountIn, oneInch, executor, desc, data, uniV3, params);

        return _afterSwap(amountIn);
    }

    /**
     * @dev Swap with univ3swap of 1inch and vault.
     * If selector is 0, buy tokens with vault and sell tokens with univ3swap of 1inch.
     * Otherwise, buy tokens with 1inch and sell tokens with vault.
     * @param oneInch Address of 1inch router
     * @param uniV3Swap UnisV3Swap struct of 1inch
     * @param vault Address of vault
     * @param swaps BatchSwapStep struct in vault
     * @param assets An array of tokens which are used in the batch swap. This is referenced from within swaps
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromETHWith1InchUniV3AndVault(
        address oneInch,
        I1InchStrategy.UniV3SwapTo calldata uniV3Swap,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused onlyWhitelist returns (uint actualAmountOut) {
        uint amountIn = getBalance();

        if (selector == 0) swapVaultAnd1InchUniV3(amountIn, oneInch, uniV3Swap, vault, swaps, assets, deadline);
        else swap1InchUniV3AndVault(amountIn, oneInch, uniV3Swap, vault, swaps, assets, deadline);

        return _afterSwap(amountIn);
    }

    /**
     * @dev Swap with univ3swap of 1inch and univ2.
     * If selector is 0, buy tokens with univ2 and sell tokens with univ3swap of 1inch.
     * Otherwise, buy tokens with 1inch and sell tokens with univ2.
     * @param oneInch Address of 1inch router
     * @param uniV3Swap UnisV3Swap struct of 1inch
     * @param uniV2 Address of univ2 router
     * @param path Array of tokens to swap in univ2
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromETHWith1InchUniV3AndUniV2(
        address oneInch,
        I1InchStrategy.UniV3SwapTo calldata uniV3Swap,
        address uniV2,
        address[] memory path,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused onlyWhitelist returns (uint actualAmountOut) {
        uint amountIn = getBalance();

        if (selector == 0) swapUniV2And1InchUniV3(amountIn, oneInch, uniV3Swap, uniV2, path, deadline);
        else swap1InchUniV3AndUniV2(amountIn, oneInch, uniV3Swap, uniV2, path, deadline);

        return _afterSwap(amountIn);
    }

    /**
     * @dev Buy tokens with univ2 and sell tokens with 1inch
     */
    function swapUniV2And1Inch(
        uint256 amountIn,
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell,
        bytes calldata dataSell,
        address uniV2Buy,
        address[] memory pathBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        getUniV2Strategy(uniV2Buy).swapExactETHForTokens{ value: amountIn }(
            uniV2Buy,
            0,
            pathBuy,
            sellStrategy,
            deadline
        );
        // Sell tokens
        descSell.amount = descSell.srcToken.balanceOf(sellStrategy);
        get1InchStrategy(oneInchSell).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, dataSell);
    }

    /**
     * @dev Buy tokens with 1inch and sell toekns with univ2
     */
    function swap1InchAndUniV2(
        uint256 amountIn,
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        bytes calldata dataBuy,
        address uniV2Sell,
        address[] memory pathSell,
        uint256 deadline
    ) private {
        // Buy tokens
        get1InchStrategy(oneInchBuy).swap{ value: amountIn }(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, dataBuy);
        // Sell tokens
        getUniV2Strategy(uniV2Sell).swapExactTokensForETH(
            uniV2Sell,
            descBuy.dstToken.balanceOf(address(getUniV2Strategy(uniV2Sell))),
            0,
            pathSell,
            address(this),
            deadline
        );
    }

    /**
     * @dev Buy tokens with vautl and sell tokens with 1inch
     */
    function swapVaultAnd1Inch(
        uint256 amountIn,
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell,
        bytes calldata data,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assetsBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        int256[] memory limitsBuy = new int256[](assetsBuy.length);
        for (uint256 i = 0; i < assetsBuy.length; i++) {
            limitsBuy[i] = type(int256).max;
        }
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        getVaultStrategy(vaultBuy).batchSwap{ value: amountIn }(
            vaultBuy,
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assetsBuy,
            fundsBuy,
            limitsBuy,
            deadline
        );
        // Sell tokens
        descSell.amount = descSell.srcToken.balanceOf(sellStrategy);
        get1InchStrategy(oneInchSell).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, data);
    }

    /**
     * @dev Buy tokens with 1inch and sell tokens with vault
     */
    function swap1InchAndVault(
        uint256 amountIn,
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        bytes calldata data,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsSell,
        uint256 deadline
    ) private {
        // Buy tokens
        get1InchStrategy(oneInchBuy).swap{ value: amountIn }(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, data);
        // Sell tokens
        address sellStrategy = address(getVaultStrategy(vaultSell));
        int256[] memory limitsSell = new int256[](assetsSell.length);
        for (uint256 i = 0; i < assetsSell.length; i++) {
            limitsSell[i] = type(int256).max;
        }
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        for (uint256 i = 0; i < swapsSell.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsSell[i];
            swapsSell[i].amount = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]).balanceOf(sellStrategy);
        }
        getVaultStrategy(vaultSell).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assetsSell,
            fundsSell,
            limitsSell,
            deadline
        );
    }

    /**
     * @dev Buy tokens with univ3 and sell tokens with 1inch
     */
    function swapUniV3And1Inch(
        uint256 amountIn,
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell,
        bytes calldata dataSell,
        address uniV3Buy,
        ISwapRouter.ExactInputSingleParams memory paramsBuy
    ) private {
        // Buy tokens
        getUniV3Strategy(uniV3Buy).exactInputSingle{ value: amountIn }(uniV3Buy, paramsBuy);
        // Sell tokens
        descSell.amount = descSell.srcToken.balanceOf(address(get1InchStrategy(oneInchSell)));
        get1InchStrategy(oneInchSell).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, dataSell);
    }

    /**
     * @dev Buy tokens with 1inch and sell tokens with univ3
     */
    function swap1InchAndUniV3(
        uint256 amountIn,
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        bytes calldata dataBuy,
        address uniV3Sell,
        ISwapRouter.ExactInputSingleParams memory paramsSell
    ) private {
        // Buy tokens
        get1InchStrategy(oneInchBuy).swap{ value: amountIn }(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, dataBuy);
        // Sell tokens
        paramsSell.amountIn = descBuy.dstToken.balanceOf(address(getUniV3Strategy(uniV3Sell)));
        getUniV3Strategy(uniV3Sell).exactInputSingle(uniV3Sell, paramsSell);
    }

    /**
     * @dev Buy tokens with univ3swap of 1inch and sell tokens with vault
     */
    function swapVaultAnd1InchUniV3(
        uint256 amountIn,
        address oneInchSell,
        I1InchStrategy.UniV3SwapTo calldata uniV3SwapSell,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assetsBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        int256[] memory limitsBuy = new int256[](assetsBuy.length);
        for (uint256 i = 0; i < assetsBuy.length; i++) {
            limitsBuy[i] = type(int256).max;
        }
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        getVaultStrategy(vaultBuy).batchSwap{ value: amountIn }(
            vaultBuy,
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assetsBuy,
            fundsBuy,
            limitsBuy,
            deadline
        );
        // Sell tokens
        get1InchStrategy(oneInchSell).uniswapV3SwapTo(oneInchSell, uniV3SwapSell);
    }

    /**
     * @dev Buy tokens with univ3swap of 1inch and sell tokens with vault
     */
    function swap1InchUniV3AndVault(
        uint256 amountIn,
        address oneInchBuy,
        I1InchStrategy.UniV3SwapTo calldata uniV3SwapBuy,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsSell,
        uint256 deadline
    ) private {
        // Buy tokens
        get1InchStrategy(oneInchBuy).uniswapV3SwapTo{ value: amountIn }(oneInchBuy, uniV3SwapBuy);
        // Sell tokens
        address sellStrategy = address(getVaultStrategy(vaultSell));
        int256[] memory limitsSell = new int256[](assetsSell.length);
        for (uint256 i = 0; i < assetsSell.length; i++) {
            limitsSell[i] = type(int256).max;
        }
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        for (uint256 i = 0; i < swapsSell.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsSell[i];
            swapsSell[i].amount = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]).balanceOf(sellStrategy);
        }
        getVaultStrategy(vaultSell).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assetsSell,
            fundsSell,
            limitsSell,
            deadline
        );
    }

    /**
     * @dev Buy tokens with univ2 and sell tokens with univ3swap of 1inch
     */
    function swapUniV2And1InchUniV3(
        uint256 amountIn,
        address oneInchSell,
        I1InchStrategy.UniV3SwapTo calldata uniV3Swap,
        address uniV2Buy,
        address[] memory pathBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        getUniV2Strategy(uniV2Buy).swapExactETHForTokens{ value: amountIn }(
            uniV2Buy,
            0,
            pathBuy,
            sellStrategy,
            deadline
        );
        // Sell tokens
        get1InchStrategy(oneInchSell).uniswapV3SwapTo(oneInchSell, uniV3Swap);
    }

    /**
     * @dev Buy tokens with univ3swap of 1inch and sell tokens with univ2
     */
    function swap1InchUniV3AndUniV2(
        uint256 amountIn,
        address oneInchBuy,
        I1InchStrategy.UniV3SwapTo calldata uniV3SwapBuy,
        address uniV2Sell,
        address[] memory pathSell,
        uint256 deadline
    ) private {
        // Buy tokens
        uint256 amount = get1InchStrategy(oneInchBuy).uniswapV3SwapTo{ value: amountIn }(oneInchBuy, uniV3SwapBuy);
        // Sell tokens
        getUniV2Strategy(uniV2Sell).swapExactTokensForETH(uniV2Sell, amount, 0, pathSell, address(this), deadline);
    }
}

