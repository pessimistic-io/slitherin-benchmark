// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITokenLocation.sol";

abstract contract LocationManager {

  ITokenLocation public location;

  constructor (address _tokenLocation) {
    _setTokenLocation(_tokenLocation);
  }

  function _setTokenLocation (address _tokenLocation) internal {
    location = ITokenLocation(_tokenLocation);
  }

}
