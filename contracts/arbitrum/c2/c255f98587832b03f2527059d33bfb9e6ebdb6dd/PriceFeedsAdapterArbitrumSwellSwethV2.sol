// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.4;

import "./PriceFeedsAdapterArbitrumSwellSweth.sol";

contract PriceFeedsAdapterArbitrumSwellSwethV2 is PriceFeedsAdapterArbitrumSwellSweth {
  function requireAuthorisedUpdater(address updater) public view override virtual {
    if (updater != 0x28a5314F19E59e688Cb782dd7eBc4DCA6e1376cB && updater != 0xc4D1AE5E796E6d7561cdc8335F85e6B57a36e097) {
      revert UpdaterNotAuthorised(updater);
    }
  }
}

