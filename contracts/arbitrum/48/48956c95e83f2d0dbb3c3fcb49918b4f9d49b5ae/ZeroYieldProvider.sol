// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IZeroYieldProvider.sol";
import "./Roles.sol";

contract ZeroYieldProvider is Initializable, IZeroYieldProvider {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  // ERRORS

  error NYP_NOT_ALLOWED();
  error NYP_UNAUTHORIZED_ASSET();
  error NYP_WRONG_INPUT();
  error NYP_ZERO_ADDRESS();

  // STORAGE

  AccessControlUpgradeable public pools;
  mapping(address => bool) private assets;

  // INITIALIZATION

  function initialize(AccessControlUpgradeable _pools, address asset) public initializer {
    if (address(_pools) == address(0)) {
      revert NYP_ZERO_ADDRESS();
    }
    assets[asset] = true;
    pools = _pools;
  }

  // MODIFIER

  modifier onlyPools() {
    if (msg.sender != address(pools)) {
      revert NYP_NOT_ALLOWED();
    }
    _;
  }

  modifier onlyAuthorizedAssets(address asset) {
    if (!assets[asset]) {
      revert NYP_UNAUTHORIZED_ASSET();
    }
    _;
  }

  // VIEW METHODS

  function isAssetAuthorized(address asset) external view returns (bool) {
    if (asset == address(0)) {
      revert NYP_ZERO_ADDRESS();
    }
    return assets[asset];
  }

  function getReserveNormalizedIncome(address asset)
    external
    view
    override
    onlyAuthorizedAssets(asset)
    returns (uint256)
  {
    if (asset == address(0)) {
      revert NYP_ZERO_ADDRESS();
    }
    return 1e27;
  }

  // BORROWER POOLS METHODS

  function deposit(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16 referralCode
  ) external override onlyPools onlyAuthorizedAssets(asset) {
    if (asset == address(0)) {
      revert NYP_ZERO_ADDRESS();
    }
    if (referralCode != 0) {
      revert NYP_WRONG_INPUT();
    }
    IERC20Upgradeable(asset).safeTransferFrom(onBehalfOf, address(this), amount);

    emit Deposit(asset, msg.sender, onBehalfOf, amount, referralCode);
  }

  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external override onlyPools onlyAuthorizedAssets(asset) returns (uint256) {
    IERC20Upgradeable(asset).safeTransfer(to, amount);

    emit Withdraw(asset, msg.sender, to, amount);

    return amount;
  }

  // GOVERNANCE METHODS

  function setAssetAuthorization(address asset, bool isAuthorized) external {
    if (!AccessControlUpgradeable(address(pools)).hasRole(Roles.GOVERNANCE_ROLE, msg.sender)) {
      revert NYP_NOT_ALLOWED();
    }
    if (asset == address(0)) {
      revert NYP_ZERO_ADDRESS();
    }

    assets[asset] = isAuthorized;

    emit SetAssetAuthorization(asset, isAuthorized);
  }
}

