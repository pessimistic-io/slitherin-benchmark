// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {IRewardRouter} from "./IRewardRouter.sol";
import {IVault} from "./IVault.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IGlp} from "./IGlp.sol";
import {IGlpPriceUtils} from "./IGlpPriceUtils.sol";
import {IPurchaser, Purchase} from "./IPurchaser.sol";

contract GlpPurchaser is IPurchaser {
    ERC20 private usdcToken;
    IRewardRouter private rewardRouter;
    IVault private vault;
    IGlpManager private glpManager;
    IGlp private glp;
    IGlpPriceUtils private glpPriceUtils;
    address private usdcAddress;
    address private glpAddress;

    uint256 private constant PERCENT_DIVISOR = 1000;
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
    uint256 private constant DEFAULT_SLIPPAGE = 30;
    uint256 private constant PRICE_PRECISION = 10 ** 30;
    uint256 private constant USDC_DIVISOR = 1*10**6;

    constructor(address _usdcAddress, address _rewardRouterAddress, address _vaultAddress, address _glpPriceUtilsAddress) {
        usdcAddress = _usdcAddress;
        usdcToken = ERC20(_usdcAddress);
        rewardRouter = IRewardRouter(_rewardRouterAddress);
        vault = IVault(_vaultAddress);
        glpPriceUtils = IGlpPriceUtils(_glpPriceUtilsAddress);
    }

    modifier checkAllowance(uint amount) {
        require(usdcToken.allowance(msg.sender, address(this)) >= amount, "Allowance Error");
        _;
    }

    function Purchase(uint256 usdcAmount) external returns (Purchase memory) {
        uint256 price = glpPriceUtils.glpPrice();
        uint256 glpToPurchase = usdcAmount * price / USDC_DIVISOR;
        
        usdcToken.transferFrom(msg.sender, address(this), usdcAmount);

        uint256 glpAmountAfterSlippage = glpToPurchase * (BASIS_POINTS_DIVISOR - DEFAULT_SLIPPAGE) / BASIS_POINTS_DIVISOR;
        usdcToken.approve(address(rewardRouter), 1000000000000000000);
        uint256 glpAmount = rewardRouter.mintAndStakeGlp(usdcAddress, usdcAmount, 0, glpAmountAfterSlippage);

        return Purchase({
            usdcAmount: usdcAmount,
            tokenAmount: glpAmount
        });
    }
}

