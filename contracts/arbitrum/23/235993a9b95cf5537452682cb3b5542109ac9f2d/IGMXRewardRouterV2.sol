// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IGMXRewardRouterV2 {
	function stakedGmxTracker() external view returns (address);

	function stakeGmx(uint256 _amount) external;

	function stakeEsGmx(uint256 _amount) external;

	function unstakeGmx(uint256 _amount) external;

	function unstakeEsGmx(uint256 _amount) external;

	function mintAndStakeGlp(
		address _token,
		uint256 _amount,
		uint256 _minUsdg,
		uint256 _minGlp
	) external;

	function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp)
		external
		payable
		returns (uint256);

	function unstakeAndRedeemGlp(
		address _tokenOut,
		uint256 _glpAmount,
		uint256 _minOut,
		address _receiver
	) external returns (uint256);

	function unstakeAndRedeemGlpETH(
		uint256 _glpAmount,
		uint256 _minOut,
		address payable _receiver
	) external returns (uint256);

	function claim() external;

	function claimEsGmx() external;

	function claimFees() external;

	function compound() external;

	function handleRewards(
		bool _shouldClaimGmx,
		bool _shouldStakeGmx,
		bool _shouldClaimEsGmx,
		bool _shouldStakeEsGmx,
		bool _shouldStakeMultiplierPoints,
		bool _shouldClaimWeth,
		bool _shouldConvertWethToEth
	) external;

	function signalTransfer(address _receiver) external;

	function acceptTransfer(address _sender) external;
}

