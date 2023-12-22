// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMathUpgradeable.sol";
import "./ExtendedMathLib.sol";

/// @title  RewardLib
/// @notice Library for calculating the reward

library RewardLibV2 {

	using SafeMathUpgradeable for uint256;

	/// @notice Calculate reward for channel capacity
	/// @param  capacity channel capacity
	/// @param  marketplace if reward from marketplace
	/// @param  penaltyValue minimum channel capacity for which a reward is given
	/// @param  makersFixedRewardAmount maker's fixed reward
	/// @param  makersRewardPercentage maker's percentage reward
	/// @param  capacityFixedRewardAmount capacity fixed reward
	/// @param  capacityRewardPercentage capacity percentage reward
	/// @param  treasuryBalance balance of the PlennyTreasury
	/// @return multiplier reward multiplier
	function calculateReward(
		uint256 capacity,
		bool marketplace,
		uint256 penaltyValue,
        uint256 maxChannelCapacity,
		uint256 makersFixedRewardAmount,
		uint256 makersRewardPercentage,
		uint256 capacityFixedRewardAmount,
		uint256 capacityRewardPercentage,
		uint256 treasuryBalance
	) internal pure returns (uint multiplier){
		uint256 rewardAmount;

		if (marketplace) {
			if (makersFixedRewardAmount < makersRewardPercentage.mul(treasuryBalance).div(100).div(100000)) {
				rewardAmount = makersFixedRewardAmount;
			} else {
				rewardAmount = makersRewardPercentage.mul(treasuryBalance).div(100).div(100000);
			}
		} else {
			if (capacityFixedRewardAmount < capacityRewardPercentage.mul(treasuryBalance).div(100).div(100000)) {
				rewardAmount = capacityFixedRewardAmount;
			} else {
				rewardAmount = capacityRewardPercentage.mul(treasuryBalance).div(100).div(100000);
			}
		}
		if (capacity >= penaltyValue) {

			uint256 cS = capacity.sub(penaltyValue);
			uint256 cMax = maxChannelCapacity.sub(penaltyValue);
			uint256 sqrtCS = ExtendedMathLib.sqrt(cS);
			uint256 sqrtCMax = ExtendedMathLib.sqrt(cMax);

			return rewardAmount.mul(cS).mul(sqrtCS).div(cMax).div(sqrtCMax);
		} else {
			return 0;
		}
	}
}
