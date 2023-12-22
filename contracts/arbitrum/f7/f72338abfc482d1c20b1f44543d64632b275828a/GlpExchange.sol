// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Test.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {IRewardRouter} from "./IRewardRouter.sol";
import {IVault} from "./IVault.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IGlp} from "./IGlp.sol";
import {IPriceUtils} from "./IPriceUtils.sol";
import {IExchange, Purchase, TradeType} from "./IExchange.sol";
import {DeltaNeutralVault} from "./DeltaNeutralVault.sol";

contract GlpExchange is IExchange, Test {
    ERC20 private usdcToken;
    IRewardRouter private rewardRouter;
    IVault private vault;
    IGlpManager private glpManager;
    IGlp private glp;
    IPriceUtils private priceUtils;
    address private usdcAddress;
    address private glpAddress;
    DeltaNeutralVault private deltaNeutralVault;

    uint256 private constant PERCENT_DIVISOR = 1000;
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
    uint256 private constant DEFAULT_SLIPPAGE = 30;
    uint256 private constant PRICE_PRECISION = 10 ** 30;
    uint256 private constant USDC_DIVISOR = 1*10**6;

    constructor(address _usdcAddress, address _rewardRouterAddress, address _vaultAddress, address _priceUtilsAddress, address _deltaNeutralVaultAddress) {
        usdcAddress = _usdcAddress;
        usdcToken = ERC20(_usdcAddress);
        rewardRouter = IRewardRouter(_rewardRouterAddress);
        vault = IVault(_vaultAddress);
        priceUtils = IPriceUtils(_priceUtilsAddress);
        deltaNeutralVault = DeltaNeutralVault(_deltaNeutralVaultAddress);
    }

    modifier checkAllowance(uint amount) {
        require(usdcToken.allowance(msg.sender, address(this)) >= amount, "Allowance Error");
        _;
    }

    function tradeType() external pure returns (TradeType) {
        return TradeType.Buy;
    }

    function buy(uint256 usdcAmount) external returns (Purchase memory) {
        uint256 price = priceUtils.glpPrice();
        uint256 glpToPurchase = usdcAmount * price / USDC_DIVISOR;
        
        usdcToken.transferFrom(address(deltaNeutralVault), address(this), usdcAmount);

        uint256 glpAmountAfterSlippage = glpToPurchase * (BASIS_POINTS_DIVISOR - DEFAULT_SLIPPAGE) / BASIS_POINTS_DIVISOR;
        emit log("testing1");
        uint256 glpAmount = rewardRouter.mintAndStakeGlp(usdcAddress, usdcAmount, 0, glpAmountAfterSlippage);

        return Purchase({
            usdcAmount: usdcAmount,
            tokenAmount: glpAmount
        });
    }

    function sell(uint256 usdcAmount) external returns (Purchase memory) {
        uint256 price = priceUtils.glpPrice();
        uint256 glpToSell = usdcAmount * price / USDC_DIVISOR;
        uint256 usdcAmountAfterSlippage = usdcAmount * (BASIS_POINTS_DIVISOR - DEFAULT_SLIPPAGE) / BASIS_POINTS_DIVISOR;

        uint256 usdcRetrieved = rewardRouter.unstakeAndRedeemGlp(usdcAddress, glpToSell, usdcAmountAfterSlippage, address(deltaNeutralVault));

        return Purchase({
            usdcAmount: usdcRetrieved,
            tokenAmount: glpToSell 
        });        
    }
}

