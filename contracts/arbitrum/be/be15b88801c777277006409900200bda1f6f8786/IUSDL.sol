// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20Metadata.sol";

/// @title USDL Events
/// @notice interface which contains any events which the USDL contract emits
interface USDLEvents {
  event Deposit(address indexed _from, uint256 _value);
  event Withdraw(address indexed _from, uint256 _value);
  event Mint(address to, uint256 _value);
  event Burn(address from, uint256 _value);
  event Donation(address indexed _from, uint256 _value, uint256 _totalSupply);
}

/// @title USDL Interface
/// @notice extends USDLEvents and IERC20Metadata
interface IUSDL is IERC20Metadata, USDLEvents {
  /// @notice initializer specifies the reserveAddress
  function initialize(address reserveAddress) external;

  // getters
  function reserveRatio() external view returns (uint192);

  function reserveAddress() external view returns (address);

  // owner
  function owner() external view returns (address);

  // business
  function deposit(uint256 usdc_amount) external;

  function depositTo(uint256 usdc_amount, address target) external;

  function withdraw(uint256 usdc_amount) external;

  function withdrawTo(uint256 usdc_amount, address target) external;

  function withdrawAll() external;

  function withdrawAllTo(address target) external;

  function donate(uint256 usdc_amount) external;

  function donateReserve() external;

  // admin functions

  function setPauser(address pauser_) external;

  function pauser() external view returns (address);

  function pause() external;

  function unpause() external;

  function mint(uint256 usdc_amount) external;

  function burn(uint256 usdc_amount) external;

  function setVaultController(address vault_master_address) external;

  function getVaultController() external view returns (address);

  // functions for the vault controller to call
  function vaultControllerBurn(address target, uint256 amount) external;

  function vaultControllerMint(address target, uint256 amount) external;

  function vaultControllerTransfer(address target, uint256 usdc_amount) external;

  function vaultControllerDonate(uint256 amount) external;
}

