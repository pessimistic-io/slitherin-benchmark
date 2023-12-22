// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IOreoStake {
    function deposit(address _for, address stakeToken , uint256 amount) external;

    function withdraw(address _for, address stakeToken , uint256 amount) external;

    function emergencyWithdraw(address _for, address stakeToken) external;

    function harvest(address _for, address stakeToken) external;
    
    function userInfo(address stakeToken, address _user) external view returns (uint256, uint256, address);
}
