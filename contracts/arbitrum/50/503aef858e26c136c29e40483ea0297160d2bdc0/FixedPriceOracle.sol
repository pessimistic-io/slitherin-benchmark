// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./SafeOwnable.sol";

contract FixedPriceOracle is SafeOwnable {
  uint256 private _fixedPrice;

  event FixedPriceChange(uint256 price);

  function setFixedPrice(uint256 _newFixedPrice) external onlyOwner {
    _fixedPrice = _newFixedPrice;
    emit FixedPriceChange(_newFixedPrice);
  }

  function getFixedPrice() external view returns (uint256) {
    return _fixedPrice;
  }
}

