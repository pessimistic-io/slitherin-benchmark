// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./IERC20.sol";

abstract contract IWETH is IERC20 {
    function deposit() external virtual payable;
    function withdraw(uint256 amount) virtual external;
}


