// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.9;

import {ISynthereumFinder} from "./IFinder.sol";
import {SynthereumFactoryAccess} from "./FactoryAccess.sol";

/**
 * @title Abstract contract inherited by pools for moving storage from one pool to another
 */
contract SynthereumPoolMigration {
  ISynthereumFinder internal finder;

  modifier onlyPoolFactory() {
    SynthereumFactoryAccess._onlyPoolFactory(finder);
    _;
  }
}

