
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICapacityPackage {
    function addCapacity(address[] memory _accounts, uint256[] memory _capacity) external;
    function addCapacity(address _account, uint256 _capacity) external;
    function subCapacity(address _account, uint256 _capacity) external;
    function userCapacityPacakage(address _account) external view returns(uint256);   
}
