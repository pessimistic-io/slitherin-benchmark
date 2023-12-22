// SPDX-License-Identifier: BUSL-1.1

import "./AbstractPool.sol";
import "./AbstractRegistry.sol";
import "./ERC20Fixed.sol";
import "./Errors.sol";
import "./ERC20.sol";

pragma solidity ^0.8.17;

contract MarginPool is AbstractPool {
  using ERC20Fixed for ERC20;

  function initialize(
    address _owner,
    ERC20 _baseToken,
    AbstractRegistry _registry
  ) external initializer {
    __AbstractPool_init(_owner, _baseToken, _registry);
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function transferBase(
    address _to,
    uint256 _amount
  ) external override onlyApproved {
    baseToken.transferFixed(_to, _amount);
  }

  function transferFromPool(
    address _token,
    address _to,
    uint256 _amount
  ) external override onlyApproved {
    _require(_token == address(baseToken), Errors.TOKEN_MISMATCH);
    baseToken.transferFixed(_to, _amount);
  }

  function getBaseBalance() external view returns (uint256) {
    return baseToken.balanceOfFixed(address(this));
  }
}

