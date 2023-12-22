// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./IERC4626.sol";
import "./ReentrancyGuard.sol";

import "./IWeth.sol";

/// @title Withdraw Assist
/// @author Christopher Enytc <wagmi@munchies.money>
/// @notice You can use this contract to withdraw native ETH from vaults that use WETH
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
contract WithdrawAssist is ReentrancyGuard {
  address public immutable weth;
  address public immutable vault;

  /**
   * @dev Set the vault contract. This must be an ERC4626 contract.
   */
  constructor(address vault_) {
    require(vault_ != address(0), "WithdrawAssist: vault_ cannot be address 0");

    weth = IERC4626(vault_).asset();
    vault = vault_;
  }

  /// @notice Withdraw native ETH from vault
  /// @dev Used to withdraw native ETH from vaults that use WETH as underlying asset
  /// @return Shares burned in the vault
  function withdraw(uint256 amount) external nonReentrant returns (uint256) {
    uint256 shares = IERC4626(vault).withdraw(
      amount,
      address(this),
      msg.sender
    );

    IWeth(weth).withdrawTo(msg.sender, amount);

    return shares;
  }
}

