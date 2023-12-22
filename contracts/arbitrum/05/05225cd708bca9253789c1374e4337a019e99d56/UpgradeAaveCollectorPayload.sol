// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IInitializableAdminUpgradeabilityProxy} from "./IInitializableAdminUpgradeabilityProxy.sol";
import {ICollector} from "./ICollector.sol";

contract UpgradeAaveCollectorPayload {
  // v3 collector proxy address
  IInitializableAdminUpgradeabilityProxy public immutable COLLECTOR_PROXY;

  // new collector impl
  address public immutable COLLECTOR;

  // short executor or guardian address
  address public immutable NEW_FUNDS_ADMIN;

  // proxy admin
  address public immutable PROXY_ADMIN;

  // streamId
  uint256 public immutable STREAM_ID;

  constructor(
    address proxy,
    address collector,
    address proxyAdmin,
    address newFundsAdmin,
    uint256 streamId
  ) {
    COLLECTOR_PROXY = IInitializableAdminUpgradeabilityProxy(proxy);
    COLLECTOR = collector;
    PROXY_ADMIN = proxyAdmin;
    NEW_FUNDS_ADMIN = newFundsAdmin;
    STREAM_ID = streamId;
  }

  function execute() external {
    // Upgrade of collector implementation
    COLLECTOR_PROXY.upgradeToAndCall(
      address(COLLECTOR),
      abi.encodeWithSelector(ICollector.initialize.selector, NEW_FUNDS_ADMIN, STREAM_ID)
    );

    // Update proxy admin
    COLLECTOR_PROXY.changeAdmin(PROXY_ADMIN);
  }
}

