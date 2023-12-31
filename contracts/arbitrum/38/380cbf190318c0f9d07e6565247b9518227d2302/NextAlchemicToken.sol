// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {ERC20PermitUpgradeable} from "./draft-ERC20PermitUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

import {IllegalArgument, IllegalState, Unauthorized} from "./Errors.sol";

import {IERC3156FlashLender} from "./IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "./IERC3156FlashBorrower.sol";

import {IAlchemicToken} from "./IAlchemicToken.sol";

import "./TokenUtils.sol";

struct InitializationParams {
  string name;
  string symbol;
}

/// @title  NextAlchemicToken
/// @author Alchemix Finance
///
/// @notice This is the contract for connext bridge token versions of al assets.
contract NextAlchemicToken is ERC20PermitUpgradeable, AccessControlUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  /// @notice The identifier of the role which maintains other roles.
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

  /// @notice The identifier of the role which allows accounts to mint tokens.
  bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL");

  /// @notice A set of addresses which are whitelisted for minting new tokens.
  mapping(address => bool) public whitelisted;

  /// @notice A set of addresses which are paused from minting new tokens.
  mapping(address => bool) public paused;

  constructor() initializer {}

  /// @notice An event which is emitted when a minter is paused from minting.
  ///
  /// @param minter The address of the minter which was paused.
  /// @param state  A flag indicating if the alchemist is paused or unpaused.
  event Paused(address minter, bool state);

  /// @notice An event which is emitted when a minter is updated in the whitelist.
  /// 
  /// @param minter   The address of the minter.
  /// @param state    Whether or not the minter is actively able to mint.
  event WhitelistSet(address minter, bool state);

  function initialize(InitializationParams memory params) public initializer {
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(SENTINEL_ROLE, msg.sender);
    _setRoleAdmin(SENTINEL_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

    __Context_init_unchained();
    __Ownable_init_unchained();
    __ERC20_init_unchained(params.name, params.symbol);
    __ERC20Permit_init_unchained(params.name);
    __ReentrancyGuard_init_unchained();
  }

  /// @dev A modifier which checks that the caller has the admin role.
  modifier onlyAdmin() {
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      revert Unauthorized();
    }
    _;
  }

  /// @dev A modifier which checks that the caller has the sentinel role.
  modifier onlySentinel() {
    if(!hasRole(SENTINEL_ROLE, msg.sender)) {
      revert Unauthorized();
    }
    _;
  }

  /// @dev A modifier which checks if whitelisted for minting.
  modifier onlyWhitelisted() {
    if(!whitelisted[msg.sender]) {
      revert Unauthorized();
    }
    _;
  }

  /// @notice Mints tokens to `a recipient.`
  ///
  /// @notice This function reverts if `msg.sender` is not whitelisted.
  /// @notice This function reverts if `msg.sender` is paused.
  ///
  /// @param recipient The address to mint the tokens to.
  /// @param amount    The amount of tokens to mint.
  function mint(address recipient, uint256 amount) external onlyWhitelisted {
    if (paused[msg.sender]) {
      revert IllegalState();
    }

    _mint(recipient, amount);
  }

  /// @notice Sets `minter` as whitelisted to mint.
  ///
  /// @notice This function reverts if `msg.sender` is not an admin.
  ///
  /// @param minter The account to permit to mint.
  /// @param state  A flag indicating if the minter should be able to mint.
  function setWhitelist(address minter, bool state) external onlyAdmin {
    whitelisted[minter] = state;

    emit WhitelistSet(minter, state);
  }

  /// @notice Pauses `minter` from minting tokens.
  ///
  /// @notice This function reverts if `msg.sender` is not a sentinel.
  ///
  /// @param minter The address to set as paused or unpaused.
  /// @param state  A flag indicating if the minter should be paused or unpaused.
  function pauseMinter(address minter, bool state) external onlySentinel {
    paused[minter] = state;
    emit Paused(minter, state);
  }

  /// @notice Burns `amount` tokens from `account`.
  ///
  /// @param amount  The amount of tokens to be burned.
  /// @param account The address to burn from.
  function burn(address account, uint256 amount) external {
    if (msg.sender != account) {
      uint256 newAllowance = allowance(account, msg.sender) - amount;
      _approve(account, msg.sender, newAllowance);
    }
    
    _burn(account, amount);
  }
}
