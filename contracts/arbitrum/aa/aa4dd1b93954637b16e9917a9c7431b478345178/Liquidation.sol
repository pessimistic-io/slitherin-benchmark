// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./ReentrancyGuardUpgradeable.sol";
import "./library_Math.sol";
import "./SafeMath.sol";

import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IERC20.sol";
import "./interfaces_IWETH.sol";
import "./TransferHelper.sol";

import "./SafeToken.sol";
import "./WhitelistUpgradeable.sol";

import "./ICore.sol";
import "./IGToken.sol";
import "./IPriceCalculator.sol";
import "./IFlashLoanReceiver.sol";
import "./IPool.sol";

contract Liquidation is IFlashLoanReceiver, WhitelistUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    address private constant ETH = address(0);
    address private constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address private constant WBTC = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    address private constant DAI = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    address private constant USDT = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address private constant USDC = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    IUniswapV2Factory private constant factory = IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);
    IUniswapV2Router02 private constant router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IPool private constant lendPool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    /* ========== STATE VARIABLES ========== */

    mapping(address => mapping(address => bool)) private tokenApproval;
    ICore public core;
    IPriceCalculator public priceCalculator;

    receive() external payable {}

    /* ========== Event ========== */

    event Liquidated(
        address gTokenBorrowed,
        address gTokenCollateral,
        address borrower,
        uint256 amount,
        uint256 rebateAmount
    );

    /* ========== INITIALIZER ========== */

    function initialize(address _core, address _priceCalculator) external initializer {
        require(_core != address(0), "Liquidation: core address can't be zero");
        require(_priceCalculator != address(0), "Liquidation: priceCalculator address can't be zero");

        __ReentrancyGuard_init();
        __WhitelistUpgradeable_init();

        core = ICore(_core);
        priceCalculator = IPriceCalculator(_priceCalculator);

        _approveTokens();
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Liquidate borrower's debt by manual
    /// @param gTokenBorrowed Market of debt to liquidate
    /// @param gTokenCollateral Market of collateral to seize
    /// @param borrower Borrower account address
    /// @param amount Liquidate underlying amount
    function liquidate(
        address gTokenBorrowed,
        address gTokenCollateral,
        address borrower,
        uint256 amount
    ) external onlyWhitelisted nonReentrant {
        (uint256 collateralInUSD, , uint256 borrowInUSD) = core.accountLiquidityOf(borrower);
        require(borrowInUSD > collateralInUSD, "Liquidation: Insufficient shortfall");

        _flashLoan(gTokenBorrowed, gTokenCollateral, borrower, amount);

        address underlying = IGToken(gTokenBorrowed).underlying();

        emit Liquidated(
            gTokenBorrowed,
            gTokenCollateral,
            borrower,
            amount,
            underlying == ETH
                ? address(this).balance
                : IERC20(IGToken(gTokenBorrowed).underlying()).balanceOf(address(this))
        );

        _sendTokenToRebateDistributor(underlying);
    }

    /// @notice Liquidate borrower's max value debt using max value collateral
    /// @param borrower borrower account address
    function autoLiquidate(address borrower) external onlyWhitelisted nonReentrant {
        (uint256 collateralInUSD, , uint256 borrowInUSD) = core.accountLiquidityOf(borrower);
        require(borrowInUSD > collateralInUSD, "Liquidation: Insufficient shortfall");

        (address gTokenBorrowed, address gTokenCollateral) = _getTargetMarkets(borrower);
        uint256 liquidateAmount = _getMaxLiquidateAmount(gTokenBorrowed, gTokenCollateral, borrower);
        require(liquidateAmount > 0, "Liquidation: liquidate amount error");

        _flashLoan(gTokenBorrowed, gTokenCollateral, borrower, liquidateAmount);

        address underlying = IGToken(gTokenBorrowed).underlying();

        emit Liquidated(
            gTokenBorrowed,
            gTokenCollateral,
            borrower,
            liquidateAmount,
            underlying == ETH
                ? address(this).balance
                : IERC20(IGToken(gTokenBorrowed).underlying()).balanceOf(address(this))
        );

        _sendTokenToRebateDistributor(underlying);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _approveTokens() private {
        address[] memory markets = core.allMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            address token = IGToken(markets[i]).underlying();
            _approveToken(token, address(markets[i]));
            _approveToken(token, address(router));
            _approveToken(token, address(lendPool));
        }
        _approveToken(WETH, address(router));
        _approveToken(WETH, address(lendPool));
    }

    function _approveToken(address token, address spender) private {
        if (token != ETH && !tokenApproval[token][spender]) {
            token.safeApprove(spender, uint256(-1));
            tokenApproval[token][spender] = true;
        }
    }

    function _flashLoan(address gTokenBorrowed, address gTokenCollateral, address borrower, uint256 amount) private {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        bytes memory params = abi.encode(gTokenBorrowed, gTokenCollateral, borrower, amount);

        address underlying = IGToken(gTokenBorrowed).underlying();

        assets[0] = underlying == ETH ? WETH : underlying;
        amounts[0] = amount;
        modes[0] = 0;

        lendPool.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(lendPool), "Liquidation: Invalid sender");
        require(initiator == address(this), "Liquidation Invalid initiator");
        require(assets.length == 1, "Liquidation: Invalid assets");
        require(amounts.length == 1, "Liquidation: Invalid amounts");
        require(premiums.length == 1, "Liquidation: Invalid premiums");
        (address gTokenBorrowed, address gTokenCollateral, address borrower, uint256 liquidateAmount) = abi.decode(
            params,
            (address, address, address, uint256)
        );
        uint256 repayAmount = amounts[0].add(premiums[0]);

        if (assets[0] == WETH) {
            IWETH(WETH).withdraw(amounts[0]);
        }

        _liquidate(gTokenBorrowed, gTokenCollateral, borrower, liquidateAmount);

        if (IGToken(gTokenCollateral).underlying() == ETH) {
            IWETH(WETH).deposit{value: address(this).balance}();
        }

        if (gTokenCollateral != gTokenBorrowed) {
            _swapForRepay(gTokenCollateral, gTokenBorrowed, repayAmount);
        }

        return true;
    }

    function _liquidate(address gTokenBorrowed, address gTokenCollateral, address borrower, uint256 amount) private {
        if (IGToken(gTokenBorrowed).underlying() == ETH) {
            core.liquidateBorrow{value: amount}(gTokenBorrowed, gTokenCollateral, borrower, 0);
        } else {
            core.liquidateBorrow(gTokenBorrowed, gTokenCollateral, borrower, amount);
        }

        uint256 gTokenCollateralBalance = IGToken(gTokenCollateral).balanceOf(address(this));
        _redeemToken(gTokenCollateral, gTokenCollateralBalance);
    }

    function _getTargetMarkets(
        address account
    ) private view returns (address gTokenBorrowed, address gTokenCollateral) {
        uint256 maxSupplied;
        uint256 maxBorrowed;
        address[] memory markets = core.marketListOf(account);
        uint256[] memory prices = priceCalculator.getUnderlyingPrices(markets);

        for (uint256 i = 0; i < markets.length; i++) {
            uint256 borrowValue = IGToken(markets[i]).borrowBalanceOf(account).mul(prices[i]).div(1e18);
            uint256 supplyValue = IGToken(markets[i]).underlyingBalanceOf(account).mul(prices[i]).div(1e18);

            if (borrowValue > 0 && borrowValue > maxBorrowed) {
                maxBorrowed = borrowValue;
                gTokenBorrowed = markets[i];
            }

            uint256 collateralFactor = core.marketInfoOf(markets[i]).collateralFactor;
            if (collateralFactor > 0 && supplyValue > 0 && supplyValue > maxSupplied) {
                maxSupplied = supplyValue;
                gTokenCollateral = markets[i];
            }
        }
    }

    function _getMaxLiquidateAmount(
        address gTokenBorrowed,
        address gTokenCollateral,
        address borrower
    ) private view returns (uint256 liquidateAmount) {
        uint256 borrowPrice = priceCalculator.getUnderlyingPrice(gTokenBorrowed);
        uint256 supplyPrice = priceCalculator.getUnderlyingPrice(gTokenCollateral);
        require(supplyPrice != 0 && borrowPrice != 0, "Liquidation: price error");

        uint256 borrowAmount = IGToken(gTokenBorrowed).borrowBalanceOf(borrower);
        uint256 supplyAmount = IGToken(gTokenCollateral).underlyingBalanceOf(borrower);

        uint256 borrowValue = borrowPrice.mul(borrowAmount).div(10 ** _getDecimals(gTokenBorrowed));
        uint256 supplyValue = supplyPrice.mul(supplyAmount).div(10 ** _getDecimals(gTokenCollateral));

        uint256 liquidationIncentive = core.liquidationIncentive();
        uint256 maxCloseValue = borrowValue.mul(core.closeFactor()).div(1e18);
        uint256 maxCloseValueWithIncentive = maxCloseValue.mul(liquidationIncentive).div(1e18);

        liquidateAmount = maxCloseValueWithIncentive < supplyValue
            ? maxCloseValue.mul(1e18).div(borrowPrice).div(10 ** (18 - _getDecimals(gTokenBorrowed)))
            : supplyValue.mul(1e36).div(liquidationIncentive).div(borrowPrice).div(
                10 ** (18 - _getDecimals(gTokenBorrowed))
            );
    }

    function _redeemToken(address gToken, uint256 gAmount) private {
        core.redeemToken(gToken, gAmount);
    }

    function _sendTokenToRebateDistributor(address token) private {
        address rebateDistributor = core.rebateDistributor();
        uint256 balance = token == ETH ? address(this).balance : IERC20(token).balanceOf(address(this));

        if (balance > 0 && token == ETH) {
            SafeToken.safeTransferETH(rebateDistributor, balance);
        } else if (balance > 0) {
            token.safeTransfer(rebateDistributor, balance);
        }
    }

    function _swapForRepay(address gTokenCollateral, address gTokenBorrowed, uint256 minReceiveAmount) private {
        address collateralToken = IGToken(gTokenCollateral).underlying();
        if (collateralToken == ETH) {
            collateralToken = WETH;
        }

        uint256 collateralTokenAmount = IERC20(collateralToken).balanceOf(address(this));
        require(collateralTokenAmount > 0, "Liquidation: Insufficent collateral");

        address borrowToken = IGToken(gTokenBorrowed).underlying();
        _swapToken(collateralToken, collateralTokenAmount, borrowToken, minReceiveAmount);
    }

    function _swapToken(address token, uint256 amount, address receiveToken, uint256 minReceiveAmount) private {
        address[] memory path = _getSwapPath(token == ETH ? WETH : token, receiveToken == ETH ? WETH : receiveToken);
        router.swapExactTokensForTokens(amount, minReceiveAmount, path, address(this), block.timestamp);
    }

    function _getSwapPath(address token1, address token2) private pure returns (address[] memory) {
        if (token1 == WETH || token2 == WETH) {
            address[] memory path = new address[](2);
            path[0] = token1;
            path[1] = token2;
            return path;
        } else {
            address[] memory path = new address[](3);
            path[0] = token1;
            path[1] = WETH;
            path[2] = token2;
            return path;
        }
    }

    /// @notice View underlying token decimals by gToken address
    /// @param gToken gToken address
    function _getDecimals(address gToken) private view returns (uint256 decimals) {
        address underlying = IGToken(gToken).underlying();
        if (underlying == address(0)) {
            decimals = 18;
        } else {
            decimals = IERC20(underlying).decimals();
        }
    }
}

