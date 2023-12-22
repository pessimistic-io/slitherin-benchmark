// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

interface IProtocolRevenue {
	event RewardsChanged(address indexed _token, uint256 _newValue);

	/**
    @notice VeHolders can call this function to reclaim their share of revenue
    @param _token the token they want to claim
     */
	function claimRewards(address _token) external;

	/**
    @notice Change vesta's treasury address
    @dev Only Owner can call this
    @param _newTreasury new treasury address
     */
	function setTreasury(address _newTreasury) external;

	/**
    @notice withdraw token from the contract
    @dev Only Owner can call this
    @param _token the token address
    @param _amount the amount to withdraw
     */
	function withdraw(address _token, uint256 _amount) external;

	/**
    @notice Pause the contract, all new revenue will automatically go to the treasury.
    @dev This option is just for the time we deploy veVsta
    @dev Only Owner can call this
    @param _pause pause status
     */
	function setPause(bool _pause) external;

	/**
    @notice Get total rewards by token inside the contract
    @param _token The address of the token
     */
	function getRewardBalance(address _token) external view returns (uint256);

	/**
    @notice Get total reward sent to the treasury
    @param _token The address of the token
     */
	function getRewardBalanceSentToTreasury(address _token)
		external
		view
		returns (uint256);
}

