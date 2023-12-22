// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity =0.8.7;

import "./ITransferHook.sol";
import "./IERC20Upgradeable.sol";
import "./draft-IERC20PermitUpgradeable.sol";

interface IPPO is IERC20Upgradeable, IERC20PermitUpgradeable {
  /**
   * @notice Sets the external `ITransferHook` contract to be called before
   * any PPO transfer.
   * @dev The transfer hook's `hook()` function will be called within
   * `_beforeTokenTransfer()`.
   *
   * Only callable by `owner()`.
   * @param newTransferHook Address of the `ITransferHook` contract
   */
  function setTransferHook(ITransferHook newTransferHook) external;

  /**
   * @notice Mints `amount` PPO to `recipient`.
   * @dev Only callable by `owner()`.
   * @param recipient Address to send minted `PPO` to
   * @param amount Amount of `PPO` to be sent
   */
  function mint(address recipient, uint256 amount) external;

  /**
   * @notice Burns `amount` tokens from the caller.
   * @param amount Amount of `PPO` to be burned
   */
  function burn(uint256 amount) external;

  /**
   * @notice Burns `amount` tokens from `account`.
   * @dev The caller's allowance with the `account` must be >= `amount` and
   * will be decreased by `amount`.
   * @param account Address to burn `PPO` from
   * @param amount Amount of `PPO` to be burned
   */
  function burnFrom(address account, uint256 amount) external;

  ///@return The transfer hook contract
  function getTransferHook() external view returns (ITransferHook);
}

