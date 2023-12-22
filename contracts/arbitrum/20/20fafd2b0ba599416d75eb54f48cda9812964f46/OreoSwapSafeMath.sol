// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.6.12;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library OreoSwapSafeMath {
  function add(uint x, uint y) internal pure returns (uint z) {
    require((z = x + y) >= x, 'OreoSwapSafeMath::add::ds-math-add-overflow');
  }

  function sub(uint x, uint y) internal pure returns (uint z) {
    require((z = x - y) <= x, 'OreoSwapSafeMath::sub::ds-math-sub-underflow');
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x, 'OreoSwapSafeMath::mul::ds-math-mul-overflow');
  }
}
