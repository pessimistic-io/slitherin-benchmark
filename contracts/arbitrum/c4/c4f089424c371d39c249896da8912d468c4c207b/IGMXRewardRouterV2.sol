// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IGMXRewardRouterV2 {
	function stakeGmx(uint256 _amount) external;

	function unstakeGmx(uint256 _amount) external;

	function handleRewards(
		bool _shouldClaimGmx,
		bool _shouldStakeGmx,
		bool _shouldClaimEsGmx,
		bool _shouldStakeEsGmx,
		bool _shouldStakeMultiplierPoints,
		bool _shouldClaimWeth,
		bool _shouldConvertWethToEth
	) external;
}

