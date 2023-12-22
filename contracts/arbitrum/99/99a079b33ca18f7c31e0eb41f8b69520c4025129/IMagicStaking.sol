// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMagicStaking {
    function totalMagicStaked() external view returns(uint256);
    function deposit(address _user, uint128 _amount) external;
    function withdraw(address _user) external;
    function stakeAmount(address _user) external view returns(uint128);
}
