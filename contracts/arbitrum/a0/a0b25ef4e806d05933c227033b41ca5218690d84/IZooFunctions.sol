pragma solidity 0.8.17;

// SPDX-License-Identifier: MIT

/// @title interface of Zoo functions contract.
interface IZooFunctions {

	/// @notice returns random number.
	function randomResult() external view returns(uint256 random);

	/// @notice returns league of nft.
	function getNftLeague(uint256 votes) external view returns(uint8);

	/// @notice returns league rewards.
	function getLeagueZooRewards(uint8 league) external returns(uint256);

	/// @notice returns arena fee.
	function getArenaFee() external returns(uint256);

	/// @notice sets random number in battles back to zero.
	function resetRandom() external;

	function randomFulfilled() external view returns(bool);

	/// @notice Function for choosing winner in battle.
	function decideWins(uint256 votesForA, uint256 votesForB, uint256 random) external view returns (bool);

	/// @notice Function for generating random number.
	function requestRandomNumber() external;

	/// @notice Function for getting random number.
	function getRandomResult() external returns(uint256);

	/// @notice Function for getting random number for selected epoch (historical).
	function getRandomResultByEpoch(uint256 epoch) external returns(uint256);

	function computePseudoRandom() external view returns (uint256);

	/// @notice Function for calculating voting with Dai in vote battles.
	function computeVotesByDai(uint256 amount) external view returns (uint256);

	/// @notice Function for calculating voting with Zoo in vote battles.
	function computeVotesByZoo(uint256 amount) external view returns (uint256);

	function firstStageDuration() external view returns (uint256);

	function secondStageDuration() external view returns (uint256);

	function thirdStageDuration() external view returns (uint256);

	function fourthStageDuration() external view returns (uint256);

	function fifthStageDuration() external view returns (uint256);

	function getStageDurations() external view returns (uint256, uint256, uint256, uint256, uint256, uint256 epochDuration);
}

