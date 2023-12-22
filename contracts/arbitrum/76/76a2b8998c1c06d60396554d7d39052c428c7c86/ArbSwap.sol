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
import "./IVault.sol";
import "./WithdrawableUpgradeable.sol";

contract ArbSwap is WithdrawableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    IUniV2Strategy public defaultUniV2Strategy;
    mapping(address => IUniV2Strategy) public uniV2Strategies;

    IVaultStrategy public defaultVaultStrategy;
    mapping(address => IVaultStrategy) public vaultStrategies;

    IUniV3Strategy public defaultUniV3Strategy;
    mapping(address => IUniV3Strategy) public uniV3Strategies;

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
        IVaultStrategy _start = vaultStrategies[vault];
        return _start != IVaultStrategy(address(0)) ? _start : defaultVaultStrategy;
    }

    function getUniV3Strategy(address uniV3) public view returns (IUniV3Strategy strategy) {
        IUniV3Strategy _strat = uniV3Strategies[uniV3];
        return _strat != IUniV3Strategy(address(0)) ? _strat : defaultUniV3Strategy;
    }

    function setDefaultSwapStrategy(IUniV2Strategy strategy) public onlyOwner {
        defaultUniV2Strategy = strategy;
    }

    function setDefaultVaultStrategy(IVaultStrategy strategy) public onlyOwner {
        defaultVaultStrategy = strategy;
    }

    function setDefaultUniV3Strategy(IUniV3Strategy strategy) public onlyOwner {
        defaultUniV3Strategy = strategy;
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

    function setup(
        IUniV2Strategy swapStrategy,
        IVaultStrategy vaultStrategy,
        IUniV3Strategy uniV3Strategy
    ) public onlyOwner {
        defaultUniV2Strategy = swapStrategy;
        defaultVaultStrategy = vaultStrategy;
        defaultUniV3Strategy = uniV3Strategy;
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
        address uniV2Buy,
        address[] memory path,
        address uniV2Sell,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapUniV2AndVault(uniV2Sell, uniV2Buy, path, swaps, assets, limits, deadline);
        else swapVaultAndUniV2(uniV2Buy, path, uniV2Sell, swaps, assets, limits, deadline);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithUniV3(
        address uniV2Buy,
        ISwapRouter.ExactInputSingleParams memory paramsBuy,
        address uniV2Sell,
        ISwapRouter.ExactInputSingleParams memory paramsSell,
        uint deadline
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        IUniV3Strategy sellStrategy = getUniV3Strategy(uniV2Sell);
        getUniV3Strategy(uniV2Buy).exactInputSingle{ value: amountIn }(uniV2Buy, paramsBuy);
        paramsSell.amountIn = IERC20Upgradeable(paramsBuy.tokenOut).balanceOf(address(sellStrategy));
        getUniV3Strategy(uniV2Sell).exactInputSingle(uniV2Sell, paramsSell);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > amountIn, 'No profit');
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithUniV3AndUniV2(
        address router,
        address[] calldata path,
        address univ3,
        ISwapRouter.ExactInputSingleParams memory params,
        uint256 deadline,
        uint256 selector
    ) external payable nonReentrant whenNotPaused returns (uint actualAmountOut) {
        require(deadline >= block.timestamp, 'Deadline exceeded');
        uint amountIn = address(this).balance;
        if (selector == 0) swapUniV2AndUniV3(router, path, univ3, params, deadline);
        else swapUniV3AndUniV2(univ3, params, router, path, deadline);
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

    function getAmountsOut(
        address router,
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts) {
        return getUniV2Strategy(router).getAmountsOut(router, amountIn, path);
    }

    function swapUniV2AndVault(
        address vaultSell,
        address uniV2Buy,
        address[] memory pathBuy,
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
}

