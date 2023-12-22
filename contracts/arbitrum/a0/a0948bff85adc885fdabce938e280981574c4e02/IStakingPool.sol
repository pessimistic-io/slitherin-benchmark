// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

/// @title An interface of the {StakingPool} contract
interface IStakingPool {
    /// @notice Indicates that `user` deposited `amount` of tokens into the pool
    event Deposit(address indexed user, uint256 amount);
    /// @notice Indicates that `user` withdrawn `amount` of tokens from the pool
    event Withdraw(address indexed user, uint256 amount);
    /// @notice Indicates that `user` withdraw `amount` of tokens from the pool
    ///      without claiming reward
    event EmergencyWithdraw(address indexed user, uint256 amount);
    /// @notice Indicates that `user` claimed his pending reward
    event Claim(address indexed user, uint256 amount);
    /// @notice Indicates that new address of `Tipping` contract was set
    event TippingAddressChanged(address indexed tipping);

    /// @notice Allows to see the pending reward of the user
    /// @param user The user to check the pending reward of
    /// @return The pending reward of the user
    function getAvailableReward(address user) external view returns (uint256);

    /// @notice Allows to see the current stake of the user
    /// @param user The user to check the current lock of
    /// @return The current lock of the user
    function getStake(address user) external view returns (uint256);

    /// @notice Allows to see the current amount of users who staked tokens in the pool
    /// @return The amount of users who staked tokens in the pool
    function getStakersCount() external view returns (uint256);

    /// @notice Allows users to lock their tokens inside the pool
    ///         or increase the current locked amount. All pending rewards
    ///         are claimed when making a new deposit
    /// @param amount The amount of tokens to lock inside the pool
    /// @dev Emits a {Deposit} event
    function deposit(uint256 amount) external;

    /// @notice Allows users to withdraw their locked tokens from the pool
    ///         All pending rewards are claimed when withdrawing
    /// @dev Emits a {Withdraw} event
    function withdraw(uint256 amount) external;

    /// @notice Allows users to withdraw their locked tokens from the pool
    ///         without claiming any rewards
    /// @dev Emits an {EmergencyWithdraw} event
    function emergencyWithdraw() external;

    /// @notice Allows users to claim all of their pending rewards
    /// @dev Emits a {Claim} event
    function claim() external;

    /// @notice Sets the address of the {Tipping} contract to call its methods
    /// @notice param tipping_ The address of the {Tipping} contract
    function setTipping(address tipping_) external;

    /// @notice Gives a signal that some tokens have been received from the
    ///         {Tipping} contract. That leads to each user's reward share
    ///         recalculation.
    /// @dev Each time someone transfers tokens using the {Tipping} contract,
    ///      a small portion of these tokens gets sent to the staking pool to be
    ///      paid as rewards
    /// @dev This function does not transfer any tokens itself
    function supplyReward(uint256 reward) external;
}

