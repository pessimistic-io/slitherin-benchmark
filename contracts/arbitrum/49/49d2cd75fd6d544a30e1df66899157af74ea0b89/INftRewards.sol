// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

interface INftRewards {
    function getUserTier(address _user)  external view returns (uint256);
    function addPoints(address _addr, uint256 _amount) external;
    function removePoints(address _addr, uint256 _amount) external;
}
