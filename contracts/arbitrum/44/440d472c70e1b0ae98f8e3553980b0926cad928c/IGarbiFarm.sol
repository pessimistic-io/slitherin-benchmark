// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "./IERC20.sol";

contract IGarbiFarm {

   uint256 public totalShare;

   IERC20 public want;

   mapping(address => uint256) public shareOf; 
}
