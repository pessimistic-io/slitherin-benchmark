// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import "./EnumerableSetUpgradeable.sol";
import "./EnumerableMapUpgradeable.sol";
import "./Initializable.sol";

import "./IGmxV2Adatper.sol";

abstract contract Storage is IGmxV2Adatper {
    GmxAdapterStoreV2 internal _store;
    bytes32[50] private __gaps;
}

