// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.6.12;

import {   IERC20 } from "./IERC20.sol";
import {ISynthereumPool} from "./IPool.sol";
import {ISynthereumFinder} from "./IFinder.sol";
import {   EnumerableSet } from "./EnumerableSet.sol";
import {   FixedPoint } from "./FixedPoint.sol";

interface ISynthereumPoolStorage {
  struct Storage {
    ISynthereumFinder finder;
    uint8 version;
    IERC20 collateralToken;
    IERC20 syntheticToken;
    bool isContractAllowed;
    EnumerableSet.AddressSet derivatives;
    FixedPoint.Unsigned startingCollateralization;
    ISynthereumPool.Fee fee;
    uint256 totalFeeProportions;
    mapping(address => uint256) nonces;
  }
}

