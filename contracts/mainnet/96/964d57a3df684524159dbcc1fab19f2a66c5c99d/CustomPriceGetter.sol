// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {IPriceGetter} from "./IPriceGetter.sol";

contract CustomPriceGetter is IPriceGetter {

  uint256 private _price;
  address public owner;

  constructor(uint256 price) {
    _price = price;
    owner = msg.sender;
  }

  function getPrice() external view override returns (uint256 price) {
    return _price;
  }

  function setPrice(uint256 newPrice) external onlyOwner {
    _price = newPrice;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "Only owner can call this function.");
    _;
  }
}
