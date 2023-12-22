// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * @dev Interface of the SettingManager
 */
interface ISettingManager {
    function cooldownDuration() external view returns (uint256);
    function isWhitelistedFromCooldown(address _user) external view returns (bool);
}

