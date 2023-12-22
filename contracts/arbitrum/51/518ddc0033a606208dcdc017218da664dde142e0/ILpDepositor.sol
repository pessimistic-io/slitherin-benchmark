// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ILpDepositor {
    function tokenID() external view returns (uint256);
    function setTokenID(uint256 tokenID) external returns (bool);
    function totalBalances(address pool) external view returns (uint256);
    function getReward(address pool, address token) external;
    function claimRewards(address pool, address token) external;
    function pendingRewards(address pool, address reward) external view returns (uint);
 
}
