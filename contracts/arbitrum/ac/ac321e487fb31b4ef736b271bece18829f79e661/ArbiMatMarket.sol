// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ComponentMarket.sol";
import "./libraryMathEx.sol";
import "./ArbiMatVestingReferralRewards.sol";
import "./console.sol";

contract ArbiMatMarket is ComponentMarket {
    ArbiMatVestingReferralRewards vestingRewards;
    bool isVestingRewardsConfigured;

    constructor(
        address _addressRouter,
        address _addressManagedToken
    ) ComponentMarket(_addressRouter, _addressManagedToken) {
        percentReferralRewardBuyer = 1;
        percentReferralRewardReferrer = 1;
        minimalHoldingForReferralBonus = 2_500 * 10 ** 18;
        minimumAmountForLpCreation = 100 * 10 ** 18;
    }

    function configureVestingRewardsContract(address _vestingContract) public onlyOwner {
        ERC20(addressManagedToken).approve(_vestingContract, MathEx.MAX_INT);
        vestingRewards = ArbiMatVestingReferralRewards(_vestingContract);
        isVestingRewardsConfigured = true;
    }

    function _onRewardsForBuyer(address _buyer, uint256 _amount) internal virtual override {
        require(isTreasuryReferralRewardsValid, "Treasury for referral rewards not configured");
        _amount = MathEx.multiplyWithFloat(_amount, 95, 100);

        treasuryReferralRewards.transferTo(_buyer, _amount);
    }

    function _onRewardsForReferrer(address _referrer, uint256 _amount) internal virtual override {
        require(isTreasuryReferralRewardsValid, "Treasury for referral rewards not configured");
        require(isVestingRewardsConfigured, "Treasury for referral rewards not configured");

        _amount = MathEx.multiplyWithFloat(_amount, 95, 100);

        treasuryReferralRewards.transferTo(address(this), _amount);
        vestingRewards.depositTokensFrom(address(this), _referrer, _amount);
    }
}

