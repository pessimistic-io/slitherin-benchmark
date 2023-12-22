// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.0 <=0.8.19;

interface IMauser {
    function getAdmin() external view returns (address admin);
    function getImplementation() external view returns (address implementation);
    function checkBalance(uint256 min, uint256 max, address addr) external view;
    function checkBalance(uint256 min, uint256 max, address addr, address token) external view;
}

