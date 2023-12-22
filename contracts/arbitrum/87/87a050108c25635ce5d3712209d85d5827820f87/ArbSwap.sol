// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./WithdrawableUpgradeable.sol";
import "./ISwapStrategy.sol";
import "./IVaultStrategy.sol";
import "./IVault.sol";

contract ArbSwap is
    WithdrawableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address payable;

    ISwapStrategy public defaultSwapStrategy;
    mapping(address => ISwapStrategy) public swapStrategies;

    IVaultStrategy public defaultVaultStrategy;
    mapping(address => IVaultStrategy) public vaultStrategies;

    receive() external payable {
        // Required to receive funds
    }

    function initialize() public initializer {
        __Withdrawable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    function getSwapStrategy(
        address router
    ) public view returns (ISwapStrategy strategy) {
        ISwapStrategy _strat = swapStrategies[router];
        return
            _strat != ISwapStrategy(address(0)) ? _strat : defaultSwapStrategy;
    }

    function getVaultStrategy(
        address router
    ) public view returns (IVaultStrategy strategy) {
        IVaultStrategy _start = vaultStrategies[router];
        return
            _start != IVaultStrategy(address(0))
                ? _start
                : defaultVaultStrategy;
    }

    function setDefaultSwapStrategy(ISwapStrategy strategy) public onlyOwner {
        defaultSwapStrategy = strategy;
    }

    function setDefaultVaultStrategy(IVaultStrategy strategy) public onlyOwner {
        defaultVaultStrategy = strategy;
    }

    function setSwapStrategy(
        address router,
        ISwapStrategy strategy
    ) public onlyOwner {
        swapStrategies[router] = strategy;
    }

    function setVaultStrategy(
        address router,
        IVaultStrategy strategy
    ) public onlyOwner {
        vaultStrategies[router] = strategy;
    }

    function setup(
        ISwapStrategy swapStrategy,
        IVaultStrategy vaultStrategy
    ) public onlyOwner {
        defaultSwapStrategy = swapStrategy;
        defaultVaultStrategy = vaultStrategy;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function arbFromETH(
        address routerBuy,
        address[] calldata pathBuy,
        address routerSell,
        address[] calldata pathSell,
        uint deadline
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint actualAmountOut)
    {
        require(deadline >= block.timestamp, "Deadline exceeded");
        uint _amountIn = address(this).balance;
        {
            IERC20Upgradeable _token = IERC20Upgradeable(
                pathBuy[pathBuy.length - 1]
            );
            ISwapStrategy _sellStrategy = getSwapStrategy(routerSell);
            // Buy the tokens
            getSwapStrategy(routerBuy).swapExactETHForTokens{value: _amountIn}(
                routerBuy,
                0,
                pathBuy,
                address(_sellStrategy),
                deadline
            );
            // Sell the tokens
            getSwapStrategy(routerSell).swapExactTokensForETH(
                routerSell,
                _token.balanceOf(address(_sellStrategy)),
                0,
                pathSell,
                address(this),
                deadline
            );
        }
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        require(actualAmountOut > _amountIn, "No profit");
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithVault(
        address routerBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address routerSell,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assetsBuy,
        address[] memory assetsSell,
        int256[] memory limits,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint actualAmountOut)
    {
        require(deadline >= block.timestamp, "Deadline exceeded");
        uint _amountIn = address(this).balance;
        {
            IVaultStrategy sellStrategy = getVaultStrategy(routerSell); //
            IVault.FundManagement memory fundsBuy = IVault.FundManagement({
                sender: address(this),
                fromInternalBalance: false,
                recipient: payable(address(sellStrategy)),
                toInternalBalance: false
            });
            getVaultStrategy(routerBuy).batchSwap{value: _amountIn}(
                IVault.SwapKind.GIVEN_IN,
                swapsBuy,
                assetsBuy,
                fundsBuy,
                limits,
                deadline
            );
            for (uint256 i = 0; i < swapsSell.length; i++) {
                IVault.BatchSwapStep memory swapStep = swapsSell[i];
                swapsSell[i].amount = IERC20Upgradeable(assetsSell[swapStep.assetInIndex]).balanceOf(address(sellStrategy));
            }
            IVault.FundManagement memory fundsSell = IVault.FundManagement({
                sender: address(sellStrategy),
                fromInternalBalance: false,
                recipient: payable(address(this)),
                toInternalBalance: false
            });
            getVaultStrategy(routerSell).batchSwap(
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
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function arbFromETHWithVaultAndRouter(
        address routerBuy,
        address[] memory path,
        address routerSell,
        IVault.BatchSwapStep[] memory swaps,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline,
        uint256 selector
    )
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint actualAmountOut) 
    {
        require(deadline >= block.timestamp, "Deadline exceeded");

        if (selector == 0)
            swapRouterAndVault(routerSell, routerBuy, path, swaps, assets, limits, deadline);
        else 
            swapVaultAndRouter(routerBuy, path, path, routerSell, swaps, assets, limits, deadline);
        // Ensure we got a profit
        actualAmountOut = address(this).balance;
        // Send the funds
        payable(_msgSender()).sendValue(actualAmountOut);
    }

    function getAmountsOut(
        address router,
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts) {
        return getSwapStrategy(router).getAmountsOut(router, amountIn, path);
    }

    function swapRouterAndVault(
        address vaultSell,
        address routerBuy,
        address[] memory pathBuy,
        IVault.BatchSwapStep[] memory swapsSell,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline
    ) private {
        uint _amountIn = address(this).balance;

        address sellStrategy = address(getVaultStrategy(vaultSell));
        getSwapStrategy(routerBuy).swapExactETHForTokens{value: _amountIn}(
            routerBuy,
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
        getVaultStrategy(vaultSell).batchSwap(
            IVault.SwapKind.GIVEN_OUT,
            swapsSell,
            assets,
            fundsSell,
            limits,
            deadline
        );
    }
    
    function swapVaultAndRouter(
        address routerSell,
        address[] memory pathSell,
        address[] memory pathBuy,
        address vaultBuy,
        IVault.BatchSwapStep[] memory swapsBuy,
        address[] memory assets,
        int256[] memory limits,
        uint256 deadline
    ) private {
        uint _amountIn = address(this).balance;

        address sellStrategy = address(getSwapStrategy(routerSell));
        IVault.FundManagement memory fundsBuy = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(sellStrategy),
            toInternalBalance: false
        });
        getVaultStrategy(vaultBuy).batchSwap{value: _amountIn}(
            IVault.SwapKind.GIVEN_IN,
            swapsBuy,
            assets,
            fundsBuy,
            limits,
            deadline
        );
        IERC20Upgradeable _token = IERC20Upgradeable(
            pathBuy[pathBuy.length - 1]
        );
        getSwapStrategy(routerSell).swapExactTokensForETH(
            routerSell,
            _token.balanceOf(sellStrategy),
            0,
            pathSell,
            address(this),
            deadline
        );
    }
}

