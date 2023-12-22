//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./ERC20.sol";
import "./Pausable.sol";
import "./AccessControl.sol";

contract SoulBoundToad is ERC20, AccessControl {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
  bytes32 public constant SLASH_ROLE = keccak256("SLASH_ROLE");

  constructor(uint256 initialSupply) ERC20("SoulBoundToad", "$toad") {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(MINTER_ROLE, msg.sender);
    _grantRole(TRANSFER_ROLE, msg.sender);
    _grantRole(SLASH_ROLE, msg.sender);
    _mint(msg.sender, initialSupply);
  }

  /// @notice guarded transfer to enable soul-bound non-transferrable token
  /// @param _to is the contract address receiving the tokens if unpaused
  /// @param _value is the amount of tokens transffered if unpaused
  function transfer(address _to, uint256 _value)
    public
    override
    onlyRole(TRANSFER_ROLE)
    returns (bool)
  {
    return super.transfer(_to, _value);
  }

  /// @notice guarded transferFrom to enable soul-bound non-transferrable token
  /// @param _from is the address sending the tokens if unpaused
  /// @param _to is the address receiving the tokens if unpaused
  /// @param _value is the amount of tokens transffered if unpaused
  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  ) public override onlyRole(TRANSFER_ROLE) returns (bool) {
    return super.transferFrom(_from, _to, _value);
  }

  /// @notice mintTo mints new $toad.
  /// @param receiver is the address receiving the tokens to be minted.
  /// @param amount is the amount of $toad to be minted.
  function mintTo(address receiver, uint256 amount)
    external
    onlyRole(MINTER_ROLE)
  {
    _mint(receiver, amount);
  }

  /// @notice slashes the balance of {account} by {amount}.
  /// @param account is the account getting slashed.
  /// @param amount is the amount to slash on {account}.
  function slash(address account, uint256 amount)
    external
    onlyRole(SLASH_ROLE)
  {
    _burn(account, amount);
  }
}

