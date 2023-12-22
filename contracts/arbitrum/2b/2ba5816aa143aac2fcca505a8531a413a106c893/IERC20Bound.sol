// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IERC20Bound {
  function unbind(address _addresses) external;

  function isUnbound(address _addr) external view returns (bool);
}

