// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC20.sol";

import "./BaseVault.sol";

/// @custom:security-contact security@munchies.money
contract PizzaVault is BaseVault {
  /* solhint-disable no-empty-blocks */

  constructor(
    IERC20 asset_,
    string memory name_,
    string memory symbol_,
    address delegator_,
    address configuration_
  ) BaseVault(asset_, name_, symbol_, delegator_, configuration_) {}
}

