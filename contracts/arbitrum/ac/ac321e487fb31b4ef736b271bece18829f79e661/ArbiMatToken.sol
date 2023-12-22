// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./BehaviorTaxedTradingToken.sol";
import "./BehaviorUniswapableV2Token.sol";
import "./BehaviorSafetyLimitsToken.sol";
import "./BehaviorSafetyMethods.sol";
import "./ArbiMatMarket.sol";
import "./console.sol";

contract ArbiMatToken is
    ERC20,
    BehaviorTaxedTradingToken,
    BehaviorUniswapableV2Token,
    BehaviorSafetyLimitsToken,
    BehaviorSafetyMethods
{
    bool private internalSwapping = false;
    uint256 public taxAirdropsPercent;
    uint256 public taxLiquidityPercent;
    uint256 public taxDevRewardPercent;
    address public treasuryAirdrops;
    address public treasuryDevRewards;
    address public treasuryLiquidity;
    ArbiMatMarket componentMarket;

    constructor(address _addressRouter) ERC20("ArbiMat", "AMAT") BehaviorUniswapableV2Token(_addressRouter) {
        _mint(msg.sender, 1_150_000 * 10 ** 18);
        maxTransactionSize = 10_000 * 10 ** 18;
        maxWalletSize = 40_000 * 10 ** 18;
        buyTaxPercent = 5;
        sellTaxPercent = 5;
        taxAirdropsPercent = 2;
        taxLiquidityPercent = 1;
        taxDevRewardPercent = 2;
    }

    function configureTaxUsage(
        uint256 _percentAirdrops,
        uint256 _percentLiquidity,
        uint256 _percentDevReward
    ) public onlyOwner {
        taxAirdropsPercent = _percentAirdrops;
        taxLiquidityPercent = _percentLiquidity;
        taxDevRewardPercent = _percentDevReward;
    }

    function configureTreasuries(
        address _treasuryLiquidity,
        address _treasuryAirdrops,
        address _treasuryDevRewards
    ) public onlyOwner {
        treasuryAirdrops = _treasuryAirdrops;
        treasuryDevRewards = _treasuryDevRewards;
        treasuryLiquidity = _treasuryLiquidity;
    }

    function configureMarket(address _addressMarket) public onlyOwner {
        setTaxingExcludedWalletAddress(_addressMarket, true);
        setSafetyLimitsExcludedWalletAddress(_addressMarket, true);
        componentMarket = ArbiMatMarket(payable(_addressMarket));
    }

    function disableAllBehaviors() public onlyOwner {
        enableDisableSafetyLimits(false);
        enableDisableTransactionTaxing(false);
    }

    function _transfer(address _from, address _to, uint256 _amount) internal virtual override {
        if (internalSwapping == false) {
            _transferCheckLimits(_from, _to, _amount);

            (uint256 amount, uint256 tax, bool isPurchase, , bool isExcluded) = _taxableTransfer(_from, _to, _amount);
            if (tax > 0) _internalTransfer(_from, address(this), tax);
            if (isExcluded == false) _internalHandleTaxes(isPurchase);
            _amount = amount;
        }

        _internalTransfer(_from, _to, _amount);
    }

    function _internalHandleTaxes(bool isPurchase) internal {
        uint256 balanceToken = IERC20(address(this)).balanceOf(address(this));

        if (balanceToken > 0.1 * 10 ** 18) {
            uint256 completePortionPct = taxAirdropsPercent + taxLiquidityPercent + taxDevRewardPercent;
            uint256 portionAirdrops = (balanceToken * taxAirdropsPercent) / completePortionPct;
            uint256 portionLiquidity = (balanceToken * taxLiquidityPercent) / completePortionPct;
            uint256 portionDevReward = (balanceToken * taxDevRewardPercent) / completePortionPct;

            require(portionAirdrops + portionLiquidity + portionDevReward <= balanceToken, "Calculation mishmash");

            internalSwapping = true;
            if (portionLiquidity > 0 && treasuryLiquidity != address(0)) {
                _internalTransfer(address(this), treasuryLiquidity, portionLiquidity);
                if (isPurchase == false) componentMarket.swapLiquidityTreasuryToLP(treasuryLiquidity);
            }
            if (portionAirdrops > 0 && treasuryAirdrops != address(0)) {
                _internalTransfer(address(this), treasuryAirdrops, portionAirdrops);
            }
            if (portionDevReward > 0 && treasuryDevRewards != address(0)) {
                _internalTransfer(address(this), treasuryDevRewards, portionDevReward);
            }
            internalSwapping = false;
        }
    }

    function _internalTransfer(address from, address to, uint256 amount) internal {
        super._transfer(from, to, amount);
    }
}

