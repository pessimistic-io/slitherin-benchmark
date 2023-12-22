// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";

import "./ArbStrategy.sol";

contract ArbFromToken is ArbStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @dev Swap tokens with univ2
     * @param amountIn Amount in
     * @param uniV2Buy Address of univ2 router to buy tokens from ETH
     * @param pathBuy Array of tokens to buy tokens from ETH in univ2
     * @param uniV2Sell Address of univ2 router to sell tokens for ETH
     * @param pathSell Array of tokens to sell tokens for ETH in univ2
     * @param deadline The deadline timestamp
     */
    function arbFromTokensWithUniV2(
        uint256 amountIn,
        address uniV2Buy,
        address[] calldata pathBuy,
        address uniV2Sell,
        address[] calldata pathSell,
        uint256 deadline
    ) external nonReentrant whenNotPaused onlyWhitelist {
        // Buy the tokens
        IERC20Upgradeable tokenBuyIn = IERC20Upgradeable(pathBuy[0]);
        address sellStrategy = address(getUniV2Strategy(uniV2Sell));
        tokenBuyIn.safeTransferFrom(_msgSender(), address(this), amountIn);
        tokenBuyIn.safeTransfer(sellStrategy, amountIn);
        getUniV2Strategy(uniV2Buy).swapExactTokensForTokens(uniV2Buy, amountIn, 0, pathBuy, sellStrategy, deadline);
        // Sell the tokens
        IERC20Upgradeable tokenBuyOut = IERC20Upgradeable(pathBuy[pathBuy.length - 1]);
        getUniV2Strategy(uniV2Sell).swapExactTokensForTokens(
            uniV2Sell,
            tokenBuyOut.balanceOf(sellStrategy),
            0,
            pathSell,
            address(this),
            deadline
        );

        IERC20Upgradeable tokenSellOut = IERC20Upgradeable(pathBuy[pathBuy.length - 1]);
        uint256 actualAmountOut = tokenSellOut.balanceOf(address(this));
        tokenSellOut.safeTransfer(_msgSender(), actualAmountOut);
    }

    /**
     * @dev Swap tokens with vault and univ2
     * If selector is 0, buy tokens with univ2 and sell tokens with vault.
     * Otherwise, buy tokens with vault and sell tokens with univ2.
     * @param amountIn Amount in
     * @param uniV2 Address of univ2 router to buy tokens
     * @param path Array of tokens to buy tokens in univ2
     * @param vault Address of vault
     * @param swaps BatchSwapStep struct in vault
     * @param assets An array of tokens which are used in the batch swap. This is referenced from within swaps
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromTokensWithVaultAndUniV2(
        uint256 amountIn,
        address uniV2,
        address[] memory path,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint256 selector
    ) external nonReentrant whenNotPaused onlyWhitelist {
        if (selector == 0) swapTokensUniV2AndVault(amountIn, uniV2, path, vault, swaps, assets, deadline);
        else swapTokensVaultAndUniV2(uniV2, path, vault, swaps, assets, deadline);
    }

    /**
     * @dev Swap tokens with 1inch and vault
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
    function arbFromTokensWith1InchAndVault(
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory desc,
        bytes calldata data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint256 selector
    ) external nonReentrant whenNotPaused onlyWhitelist {
        if (selector == 0) {
            swapTokensVaultAnd1Inch(oneInch, executor, desc, data, vault, swaps, assets, deadline);

            for (uint256 i = 0; i < swaps.length; i++) {
                IVault.BatchSwapStep memory swapStep = swaps[i];
                IERC20Upgradeable token = IERC20Upgradeable(assets[swapStep.assetInIndex]);
                uint256 actualAmountOut = token.balanceOf(address(this));
                _require(actualAmountOut > swapStep.amount, Errors.NO_PROFIT);
                token.safeTransfer(_msgSender(), actualAmountOut);
            }
        } else {
            swapTokens1InchAndVault(oneInch, executor, desc, data, vault, swaps, assets, deadline);
            uint actualAmountOut = IERC20Upgradeable(address(desc.srcToken)).balanceOf(address(this));

            _require(actualAmountOut > desc.amount, Errors.NO_PROFIT);
            IERC20Upgradeable(address(desc.srcToken)).safeTransfer(_msgSender(), actualAmountOut);
        }
    }

    /**
     * @dev Swap tokens with univ3swap of 1inch and vault
     * If seletor is 0, buy tokens with vault and sell tokens with univ3swap of 1inch.
     * Otherwise, buy tokens with univ3swap of 1inch and sell tokens with vault.
     * @param oneInch Address of 1inch router
     * @param uniV3Swap UnisV3Swap struct of 1inch
     * @param vault Address of vault
     * @param swaps BatchSwapStep struct in vault
     * @param assets An array of tokens which are used in the batch swap. This is referenced from within swaps
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromTokensWith1InchUniV3AndVault(
        address oneInch,
        I1InchStrategy.UniV3SwapTo calldata uniV3Swap,
        address vault,
        IVault.BatchSwapStep[] calldata swaps,
        address[] calldata assets,
        uint256 deadline,
        uint256 selector
    ) external nonReentrant whenNotPaused onlyWhitelist {
        if (selector == 0) swapTokensVaultAnd1InchUniV3(oneInch, uniV3Swap, vault, swaps, assets, deadline);
        else swapTokens1InchUniV3AndVault(oneInch, uniV3Swap, vault, swaps, assets, deadline);
    }

    /**
     * @dev Buy tokens with univ2 and sell tokens with vault
     */
    function swapTokensUniV2AndVault(
        uint256 amountIn,
        address uniV2Buy,
        address[] memory pathBuy,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsSell,
        uint256 deadline
    ) private {
        // Buy tokens
        IERC20Upgradeable tokenBuyIn = IERC20Upgradeable(pathBuy[0]);
        address buyStrategy = address(getUniV2Strategy(uniV2Buy));
        address sellStrategy = address(getVaultStrategy(vaultSell));
        tokenBuyIn.safeTransferFrom(_msgSender(), address(this), amountIn);
        tokenBuyIn.safeTransfer(buyStrategy, amountIn);
        IUniV2Strategy(buyStrategy).swapExactTokensForTokens(uniV2Buy, amountIn, 0, pathBuy, sellStrategy, deadline);
        // Sell tokens
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(_msgSender()),
            toInternalBalance: false
        });
        int256[] memory limitsSell = new int256[](assetsSell.length);
        for (uint256 i = 0; i < assetsSell.length; i++) {
            limitsSell[i] = type(int256).max;
        }
        for (uint256 i = 0; i < swapsSell.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsSell[i];
            swapsSell[i].amount = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]).balanceOf(address(sellStrategy));
        }
        IVaultStrategy(sellStrategy).batchSwap(
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
     * @dev Buy tokens with vault and sell tokens with univ2
     */
    function swapTokensVaultAndUniV2(
        address uniV2Sell,
        address[] memory pathSell,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assetsBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address buyStrategy = address(getVaultStrategy(vaultBuy));
        address sellStrategy = address(getUniV2Strategy(uniV2Sell));
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        int256[] memory limitsBuy = new int256[](assetsBuy.length);
        for (uint256 i = 0; i < assetsBuy.length; i++) {
            limitsBuy[i] = type(int256).max;
        }
        for (uint256 i = 0; i < swapsBuy.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsBuy[i];
            IERC20Upgradeable token = IERC20Upgradeable(assetsBuy[swapStep.assetInIndex]);
            token.safeTransferFrom(_msgSender(), address(this), swapStep.amount);
            token.safeTransfer(buyStrategy, swapStep.amount);
        }
        IVaultStrategy(buyStrategy).batchSwap(
            vaultBuy,
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assetsBuy,
            fundsBuy,
            limitsBuy,
            deadline
        );
        // Sell tokens
        IERC20Upgradeable _token = IERC20Upgradeable(assetsBuy[swapsBuy[swapsBuy.length - 1].assetOutIndex]);
        IUniV2Strategy(sellStrategy).swapExactTokensForTokens(
            uniV2Sell,
            _token.balanceOf(sellStrategy),
            0,
            pathSell,
            address(this),
            deadline
        );
    }

    /**
     * @dev Buy tokens with vault and sell tokens with 1inch
     */
    function swapTokensVaultAnd1Inch(
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
        address buyStrategy = address(getVaultStrategy(vaultBuy));
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        int256[] memory limitsBuy = new int256[](assetsBuy.length);
        for (uint256 i = 0; i < assetsBuy.length; i++) {
            limitsBuy[i] = type(int256).max;
        }
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        for (uint256 i = 0; i < swapsBuy.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsBuy[i];
            IERC20Upgradeable token = IERC20Upgradeable(assetsBuy[swapStep.assetInIndex]);
            token.safeTransferFrom(_msgSender(), address(this), swapStep.amount);
            token.safeTransfer(buyStrategy, swapStep.amount);
        }
        IVaultStrategy(buyStrategy).batchSwap(
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
        I1InchStrategy(sellStrategy).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, data);
    }

    /**
     * @dev Buy tokens with 1inch and sell tokens with vault
     */
    function swapTokens1InchAndVault(
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
        address buyStrategy = address(get1InchStrategy(oneInchBuy));
        address sellStrategy = address(getVaultStrategy(vaultSell));
        IERC20Upgradeable(address(descBuy.srcToken)).safeTransferFrom(_msgSender(), address(this), descBuy.amount);
        IERC20Upgradeable(address(descBuy.srcToken)).safeTransfer(buyStrategy, descBuy.amount);
        I1InchStrategy(buyStrategy).swap(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, data);
        // Sell tokens
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
            swapsSell[i].amount = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]).balanceOf(address(sellStrategy));
        }
        IVaultStrategy(sellStrategy).batchSwap(
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
     * @dev Buy tokens with vault and sell tokens with univ3swap of 1inch
     */
    function swapTokensVaultAnd1InchUniV3(
        address oneInchSell,
        I1InchStrategy.UniV3SwapTo calldata uniV3SwapSell,
        address vaultBuy,
        IVault.BatchSwapStep[] calldata swapsBuy,
        address[] calldata assetsBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address buyStrategy = address(getVaultStrategy(vaultBuy));
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        int256[] memory limitsBuy = new int256[](assetsBuy.length);
        for (uint256 i = 0; i < assetsBuy.length; i++) {
            limitsBuy[i] = type(int256).max;
        }
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        for (uint256 i = 0; i < swapsBuy.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsBuy[i];
            IERC20Upgradeable token = IERC20Upgradeable(assetsBuy[swapStep.assetInIndex]);
            token.safeTransferFrom(_msgSender(), address(this), swapStep.amount);
            token.safeTransfer(buyStrategy, swapStep.amount);
        }
        IVaultStrategy(buyStrategy).batchSwap(
            vaultBuy,
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assetsBuy,
            fundsBuy,
            limitsBuy,
            deadline
        );
        // Sell tokens
        uint256 amountOut = I1InchStrategy(sellStrategy).uniswapV3SwapTo(oneInchSell, uniV3SwapSell);
        _require(amountOut > swapsBuy[0].amount, Errors.NO_PROFIT);
    }

    /**
     * @dev Buy tokens with univ3swap of 1inch and sell tokens with vault
     */
    function swapTokens1InchUniV3AndVault(
        address oneInchBuy,
        I1InchStrategy.UniV3SwapTo memory uniV3SwapBuy,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsSell,
        uint256 deadline
    ) private {
        // Buy tokens
        address buyStrategy = address(get1InchStrategy(oneInchBuy));
        IERC20Upgradeable(uniV3SwapBuy.srcToken).safeTransferFrom(_msgSender(), address(this), uniV3SwapBuy.amount);
        IERC20Upgradeable(uniV3SwapBuy.srcToken).safeTransfer(buyStrategy, uniV3SwapBuy.amount);
        I1InchStrategy(buyStrategy).uniswapV3SwapTo(oneInchBuy, uniV3SwapBuy);
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
            swapsSell[i].amount = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]).balanceOf(address(sellStrategy));
        }
        IVaultStrategy(sellStrategy).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assetsSell,
            fundsSell,
            limitsSell,
            deadline
        );
        for (uint256 i = 0; i < swapsSell.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsSell[i];
            IERC20Upgradeable token = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]);
            uint256 actualAmountOut = token.balanceOf(address(this));
            _require(actualAmountOut > uniV3SwapBuy.amount, Errors.NO_PROFIT);
            token.safeTransfer(_msgSender(), actualAmountOut);
        }
    }
}

