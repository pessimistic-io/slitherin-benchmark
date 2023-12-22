// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./Ownable.sol";
import "./CourseCompletedNFT.sol";

contract MirthisContract is OtherContract {
  uint256 public s_variable = 0;
  uint256 public s_otherVar = 0;
  address private immutable i_owner;
  event NothingDone();

  constructor() {
    i_owner = msg.sender;
  }

  function doSomething() public {
    s_variable = 123;
    s_otherVar = 1;
  }

  function doNothing() public {
    emit NothingDone();
  }

  function getOwner() external override returns (address) {
    return i_owner;
  }
}

