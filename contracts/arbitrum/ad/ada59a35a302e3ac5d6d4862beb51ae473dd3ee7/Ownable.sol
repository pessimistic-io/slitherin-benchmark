// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

contract Ownable {
  address payable public owner;

  constructor(address initialOwner) {
    owner = payable(initialOwner);
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  event LogNewOwner(address sender, address newOwner);

  function setOwner(address payable newOwner) external onlyOwner {
    require(newOwner != address(0));
    owner = newOwner;
    emit LogNewOwner(msg.sender, newOwner);
  }
}

