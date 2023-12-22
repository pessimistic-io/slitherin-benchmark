// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

interface IBaseStrategy {
    function vault() external view returns (address);
    function want() external view returns (IERC20);
    function beforeDeposit() external;
    function inputToken() external view returns (address);
    function withdraw(uint256) external;
    function balanceOf() external view returns (uint256);
    function balanceOfWant() external view returns (uint256);
    function balanceOfPool() external view returns (uint256);
    function harvest() external;
    function panic() external;
}


