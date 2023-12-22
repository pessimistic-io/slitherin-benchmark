// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.9;

import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";

contract JarvisToken is TransparentUpgradeableProxy {
  constructor(
    address _logic,
    address admin_,
    bytes memory _data
  ) TransparentUpgradeableProxy(_logic, admin_, _data) {}
}

