// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

import "./ERC20_IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function balanceOf(address account) external view returns (uint256);
}
