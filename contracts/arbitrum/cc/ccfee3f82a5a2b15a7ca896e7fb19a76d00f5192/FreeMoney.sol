// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

contract FreeMoney {
  constructor() payable {}

  receive() external payable {}

  function collect() external {
    payable(msg.sender).transfer(
      address(this).balance
    );
  }
}