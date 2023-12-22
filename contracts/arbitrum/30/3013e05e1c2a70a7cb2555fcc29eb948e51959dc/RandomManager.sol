// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRandomizer.sol";

abstract contract RandomManager {

  IRandomizer public randomizer;

  constructor (address _randomizer) {
    _setRandomizer(_randomizer);
  }

  function _setRandomizer (address _randomizer) internal {
    randomizer = IRandomizer(_randomizer);
  }

}
