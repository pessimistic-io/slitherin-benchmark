// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

import "./IMintableBurnable.sol";
import "./Errors.sol";
import "./FixedPoint.sol";
import "./ERC20Fixed.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ERC20.sol";

/// @custom:security-contact security@uniwhale.co
contract BridgedVault is
  OwnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  IMintableBurnable,
  ReentrancyGuardUpgradeable
{
  using ERC20Fixed for ERC20;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  ERC20 public bridgedToken;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address owner,
    ERC20 _bridgedToken
  ) public virtual initializer {
    __Ownable_init();
    __Pausable_init();
    __AccessControl_init();
    __ReentrancyGuard_init();

    _require(
      owner != address(0) && address(_bridgedToken) != address(0),
      Errors.INVALID_INPUT
    );

    bridgedToken = _bridgedToken;

    _transferOwnership(owner);
    _grantRole(DEFAULT_ADMIN_ROLE, owner);
    _grantRole(MINTER_ROLE, owner);
  }

  function balance() external view override returns (uint256) {
    return bridgedToken.balanceOfFixed(address(this));
  }

  function addBalance(uint256 amount) external override {
    bridgedToken.transferFromFixed(msg.sender, address(this), amount);
  }

  function removeBalance(uint256 amount) external override onlyOwner {
    bridgedToken.transferFixed(msg.sender, amount);
  }

  function mint(
    address to,
    uint256 amount
  ) external override onlyRole(MINTER_ROLE) {
    _require(
      amount <= bridgedToken.balanceOfFixed(address(this)),
      Errors.INVALID_AMOUNT
    );
    bridgedToken.transferFixed(to, amount);
  }

  function balanceOf(address account) external view override returns (uint256) {
    return bridgedToken.balanceOfFixed(account);
  }

  function burn(uint256 amount) external override {
    bridgedToken.transferFromFixed(msg.sender, address(this), amount);
  }

  function burnFrom(
    address account,
    uint256 amount
  ) external override onlyRole(MINTER_ROLE) {
    bridgedToken.transferFromFixed(account, address(this), amount);
  }
}

