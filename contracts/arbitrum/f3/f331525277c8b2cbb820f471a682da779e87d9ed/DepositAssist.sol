// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./IERC20.sol";
import "./IERC4626.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";

import "./IWeth.sol";

/// @title Deposit Assist
/// @author Christopher Enytc <wagmi@munchies.money>
/// @notice You can use this contract to deposit native ETH from vaults that use WETH
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
contract DepositAssist is ReentrancyGuard {
  address public immutable weth;
  address public immutable vault;

  /**
   * @dev Set the vault contract. This must be an ERC4626 contract.
   */
  constructor(address vault_) {
    require(vault_ != address(0), "DepositAssist: vault_ cannot be address 0");

    weth = IERC4626(vault_).asset();
    vault = vault_;

    // Allow vault to use tokens in the contract
    SafeERC20.safeIncreaseAllowance(IERC20(weth), vault, type(uint256).max);
  }

  /// @notice Deposit native ETH to vault
  /// @dev Used to deposit native ETH to vaults that use WETH as underlying asset
  /// @return Shares minted in the vault
  function deposit() external payable nonReentrant returns (uint256) {
    IWeth(weth).deposit{value: msg.value}();

    uint256 shares = IERC4626(vault).deposit(msg.value, msg.sender);

    return shares;
  }
}

