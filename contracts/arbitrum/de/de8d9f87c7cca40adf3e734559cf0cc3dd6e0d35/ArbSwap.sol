// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./IUniV2Strategy.sol";
import "./IVaultStrategy.sol";
import "./IUniV3Strategy.sol";
import "./I1InchStrategy.sol";
import "./IVault.sol";
import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";
import "./WithdrawableUpgradeable.sol";

contract ArbSwap is WithdrawableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    bytes public constant ZERO_BYTES = '';

    IUniV2Strategy public defaultUniV2Strategy;
    mapping(address => IUniV2Strategy) public uniV2Strategies;

    IVaultStrategy public defaultVaultStrategy;
    mapping(address => IVaultStrategy) public vaultStrategies;

    IUniV3Strategy public defaultUniV3Strategy;
    mapping(address => IUniV3Strategy) public uniV3Strategies;

    I1InchStrategy public default1InchStrategy;
    mapping(address => I1InchStrategy) public oneInchStrategies;

    receive() external payable {
        // Required to receive funds
    }

    function initialize() public initializer {
        __Withdrawable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    function getUniV2Strategy(address uniV2) public view returns (IUniV2Strategy strategy) {
        IUniV2Strategy _strat = uniV2Strategies[uniV2];
        return _strat != IUniV2Strategy(address(0)) ? _strat : defaultUniV2Strategy;
    }

    function getVaultStrategy(address vault) public view returns (IVaultStrategy strategy) {
        IVaultStrategy _strat = vaultStrategies[vault];
        return _strat != IVaultStrategy(address(0)) ? _strat : defaultVaultStrategy;
    }

    function getUniV3Strategy(address uniV3) public view returns (IUniV3Strategy strategy) {
        IUniV3Strategy _strat = uniV3Strategies[uniV3];
        return _strat != IUniV3Strategy(address(0)) ? _strat : defaultUniV3Strategy;
    }

    function get1InchStrategy(address oneInch) public view returns (I1InchStrategy strategy) {
        I1InchStrategy _strat = oneInchStrategies[oneInch];
        return _strat != I1InchStrategy(address(0)) ? _strat : default1InchStrategy;
    }

    function setDefaultUniV2Strategy(IUniV2Strategy strategy) public onlyOwner {
        defaultUniV2Strategy = strategy;
    }

    function setDefaultVaultStrategy(IVaultStrategy strategy) public onlyOwner {
        defaultVaultStrategy = strategy;
    }

    function setDefaultUniV3Strategy(IUniV3Strategy strategy) public onlyOwner {
        defaultUniV3Strategy = strategy;
    }

    function setDefault1InchStrategy(I1InchStrategy strategy) public onlyOwner {
        default1InchStrategy = strategy;
    }

    function setUniV2Strategy(address uniV2, IUniV2Strategy strategy) public onlyOwner {
        uniV2Strategies[uniV2] = strategy;
    }

    function setVaultStrategy(address vault, IVaultStrategy strategy) public onlyOwner {
        vaultStrategies[vault] = strategy;
    }

    function setUniV3Strategy(address uniV3, IUniV3Strategy strategy) public onlyOwner {
        uniV3Strategies[uniV3] = strategy;
    }

    function set1InchStrategy(address oneInch, I1InchStrategy strategy) public onlyOwner {
        oneInchStrategies[oneInch] = strategy;
    }

    function setup(
        IUniV2Strategy uniV2Strategy,
        IVaultStrategy vaultStrategy,
        IUniV3Strategy uniV3Strategy,
        I1InchStrategy oneInchStrategy
    ) public onlyOwner {
        defaultUniV2Strategy = uniV2Strategy;
        defaultVaultStrategy = vaultStrategy;
        defaultUniV3Strategy = uniV3Strategy;
        default1InchStrategy = oneInchStrategy;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function arbFromETH(
        address uniV2Buy,
        address[] calldata pathBuy,
        address uniV2Sell,
        address[] calldata pathSell,
        uint deadline
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        {
            IERC20Upgradeable _token = IERC20Upgradeable(pathBuy[pathBuy.length - 1]);
            IUniV2Strategy _sellStrategy = getUniV2Strategy(uniV2Sell);
            // Buy the tokens
            getUniV2Strategy(uniV2Buy).swapExactETHForTokens{ value: amountIn }(
                uniV2Buy,
                0,
                pathBuy,
                address(_sellStrategy),
                deadline
            );
            // Sell the tokens
            getUniV2Strategy(uniV2Sell).swapExactTokensForETH(
                uniV2Sell,
                _token.balanceOf(address(_sellStrategy)),
                0,
                pathSell,
                address(this),
                deadline
            );
        }
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithVault(
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsBuy,
        address[] memory assetsSell,
        int256[] memory limits,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        {
            IVaultStrategy sellStrategy = getVaultStrategy(vaultSell); //
            IVault.FundManagement memory fundsBuy = IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(sellStrategy)),
                toInternalBalance: false
            });
            getVaultStrategy(vaultBuy).batchSwap{ value: amountIn }(
                vaultBuy,
                IVault.SwapKind.GIVEN_IN,
                swapsBuy,
                assetsBuy,
                fundsBuy,
                limits,
                deadline
            );
            for (uint256 i = 0; i < swapsSell.length; i++) {
                IVault.BatchSwapStep memory swapStep = swapsSell[i];
                swapsSell[i].amount = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]).balanceOf(
                    address(sellStrategy)
                );
            }
            IVault.FundManagement memory fundsSell = IVault.FundManagement({
                sender: address(sellStrategy),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            });
            getVaultStrategy(vaultSell).batchSwap(
                vaultSell,
                IVault.SwapKind.GIVEN_IN,
                swapsSell,
                assetsSell,
                fundsSell,
                limits,
                deadline
            );
        }
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithVaultAndUniV2(
        address uniV2Router,
        address[] memory path,
        address vaultRouter,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapUniV2AndVault(uniV2Router, path, vaultRouter, swaps, assets, limits, deadline);
        else swapVaultAndUniV2(uniV2Router, path, vaultRouter, swaps, assets, limits, deadline);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithUniV3(
        address uniV3Buy,
        ISwapRouter.ExactInputSingleParams memory paramsBuy,
        address uniV3Sell,
        ISwapRouter.ExactInputSingleParams memory paramsSell,
        uint deadline
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        IUniV3Strategy sellStrategy = getUniV3Strategy(uniV3Sell);
        getUniV3Strategy(uniV3Buy).exactInputSingle{ value: amountIn }(uniV3Buy, paramsBuy);
        paramsSell.amountIn = IERC20Upgradeable(paramsBuy.tokenOut).balanceOf(address(sellStrategy));
        getUniV3Strategy(uniV3Sell).exactInputSingle(uniV3Sell, paramsSell);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithUniV3AndUniV2(
        address uniV2,
        address[] calldata path,
        address uniV3,
        ISwapRouter.ExactInputSingleParams memory params,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapUniV2AndUniV3(uniV2, path, uniV3, params, deadline);
        else swapUniV3AndUniV2(uniV3, params, uniV2, path, deadline);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithUniV3AndVault(
        address uniV3,
        ISwapRouter.ExactInputSingleParams memory params,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapVaultAndUniV3(vault, swaps, assets, limits, uniV3, params, deadline);
        else swapUniV3AndVault(uniV3, params, vault, swaps, assets, limits, deadline);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWith1Inch(
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        uint amountIn = address(this).balance;
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        get1InchStrategy(oneInchBuy).swap{ value: amountIn }(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, ZERO_BYTES);
        descSell.amount = descBuy.dstToken.balanceOf(sellStrategy);
        get1InchStrategy(oneInchSell).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, ZERO_BYTES);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWith1InchAndUniV2(
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory desc,
        address uniV2,
        address[] memory path,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapUniV2And1Inch(oneInch, executor, desc, uniV2, path, deadline);
        else swap1InchAndUniV2(oneInch, executor, desc, uniV2, path, deadline);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWith1InchAndUniV3(
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory desc,
        address uniV3,
        ISwapRouter.ExactInputSingleParams memory params,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapUniV3And1Inch(oneInch, executor, desc, uniV3, params);
        else swap1InchAndUniV3(oneInch, executor, desc, uniV3, params);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWith1InchAndVault(
        address oneInch,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription memory desc,
        address vault,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapVaultAnd1Inch(oneInch, executor, desc, vault, swaps, assets, deadline);
        else swap1InchAndVault(oneInch, executor, desc, vault, swaps, assets, deadline);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function getAmountsOut(
        address router,
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts) {
        return getUniV2Strategy(router).getAmountsOut(router, amountIn, path);
    }

    function swapUniV2AndVault(
        address uniV2Buy,
        address[] memory pathBuy,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline
    ) private {
        uint amountIn = address(this).balance;

        address sellStrategy = address(getVaultStrategy(vaultSell));
        getUniV2Strategy(uniV2Buy).swapExactETHForTokens{ value: amountIn }(
            uniV2Buy,
            0,
            pathBuy,
            sellStrategy,
            deadline
        );
        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        for (uint256 i = 0; i < swapsSell.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsSell[i];
            swapsSell[i].amount = IERC20Upgradeable(assets[swapStep.assetInIndex]).balanceOf(address(sellStrategy));
        }
        getVaultStrategy(vaultSell).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assets,
            fundsSell,
            limits,
            deadline
        );
    }

    function swapVaultAndUniV2(
        address uniV2Sell,
        address[] memory pathSell,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline
    ) private {
        uint amountIn = address(this).balance;

        address sellStrategy = address(getUniV2Strategy(uniV2Sell));
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
            assets,
            fundsBuy,
            limits,
            deadline
        );
        IERC20Upgradeable _token = IERC20Upgradeable(assets[swapsBuy[swapsBuy.length - 1].assetOutIndex]);
        getUniV2Strategy(uniV2Sell).swapExactTokensForETH(
            uniV2Sell,
            _token.balanceOf(sellStrategy),
            0,
            pathSell,
            address(this),
            deadline
        );
    }

    function swapUniV2AndUniV3(
        address uniV2Buy,
        address[] calldata pathBuy,
        address uniV3Sell,
        ISwapRouter.ExactInputSingleParams memory paramsSell,
        uint deadline
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(getUniV3Strategy(uniV3Sell));

        getUniV2Strategy(uniV2Buy).swapExactETHForTokens{ value: amountIn }(
            uniV2Buy,
            0,
            pathBuy,
            sellStrategy,
            deadline
        );
        IERC20Upgradeable token = IERC20Upgradeable(pathBuy[pathBuy.length - 1]);
        paramsSell.amountIn = token.balanceOf(sellStrategy);
        getUniV3Strategy(uniV3Sell).exactInputSingle(uniV3Sell, paramsSell);
    }

    function swapUniV3AndUniV2(
        address uniV3Buy,
        ISwapRouter.ExactInputSingleParams memory paramsBuy,
        address uniV2Sell,
        address[] calldata pathSell,
        uint deadline
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(getUniV2Strategy(uniV2Sell));

        getUniV3Strategy(uniV3Buy).exactInputSingle{ value: amountIn }(uniV3Buy, paramsBuy);
        IERC20Upgradeable token = IERC20Upgradeable(paramsBuy.tokenOut);
        getUniV2Strategy(uniV2Sell).swapExactTokensForETH(
            uniV2Sell,
            token.balanceOf(sellStrategy),
            0,
            pathSell,
            address(this),
            deadline
        );
    }

    function swapVaultAndUniV3(
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assets,
        int256[] memory limits,
        address uniV3Sell,
        ISwapRouter.ExactInputSingleParams memory paramsSell,
        uint deadline
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(getUniV3Strategy(uniV3Sell));

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
            assets,
            fundsBuy,
            limits,
            deadline
        );
        IERC20Upgradeable token = IERC20Upgradeable(assets[swapsBuy[swapsBuy.length - 1].assetOutIndex]);
        paramsSell.amountIn = token.balanceOf(sellStrategy);
        getUniV3Strategy(uniV3Sell).exactInputSingle(uniV3Sell, paramsSell);
    }

    function swapUniV3AndVault(
        address uniV3Buy,
        ISwapRouter.ExactInputSingleParams memory paramsBuy,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline
    ) private {
        uint amountIn = address(this).balance;

        address sellStrategy = address(getVaultStrategy(vaultSell));
        getUniV3Strategy(uniV3Buy).exactInputSingle{ value: amountIn }(uniV3Buy, paramsBuy);

        IVault.FundManagement memory fundsSell = IVault.FundManagement({
            sender: sellStrategy,
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        for (uint256 i = 0; i < swapsSell.length; i++) {
            IVault.BatchSwapStep memory swapStep = swapsSell[i];
            swapsSell[i].amount = IERC20Upgradeable(assets[swapStep.assetInIndex]).balanceOf(address(sellStrategy));
        }
        getVaultStrategy(vaultSell).batchSwap(
            vaultSell,
            IVault.SwapKind.GIVEN_IN,
            swapsSell,
            assets,
            fundsSell,
            limits,
            deadline
        );
    }

    function swapUniV2And1Inch(
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell,
        address uniV2Buy,
        address[] memory pathBuy,
        uint256 deadline
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        getUniV2Strategy(uniV2Buy).swapExactETHForTokens{ value: amountIn }(
            uniV2Buy,
            0,
            pathBuy,
            sellStrategy,
            deadline
        );
        descSell.amount = descSell.srcToken.balanceOf(sellStrategy);
        get1InchStrategy(oneInchSell).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, ZERO_BYTES);
    }

    function swap1InchAndUniV2(
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        address uniV2Sell,
        address[] memory pathSell,
        uint256 deadline
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(getUniV2Strategy(uniV2Sell));
        get1InchStrategy(oneInchBuy).swap{ value: amountIn }(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, ZERO_BYTES);
        getUniV2Strategy(uniV2Sell).swapExactTokensForETH(
            uniV2Sell,
            descBuy.dstToken.balanceOf(sellStrategy),
            0,
            pathSell,
            address(this),
            deadline
        );
    }

    function swapUniV3And1Inch(
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell,
        address uniV3Buy,
        ISwapRouter.ExactInputSingleParams memory paramsBuy
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(get1InchStrategy(oneInchSell));
        getUniV3Strategy(uniV3Buy).exactInputSingle{ value: amountIn }(uniV3Buy, paramsBuy);
        descSell.amount = descSell.srcToken.balanceOf(sellStrategy);
        get1InchStrategy(oneInchSell).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, ZERO_BYTES);
    }

    function swap1InchAndUniV3(
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        address uniV3Sell,
        ISwapRouter.ExactInputSingleParams memory paramsSell
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(getUniV3Strategy(uniV3Sell));
        get1InchStrategy(oneInchBuy).swap{ value: amountIn }(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, ZERO_BYTES);
        paramsSell.amountIn = descBuy.dstToken.balanceOf(sellStrategy);
        getUniV3Strategy(uniV3Sell).exactInputSingle(uniV3Sell, paramsSell);
    }

    function swapVaultAnd1Inch(
        address oneInchSell,
        IAggregationExecutor executorSell,
        I1InchRouter.SwapDescription memory descSell,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assetsBuy,
        uint256 deadline
    ) private {
        uint amountIn = address(this).balance;
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
        descSell.amount = descSell.srcToken.balanceOf(sellStrategy);
        get1InchStrategy(oneInchSell).swap(oneInchSell, executorSell, descSell, ZERO_BYTES, ZERO_BYTES);
    }

    function swap1InchAndVault(
        address oneInchBuy,
        IAggregationExecutor executorBuy,
        I1InchRouter.SwapDescription memory descBuy,
        address vaultSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsSell,
        uint256 deadline
    ) private {
        uint amountIn = address(this).balance;
        address sellStrategy = address(getVaultStrategy(vaultSell));
        get1InchStrategy(oneInchBuy).swap{ value: amountIn }(oneInchBuy, executorBuy, descBuy, ZERO_BYTES, ZERO_BYTES);
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
}

