// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {L2Pool} from "./pool_L2Pool.sol";

contract MockL2Pool is L2Pool {
  function getRevision() internal pure override returns (uint256) {
    return 0x3;
  }

  constructor(IPoolAddressesProvider provider) L2Pool(provider) {}
}

