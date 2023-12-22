// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IKitchen.sol";

abstract contract KitchenManager {

  IKitchen public kitchen;

  constructor (address _kitchen) {
    _setKitchen(_kitchen);
  }

  function _setKitchen (address _kitchen) internal {
    kitchen = IKitchen(_kitchen);
  }

}
