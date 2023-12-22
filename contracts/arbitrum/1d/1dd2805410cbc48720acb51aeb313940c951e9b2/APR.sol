// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Math.sol";

library APR {

  function dailyApr(uint256 _apr) internal pure returns(uint256) {
    return Math.mulDiv(_apr, 1 days, 1 days * 365);
  }

}
