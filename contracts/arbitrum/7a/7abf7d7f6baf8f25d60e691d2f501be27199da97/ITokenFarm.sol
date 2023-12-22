// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/**
 * @dev Interface of the VeDxp
 */
interface ITokenFarm {
    function claimable(address _account) external view returns (uint256);
    function cooldownDuration() external view returns (uint256);
    function getTierVela(address _account) external view returns (uint256);
    function guessTierVela(address _account,  bool _isPlus, uint256 _amount) external view returns (uint256);
    function getStakedVela(address _account) external view returns (uint256, uint256);
    function getStakedVLP(address _account) external view returns (uint256, uint256);
    function getTotalVested(address _account) external view returns (uint256);
    function pendingTokens(bool _isVelaPool, address _user) external view returns (
        address[] memory,
        string[] memory,
        uint256[] memory,
        uint256[] memory
    );
}

