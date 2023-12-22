// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./VariableRewardsStrategyForSAV2.sol";

import "./ISingleStaking.sol";

contract CompoundingBets is VariableRewardsStrategyForSAV2 {
    ISingleStaking public stakingContract;

    constructor(
        address _stakingContract,
        address _swapPairDepositToken,
        uint256 _swapFeeBips,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForSAV2(_swapPairDepositToken, _swapFeeBips, _settings, _strategySettings) {
        stakingContract = ISingleStaking(_stakingContract);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.stake(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        stakingContract.withdraw(_amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        stakingContract.withdraw(totalDeposits());
        depositToken.approve(address(stakingContract), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](rewardCount);
        for (uint256 i = 0; i < pendingRewards.length; i++) {
            address rewardToken = supportedRewards[i];
            uint256 amount = stakingContract.earned(address(this), rewardToken);
            pendingRewards[i] = Reward({reward: rewardToken, amount: amount});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        stakingContract.getReward();
    }

    function totalDeposits() public view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }
}

