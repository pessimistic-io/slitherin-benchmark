// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/**
 * @dev Interface of the VeDxp
 */
interface ITokenFarm {
    function getTierVela(address _account) external view returns (uint256);
    function pendingTokens(bool _isVelaPool, address _user) external view returns (
        address[] memory,
        string[] memory,
        uint256[] memory,
        uint256[] memory
    );
}

