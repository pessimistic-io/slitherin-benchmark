// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import "./ERC165.sol";
import "./Multicall.sol";
import "./ITokenPriceOracle.sol";

/// @title A base implementation of `ITokenPriceOracle` that implements `ERC165` and `Multicall`
abstract contract BaseOracle is Multicall, ERC165, ITokenPriceOracle {
  /// @inheritdoc IERC165
  function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
    return
      _interfaceId == type(ITokenPriceOracle).interfaceId ||
      _interfaceId == type(Multicall).interfaceId ||
      super.supportsInterface(_interfaceId);
  }
}

