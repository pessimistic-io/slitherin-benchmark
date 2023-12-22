pragma solidity 0.8.17;

// SPDX-License-Identifier: MIT

interface IGlpRewardRouter
{
	function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);

	function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);

	// function transfer(address who, uint256 amount) external returns (bool);

	// function increaseMockBalance() external;

	// function balanceOf(address who) external view returns (uint256);
}

