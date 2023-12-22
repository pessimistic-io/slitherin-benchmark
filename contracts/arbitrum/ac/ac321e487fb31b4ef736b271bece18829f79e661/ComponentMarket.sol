// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./AccessControl.sol";
import "./BehaviorTaxedTradingToken.sol";
import "./BehaviorUniswapableV2Token.sol";
import "./BehaviorSafetyMethods.sol";
import "./ComponentTreasuryErc20.sol";
import "./console.sol";

contract ComponentMarket is Ownable, BehaviorUniswapableV2, BehaviorSafetyMethods {
    address public addressTreasuryRewards;
    uint256 public percentReferralRewardBuyer;
    uint256 public percentReferralRewardReferrer;
    uint256 public minimalHoldingForReferralBonus;
    uint256 public minimumAmountForLpCreation;
    bool isTreasuryReferralRewardsValid;
    ComponentTreasuryErc20 treasuryReferralRewards;

    constructor(
        address _addressRouter,
        address _addressManagedToken
    ) BehaviorUniswapableV2(_addressRouter, _addressManagedToken) {}

    function configureRewardTreasury(address _treasury) public onlyOwner {
        isTreasuryReferralRewardsValid = true;
        treasuryReferralRewards = ComponentTreasuryErc20(_treasury);
    }

    function setMinimumAmountForLpCreation(uint256 _minAmount) public onlyOwner {
        minimumAmountForLpCreation = _minAmount;
    }

    function setMinimalHoldingForReferralBonus(uint256 _minHolding) public onlyOwner {
        minimalHoldingForReferralBonus = _minHolding;
    }

    function setRewardPercent(uint256 _percentBuyer, uint256 _percentReferrer) public onlyOwner {
        percentReferralRewardBuyer = _percentBuyer;
        percentReferralRewardReferrer = _percentReferrer;
    }

    function swapEthForTokensWithReferral(uint256 _minAmountOut, address _to, address _referrer) public payable {
        uint256 purchasedTokens = _swapEthForTokens(_minAmountOut, _to);

        if (_referrer != address(0)) {
            uint256 balanceHolder = ERC20(addressManagedToken).balanceOf(_referrer);
            require(minimalHoldingForReferralBonus <= balanceHolder, "Referrer doesn't hold enough tokens");

            uint256 rewardBuyer = (purchasedTokens * percentReferralRewardBuyer) / 100;
            uint256 rewardReferrer = (purchasedTokens * percentReferralRewardReferrer) / 100;

            if (rewardBuyer > 0) _onRewardsForBuyer(_to, rewardBuyer);
            if (rewardReferrer > 0) _onRewardsForReferrer(_referrer, rewardReferrer);
        }
    }

    function _onRewardsForBuyer(address _buyer, uint256 _amount) internal virtual {
        require(isTreasuryReferralRewardsValid, "Treasury for referral rewards not configured");

        treasuryReferralRewards.transferTo(_buyer, _amount);
    }

    function _onRewardsForReferrer(address _referrer, uint256 _amount) internal virtual {
        require(isTreasuryReferralRewardsValid, "Treasury for referral rewards not configured");

        treasuryReferralRewards.transferTo(_referrer, _amount);
    }

    function createLiquidityTokenAndEth(uint256 _amountTokens) public payable onlyOwner {
        uint256 amountETH = msg.value;
        ERC20(addressManagedToken).transferFrom(msg.sender, address(this), _amountTokens);
        _addTokensToLiquidityETH(_amountTokens, amountETH);
    }

    function swapLiquidityTreasuryToLP(address _treasuryForLiquidity) public {
        ComponentTreasuryErc20 treasury = ComponentTreasuryErc20(_treasuryForLiquidity);
        uint256 balanceTreasury = treasury.treasuryBalance();
        if (balanceTreasury >= minimumAmountForLpCreation) {
            treasury.transferTo(address(this), balanceTreasury);

            _swapTokensToHalfAndCreateLpETH(balanceTreasury);
        }
    }
}

