// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./Math.sol";

import "./IGlpManager.sol";

/// @custom:security-contact security@munchies.money
contract GlpPriceFeed {
  address public immutable glpManager;

  constructor(address glpManager_) {
    glpManager = glpManager_;
  }

  function getPrice(bool _maximise) public view returns (uint256 price) {
    price = _getPrice(_maximise);
  }

  function _getPrice(bool _maximise) internal view returns (uint256 price) {
    price = IGlpManager(glpManager).getPrice(_maximise);
  }

  function convertToUSD(uint256 amount) public view returns (uint256) {
    uint256 decimals = 18;
    uint256 price = _getPrice(true);

    return Math.mulDiv(amount, price, 1 * 10 ** decimals); // F:[PO-7]
  }

  function getMinPrice(uint256 amount) public pure returns (uint256) {
    uint256 basisPointsDivisor = 10000;
    uint256 defaultSlippageAmount = 30;

    return
      Math.mulDiv(
        amount,
        basisPointsDivisor - defaultSlippageAmount,
        basisPointsDivisor
      );
  }
}

