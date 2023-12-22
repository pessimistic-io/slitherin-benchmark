// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

interface ISavvyUserBalance {
    /// @notice User’s SVY amount in wallet.
    /// @param user_ The address of a user.
    /// @return Amount of user's SVY balance.
    function getUserSVYBalance(address user_) external view returns (uint256);

    /// @notice User’s SVY amount staked in veSVY contract.
    /// @param user_ The address of a user.
    /// @return Amount of user staked in veSVY.
    function getUserStakedSVYAmount(
        address user_
    ) external view returns (uint256);

    /// @notice User’s veSVY amount in wallet.
    /// @param user_ The address of a user.
    /// @return Amount of user's veSVY balance.
    function getUserVeSVYBalance(address user_) external view returns (uint256);

    /// @notice User’s claimable veSVY amount in the veSVY contract.
    /// @param user_ The address of a user.
    /// @return Amount of user's claimable veSVY.
    function getUserClaimableVeSVYAmount(
        address user_
    ) external view returns (uint256);

    /// @notice User’s claimable SVY amount in the SavvyBooster contract.
    /// @param user_ The address of a user.
    /// @return Amount of user's claimable SVY.
    function getUserClaimableSVYAmount(
        address user_
    ) external view returns (uint256);

    /// @notice SVY USD price.
    /// @dev This function returns token price calculated by 1e18.
    /// @return SVY USD price.
    function getSVYPrice() external view returns (uint256);

    /// @notice User’s SVY earn rate in USD / user’s total deposit in USD
    /// @param user_ The address of a user.
    /// @return Amount of svy earn rate.
    function getSVYEarnRate(address user_) external view returns (uint256);

    /// @notice User’s SVY earn rate in USD / user’s total deposit.
    /// @param user_ The address of a user.
    /// @return User’s SVY earn rate in USD / user’s total deposit.
    function getSVYAPY(address user_) external view returns (uint256);
}

