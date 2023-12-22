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

  /// @notice Check if the user has approved the withdraw assist to transferFrom vault shares
  /// @param user The address of the user
  /// @return Approval status of the user
  function checkApproval(address user) external view returns (bool) {
    uint256 approvedAllowance = IERC4626(vault).allowance(user, address(this));

    if (approvedAllowance == type(uint256).max) {
      return true;
    }

    return false;
  }

  /// @notice Check if the user has approved a given allowance to the withdraw assist to transferFrom vault shares
  /// @param user The address of the user
  /// @param allowance The allowance to check on asset token
  /// @return Approval status of the user
  function checkApproval(
    address user,
    uint256 allowance
  ) external view returns (bool) {
    uint256 approvedAllowance = IERC4626(vault).allowance(user, address(this));

    if (allowance <= approvedAllowance) {
      return true;
    }

    return false;
  }

  /// @notice Withdraw native ETH from vault
  /// @dev Used to withdraw native ETH from vaults that use WETH as underlying asset
  /// @return Shares burned in the vault
  function withdraw(uint256 amount) external nonReentrant returns (uint256) {
    uint256 shares = IERC4626(vault).convertToShares(amount);

    uint256 assets = IERC4626(vault).redeem(
      shares + 1,
      address(this),
      msg.sender
    );

    IWeth(weth).withdrawTo(msg.sender, assets);

    return shares;
  }
}

