// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeERC20Upgradeable.sol";

import "./ArbStrategy.sol";

contract ArbFromTokens is ArbStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    // state variables
    mapping(address => mapping(address => uint)) public userInfo;

    /**
     * @dev Deposit native token
     */
    function deposit() external payable nonReentrant {
        _require(msg.value > 0, Errors.NO_AMOUNT);
        userInfo[address(0)][_msgSender()] += msg.value;
    }

    /**
     * @dev Deposit erc20 token
     * @param token Token address to deposit
     * @param amount Token amount to deposit
     */
    function depositToken(address token, uint amount) external nonReentrant {
        _require(amount > 0, Errors.NO_AMOUNT);
        userInfo[token][_msgSender()] += amount;
        IERC20Upgradeable(token).safeTransferFrom(_msgSender(), address(this), amount);
    }

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
        address[] memory pathBuy,
        address uniV2Sell,
        address[] memory pathSell,
        uint256 deadline
    ) external nonReentrant whenNotPaused onlyWhitelist {
        // Buy the tokens
        address buyStrategy = getUniV2Strategy(uniV2Buy);
        address sellStrategy = getUniV2Strategy(uniV2Sell);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(pathBuy[0]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), amountIn);
        tokenIn.safeTransfer(buyStrategy, amountIn);
        IUniV2Strategy(buyStrategy).swapExactTokensForTokens(uniV2Buy, amountIn, 0, pathBuy, sellStrategy, deadline);
        // Sell the tokens
        IUniV2Strategy(sellStrategy).swapExactTokensForTokens(
            uniV2Sell,
            IERC20Upgradeable(pathBuy[pathBuy.length - 1]).balanceOf(sellStrategy),
            0,
            pathSell,
            address(this),
            deadline
        );

        _ensureProfit(amountIn, tokenIn);
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
        bytes memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint256 selector
    ) external nonReentrant whenNotPaused onlyWhitelist {
        if (selector == 0) swapTokensVaultAnd1Inch(oneInch, executor, desc, data, vault, swaps, assets, deadline);
        else swapTokens1InchAndVault(oneInch, executor, desc, data, vault, swaps, assets, deadline);
    }

    /**
     * @dev Swap tokens with univ3swap of 1inch and vault
     * If selector is 0, buy tokens with vault and sell tokens with univ3swap of 1inch.
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
        I1InchStrategy.UniV3SwapTo memory uniV3Swap,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint256 selector
    ) external nonReentrant whenNotPaused onlyWhitelist {
        if (selector == 0) swapTokensVaultAnd1InchUniV3(oneInch, uniV3Swap, vault, swaps, assets, deadline);
        else swapTokens1InchUniV3AndVault(oneInch, uniV3Swap, vault, swaps, assets, deadline);
    }

    /**
     * @dev Swap tokens with firebird and vault
     * If selector is 0, buy tokens with vault and sell tokens with firebird.
     * Otherwise, buy tokens with firebird and sell tokens with vault.
     * @param fireBird Address of firebird router
     * @param caller Aggregation caller that executes calls described in data for firebird
     * @param desc Swap descrption in firebird
     * @param data Encoded calls that caller should execute in between of swaps for firebird
     * @param vault Address of vault
     * @param swaps BatchSwapStep struct in vault
     * @param assets An array of tokens which are used in the batch swap. This is referenced from within swaps
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromTokensWithFireBirdAndVault(
        address fireBird,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription memory desc,
        bytes memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint deadline,
        uint256 selector
    ) external nonReentrant whenNotPaused {
        if (selector == 0) swapTokensVaultAndFireBird(fireBird, caller, desc, data, vault, swaps, assets, deadline);
        else swapTokensFireBirdAndVault(fireBird, caller, desc, data, vault, swaps, assets, deadline);
    }

    /**
     * @dev Swap tokens with firebird and 1inch
     * If selector is 0, buy tokens with 1inch and sell tokens with firebird.
     * Otherwise, buy tokens with firebird and sell tokens with 1inch.
     * @param fireBird Address of firebird router
     * @param caller Aggregation caller that executes calls described in data for firebird
     * @param descFireBird Swap descrption in firebird
     * @param dataFireBird Encoded calls that caller should execute in between of swaps for firebird
     * @param oneInch Address of 1inch router
     * @param executor Aggregation executor that executes calls described in data
     * @param descInch Swap description in 1inch
     * @param dataInch Encoded calls that caller should execute in between of swaps
     */
    function arbFromTokensWithFireBirdAnd1Inch(
        address fireBird,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription memory descFireBird,
        bytes memory dataFireBird,
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory descInch,
        bytes memory dataInch,
        uint selector
    ) external nonReentrant whenNotPaused {
        if (selector == 0)
            swapTokens1InchAndFireBird(
                fireBird,
                caller,
                descFireBird,
                dataFireBird,
                oneInch,
                executor,
                descInch,
                dataInch
            );
        else
            swapTokensFireBirdAnd1Inch(
                fireBird,
                caller,
                descFireBird,
                dataFireBird,
                oneInch,
                executor,
                descInch,
                dataInch
            );
    }

    /**
     * @dev Swap tokens with odos and vault
     * If selector is 0, buy tokens with vault and sell tokens with odos.
     * Otherwise, buy tokens with odos and sell tokens with vault.
     * @param odos Address of odos router
     * @param tokenInfo All information about the tokens being swapped
     * @param data Encoded data for swapCompact
     * @param vault Address of vault
     * @param swaps BatchSwapStep struct in vault
     * @param assets An array of tokens which are used in the batch swap. This is referenced from within swaps
     * @param deadline The deadline timestamp
     * @param selector Selector of the swap method
     */
    function arbFromTokensWithOdosAndVault(
        address odos,
        IOdosRouter.swapTokenInfo memory tokenInfo,
        bytes memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint selector
    ) external nonReentrant whenNotPaused {
        if (selector == 0) swapTokensVaultAndOdos(odos, tokenInfo, data, vault, swaps, assets, deadline);
        else swapTokensOdosAndVault(odos, tokenInfo, data, vault, swaps, assets, deadline);
    }

    /**
     * @dev Swap tokens with odos and vault
     * If selector is 0, buy tokens with vault and sell tokens with paraswap.
     * Otherwise, buy tokens with paraswap and sell tokens with vault.
     */
    function arbFromTokensWithParaAndVault(
        address para,
        Utils.SimpleData memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint selector
    ) external nonReentrant whenNotPaused {
        if (selector == 0) swapTokensVaultAndPara(para, data, vault, swaps, assets, deadline);
        else swapTokensParaAndVault(para, data, vault, swaps, assets, deadline);
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
        address buyStrategy = getUniV2Strategy(uniV2Buy);
        address sellStrategy = getVaultStrategy(vaultSell);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(pathBuy[0]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), amountIn);
        tokenIn.safeTransfer(buyStrategy, amountIn);
        IUniV2Strategy(buyStrategy).swapExactTokensForTokens(uniV2Buy, amountIn, 0, pathBuy, sellStrategy, deadline);
        // Sell tokens
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        swapsSell[0].amount = IERC20Upgradeable(assetsSell[swapsSell[0].assetInIndex]).balanceOf(sellStrategy);
        IVaultStrategy(sellStrategy).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assetsSell,
            fundsSell,
            getLimitsForVault(assetsSell.length),
            deadline
        );

        _ensureProfit(amountIn, tokenIn);
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
        address buyStrategy = getVaultStrategy(vaultBuy);
        address sellStrategy = getUniV2Strategy(uniV2Sell);
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        IERC20Upgradeable tokenIn = IERC20Upgradeable(assetsBuy[swapsBuy[0].assetInIndex]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), swapsBuy[0].amount);
        tokenIn.safeTransfer(buyStrategy, swapsBuy[0].amount);
        IVaultStrategy(buyStrategy).batchSwap(
            vaultBuy,
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assetsBuy,
            fundsBuy,
            getLimitsForVault(assetsBuy.length),
            deadline
        );
        // Sell tokens
        uint sellIn = IERC20Upgradeable(assetsBuy[swapsBuy[swapsBuy.length - 1].assetOutIndex]).balanceOf(sellStrategy);
        IUniV2Strategy(sellStrategy).swapExactTokensForTokens(uniV2Sell, sellIn, 0, pathSell, address(this), deadline);

        _ensureProfit(swapsBuy[0].amount, tokenIn);
    }

    /**
     * @dev Buy tokens with vault and sell tokens with 1inch
     */
    function swapTokensVaultAnd1Inch(
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell,
        bytes memory data,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assetsBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address buyStrategy = getVaultStrategy(vaultBuy);
        address sellStrategy = get1InchStrategy(oneInchSell);
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        IERC20Upgradeable tokenIn = IERC20Upgradeable(assetsBuy[swapsBuy[0].assetInIndex]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), swapsBuy[0].amount);
        tokenIn.safeTransfer(buyStrategy, swapsBuy[0].amount);
        IVaultStrategy(buyStrategy).batchSwap(
            vaultBuy,
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assetsBuy,
            fundsBuy,
            getLimitsForVault(assetsBuy.length),
            deadline
        );
        // Sell tokens
        descSell.amount = descSell.srcToken.balanceOf(sellStrategy);
        I1InchStrategy(sellStrategy).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, data);

        _ensureProfit(swapsBuy[0].amount, tokenIn);
    }

    /**
     * @dev Buy tokens with 1inch and sell tokens with vault
     */
    function swapTokens1InchAndVault(
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        bytes memory data,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsSell,
        uint256 deadline
    ) private {
        // Buy tokens
        address buyStrategy = get1InchStrategy(oneInchBuy);
        address sellStrategy = getVaultStrategy(vaultSell);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(address(descBuy.srcToken));
        tokenIn.safeTransferFrom(_msgSender(), address(this), descBuy.amount);
        tokenIn.safeTransfer(buyStrategy, descBuy.amount);
        I1InchStrategy(buyStrategy).swap(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, data);
        // Sell tokens
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        swapsSell[0].amount = IERC20Upgradeable(assetsSell[swapsSell[0].assetInIndex]).balanceOf(sellStrategy);
        IVaultStrategy(sellStrategy).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assetsSell,
            fundsSell,
            getLimitsForVault(assetsSell.length),
            deadline
        );

        _ensureProfit(descBuy.amount, tokenIn);
    }

    /**
     * @dev Buy tokens with vault and sell tokens with univ3swap of 1inch
     */
    function swapTokensVaultAnd1InchUniV3(
        address oneInchSell,
        I1InchStrategy.UniV3SwapTo memory uniV3SwapSell,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assetsBuy,
        uint256 deadline
    ) private {
        // Buy tokens
        address buyStrategy = getVaultStrategy(vaultBuy);
        address sellStrategy = get1InchStrategy(oneInchSell);
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        IERC20Upgradeable tokenIn = IERC20Upgradeable(assetsBuy[swapsBuy[0].assetInIndex]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), swapsBuy[0].amount);
        tokenIn.safeTransfer(buyStrategy, swapsBuy[0].amount);
        IVaultStrategy(buyStrategy).batchSwap(
            vaultBuy,
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assetsBuy,
            fundsBuy,
            getLimitsForVault(assetsBuy.length),
            deadline
        );
        // Sell tokens
        I1InchStrategy.UniV3SwapTo memory _u = uniV3SwapSell;
        _u.amount = IERC20Upgradeable(_u.srcToken).balanceOf(sellStrategy);
        I1InchStrategy(sellStrategy).uniswapV3SwapTo(oneInchSell, _u);

        _ensureProfit(swapsBuy[0].amount, tokenIn);
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
        address buyStrategy = get1InchStrategy(oneInchBuy);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(uniV3SwapBuy.srcToken);
        tokenIn.safeTransferFrom(_msgSender(), address(this), uniV3SwapBuy.amount);
        tokenIn.safeTransfer(buyStrategy, uniV3SwapBuy.amount);
        I1InchStrategy(buyStrategy).uniswapV3SwapTo(oneInchBuy, uniV3SwapBuy);
        // Sell tokens
        address sellStrategy = getVaultStrategy(vaultSell);
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        swapsSell[0].amount = IERC20Upgradeable(assetsSell[swapsSell[0].assetInIndex]).balanceOf(sellStrategy);
        IVaultStrategy(sellStrategy).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assetsSell,
            fundsSell,
            getLimitsForVault(assetsSell.length),
            deadline
        );

        _ensureProfit(uniV3SwapBuy.amount, tokenIn);
    }

    /**
     * @dev Buy tokens with vault and sell tokens with firebird
     */
    function swapTokensVaultAndFireBird(
        address fireBird,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription memory desc,
        bytes memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint deadline
    ) private {
        // Buy tokens
        address buyStrategy = getVaultStrategy(vault);
        address sellStrategy = getFireBirdStrategy(fireBird);
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        IERC20Upgradeable tokenIn = IERC20Upgradeable(assets[swaps[0].assetInIndex]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), swaps[0].amount);
        tokenIn.safeTransfer(buyStrategy, swaps[0].amount);
        IVaultStrategy(buyStrategy).batchSwap(
            vault,
            IVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            fundsBuy,
            getLimitsForVault(assets.length),
            deadline
        );
        // Sell tokens
        desc.amount = desc.srcToken.balanceOf(sellStrategy);
        IFireBirdStrategy(sellStrategy).swap(fireBird, caller, desc, data);

        _ensureProfit(swaps[0].amount, tokenIn);
    }

    /**
     * @dev Buy tokens with firebird and sell tokens with vault
     */
    function swapTokensFireBirdAndVault(
        address fireBird,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription memory desc,
        bytes memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint deadline
    ) private {
        // Buy tokens
        address buyStrategy = getFireBirdStrategy(fireBird);
        address sellStrategy = getVaultStrategy(vault);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(address(desc.srcToken));
        tokenIn.safeTransferFrom(_msgSender(), address(this), desc.amount);
        tokenIn.safeTransfer(buyStrategy, desc.amount);
        IFireBirdStrategy(buyStrategy).swap(fireBird, caller, desc, data);
        // Sell tokens
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        swaps[0].amount = desc.dstToken.balanceOf(sellStrategy);
        IVaultStrategy(sellStrategy).batchSwap(
            vault,
            IVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            fundsSell,
            getLimitsForVault(assets.length),
            deadline
        );

        _ensureProfit(desc.amount, tokenIn);
    }

    /**
     * @dev Buy tokens with 1inch and sell tokens with firebird
     */
    function swapTokens1InchAndFireBird(
        address fireBird,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription memory descFireBird,
        bytes memory dataFireBird,
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory descInch,
        bytes memory dataInch
    ) private {
        // Buy tokens
        address buyStrategy = get1InchStrategy(oneInch);
        address sellStrategy = getFireBirdStrategy(fireBird);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(address(descInch.srcToken));
        tokenIn.safeTransferFrom(_msgSender(), address(this), descInch.amount);
        tokenIn.safeTransfer(buyStrategy, descInch.amount);
        I1InchStrategy(buyStrategy).swap(oneInch, executor, descInch, ZERO_BYTES, dataInch);
        // Sell tokens
        descFireBird.amount = IERC20Upgradeable(address(descFireBird.srcToken)).balanceOf(sellStrategy);
        IFireBirdStrategy(sellStrategy).swap(fireBird, caller, descFireBird, dataFireBird);

        _ensureProfit(descInch.amount, tokenIn);
    }

    /**
     * @dev Buy tokens with firebird and sell tokens with 1inch
     */
    function swapTokensFireBirdAnd1Inch(
        address fireBird,
        IAggregationExecutor caller,
        IFireBirdRouter.SwapDescription memory descFireBird,
        bytes memory dataFireBird,
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory descInch,
        bytes memory dataInch
    ) private {
        // Buy tokens
        address buyStrategy = get1InchStrategy(oneInch);
        address sellStrategy = getFireBirdStrategy(fireBird);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(address(descFireBird.srcToken));
        tokenIn.safeTransferFrom(_msgSender(), address(this), descFireBird.amount);
        tokenIn.safeTransfer(buyStrategy, descFireBird.amount);
        IFireBirdStrategy(sellStrategy).swap(fireBird, caller, descFireBird, dataFireBird);
        // Sell tokens
        descInch.amount = descInch.srcToken.balanceOf(sellStrategy);
        I1InchStrategy(buyStrategy).swap(oneInch, executor, descInch, ZERO_BYTES, dataInch);

        _ensureProfit(descFireBird.amount, tokenIn);
    }

    /**
     * @dev Buy tokens with vault and sell tokens with odos
     */
    function swapTokensVaultAndOdos(
        address odos,
        IOdosRouter.swapTokenInfo memory tokenInfo,
        bytes memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline
    ) private {
        address buyStrategy = getVaultStrategy(vault);
        address sellStrategy = getOdosStrategy(odos);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(assets[swaps[0].assetInIndex]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), swaps[0].amount);
        tokenIn.safeTransfer(buyStrategy, swaps[0].amount);

        // Buy tokens
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        IVaultStrategy(buyStrategy).batchSwap(
            vault,
            IVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            fundsBuy,
            getLimitsForVault(assets.length),
            deadline
        );

        // Sell tokens
        tokenInfo.inputAmount = IERC20Upgradeable(tokenInfo.inputToken).balanceOf(sellStrategy);
        bytes32 newAmountBytes = bytes32(tokenInfo.inputAmount);
        uint8 length = uint8(data[48]); // 48th byte marks the length of `tokenInfo.inputToken`
        for (uint8 i = 0; i < length; i++) {
            data[49 + i] = newAmountBytes[32 - length + i];
        }
        IOdosStrategy(sellStrategy).swapCompact(odos, tokenInfo, data);

        _ensureProfit(swaps[0].amount, tokenIn);
    }

    /**
     * @dev Buy tokens with odos and sell tokens with vault
     */
    function swapTokensOdosAndVault(
        address odos,
        IOdosRouter.swapTokenInfo memory tokenInfo,
        bytes memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline
    ) private {
        address buyStrategy = getOdosStrategy(odos);
        address sellStrategy = getVaultStrategy(vault);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(tokenInfo.inputToken);
        tokenIn.safeTransferFrom(_msgSender(), address(this), tokenInfo.inputAmount);
        tokenIn.safeTransfer(buyStrategy, tokenInfo.inputAmount);

        // Buy tokens
        IOdosStrategy(buyStrategy).swapCompact(odos, tokenInfo, data);

        // Sell tokens
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        swaps[0].amount = IERC20Upgradeable(tokenInfo.outputToken).balanceOf(sellStrategy);
        IVaultStrategy(sellStrategy).batchSwap(
            vault,
            IVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            fundsSell,
            getLimitsForVault(assets.length),
            deadline
        );

        _ensureProfit(tokenInfo.inputAmount, tokenIn);
    }

    /**
     * @dev Buy tokens with vault and sell tokens with paraswap
     */
    function swapTokensVaultAndPara(
        address para,
        Utils.SimpleData memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline
    ) private {
        address buyStrategy = getVaultStrategy(vault);
        address sellStrategy = getParaStrategy(para);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(assets[swaps[0].assetInIndex]);
        tokenIn.safeTransferFrom(_msgSender(), address(this), swaps[0].amount);
        tokenIn.safeTransfer(buyStrategy, swaps[0].amount);

        // Buy tokens
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: buyStrategy,
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        IVaultStrategy(buyStrategy).batchSwap(
            vault,
            IVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            fundsBuy,
            getLimitsForVault(assets.length),
            deadline
        );

        // Sell tokens
        data.fromAmount = IERC20Upgradeable(data.fromToken).balanceOf(sellStrategy);
        IParaswapStrategy(sellStrategy).simpleSwap(para, data);

        _ensureProfit(swaps[0].amount, tokenIn);
    }

    /**
     * @dev Buy tokens with paraswap and sell tokens with vault
     */
    function swapTokensParaAndVault(
        address para,
        Utils.SimpleData memory data,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline
    ) private {
        address buyStrategy = getParaStrategy(para);
        address sellStrategy = getVaultStrategy(vault);
        IERC20Upgradeable tokenIn = IERC20Upgradeable(data.fromToken);
        tokenIn.safeTransferFrom(_msgSender(), address(this), data.fromAmount);
        tokenIn.safeTransfer(buyStrategy, data.fromAmount);

        // Buy tokens
        IParaswapStrategy(buyStrategy).simpleSwap(para, data);

        // Sell tokens
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        swaps[0].amount = IERC20Upgradeable(data.toToken).balanceOf(sellStrategy);
        IVaultStrategy(sellStrategy).batchSwap(
            vault,
            IVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            fundsSell,
            getLimitsForVault(assets.length),
            deadline
        );

        _ensureProfit(data.fromAmount, tokenIn);
    }
}

