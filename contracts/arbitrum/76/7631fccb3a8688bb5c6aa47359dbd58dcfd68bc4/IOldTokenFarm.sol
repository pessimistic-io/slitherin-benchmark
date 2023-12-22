// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

/**
 * @dev Interface of the OldTokenFarm
 */
interface IOldTokenFarm {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 startTimestamp;
    }
    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory amounts
        );
    function userInfo(uint256 _pid, address _account) external view returns (UserInfo memory);
}

