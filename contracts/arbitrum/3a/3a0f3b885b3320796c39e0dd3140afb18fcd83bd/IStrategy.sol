// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategy {
    function registerStake(uint amount) external;
    function unregisterStake(uint amount) external;
    function getTotalStaked() external view returns (uint total);
    function initialize(address _vault) external;
    function reinvest() external;
}
