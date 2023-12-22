// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IORBToken is IERC20 {
    function burn(address to, uint256 amount) external;
}

