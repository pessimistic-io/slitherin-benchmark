// SPDX-License-Identifier: AGPL-3.0


pragma solidity ^0.8.0;

import "./IMintValidator.sol";
import "./IFabricator.sol";

// A validator that always prints 1 collectible of given ID
// For Testing only
contract BasicValidator is IMintValidator {
  uint256 private _id;
  IFabricator public watcher;

  constructor(uint256 id_, IFabricator _watcher) {
    _id = id_;
    watcher = _watcher;
  }

  function validate(
    address recipient,
    uint256, /* _dropId*/
    uint256[] memory quantities, /* _qty*/
    string calldata, /* _metadata*/
    bytes memory /* _data*/
  ) external override {
    uint256[] memory idReturn = new uint256[](1);
    uint256[] memory quantityReturn = new uint256[](1);
    idReturn[0] = _id;
    quantityReturn[0] = quantities[0];
    watcher.modularMintCallback(recipient, idReturn, quantityReturn, "");
  }
}

