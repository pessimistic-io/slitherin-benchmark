// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./TokenTimelock.sol";

contract SimpleTokenTimelock is TokenTimelock {
    constructor(IERC20 token, address beneficiary, uint256 releaseTime)
       public
       TokenTimelock(token, beneficiary, releaseTime)
    {}
}
