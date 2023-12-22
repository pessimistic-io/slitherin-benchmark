// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IItems.sol";

abstract contract ItemManager {

  IItems public items;

  constructor (address _items) {
    _setItems(_items);
  }

  function _setItems (address _items) internal {
    items = IItems(_items);
  }

}
