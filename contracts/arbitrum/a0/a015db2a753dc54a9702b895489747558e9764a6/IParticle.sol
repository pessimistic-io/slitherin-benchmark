// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC20.sol";

interface IParticle is IERC20 {
  function mintFor(address _for, uint256 _amount) external;
}

