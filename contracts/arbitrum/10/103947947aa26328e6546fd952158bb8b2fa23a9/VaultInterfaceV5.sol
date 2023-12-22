// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface VaultInterfaceV5{
	function sendDaiToTrader(address, uint) external;
	function receiveDaiFromTrader(address, uint, uint) external;
	function currentBalanceDai() external view returns(uint);
	function distributeRewardDai(uint) external;
	function distributeReward(uint assets) external;
	function sendAssets(uint assets, address receiver) external;
	function receiveAssets(uint assets, address user) external;
}
