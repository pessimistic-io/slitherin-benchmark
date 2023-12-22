// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import "./IMiniSalesFlag.sol";
import "./SafeOwnable.sol";

contract MiniSalesFlag is IMiniSalesFlag, SafeOwnable {
  bool private _saleStarted;

  function setSaleStarted(bool _newSaleStarted) external override onlyOwner {
    _saleStarted = _newSaleStarted;
  }

  function hasSaleStarted() external view override returns (bool) {
    return _saleStarted;
  }
}

