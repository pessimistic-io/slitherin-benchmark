// SPDX-License-Identifier: BUSL-1.1

import "./ERC20Fixed.sol";
import "./FixedPoint.sol";
import {LiquidityPool} from "./LiquidityPool.sol";
import {ERC20} from "./ERC20.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";

pragma solidity ^0.8.17;

contract FeeVault is OwnableUpgradeable, AccessControlUpgradeable {
  using FixedPoint for uint256;
  using ERC20Fixed for ERC20;
  using ERC20Fixed for LiquidityPool;

  address baseToken;
  address liquidityPool;

  function initialize(
    address _owner,
    address _baseToken,
    address _liquidityPool
  ) external initializer {
    __Ownable_init();
    __AccessControl_init();

    _transferOwnership(_owner);
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);

    baseToken = _baseToken;
    liquidityPool = _liquidityPool;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function add(uint256 amount) external {
    _require(amount > 0, Errors.INVALID_AMOUNT);
    ERC20(baseToken).transferFromFixed(msg.sender, address(this), amount);
    ERC20(baseToken).approve(liquidityPool, amount);
    LiquidityPool(liquidityPool).mint(amount);
    uint256 minted = LiquidityPool(liquidityPool).balanceOfFixed(address(this));
    LiquidityPool(liquidityPool).approve(liquidityPool, minted);
    LiquidityPool(liquidityPool).stake(minted);
  }
}

