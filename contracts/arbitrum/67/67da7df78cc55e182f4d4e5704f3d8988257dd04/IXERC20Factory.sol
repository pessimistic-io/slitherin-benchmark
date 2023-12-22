// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

interface IXERC20Factory {
  /**
   * @notice Emitted when a new XERC20 is deployed
   */

  event XERC20Deployed(address indexed _xerc20);

  /**
   * @notice Emitted when a new XERC20 implementation deployed
   */

  event XERC20ImplementationDeployed(address indexed _xerc20);

  /**
   * @notice Emitted when a new XERC20Lockbox is deployed
   */

  event LockboxDeployed(address indexed _lockbox);

  /**
   * @notice Emitted when a new XERC20Lockbox implementation deployed
   */

  event LockboxImplementationDeployed(address indexed _lockbox);

  /**
   * @notice Reverts when a non-owner attempts to call
   */

  error IXERC20Factory_NotOwner();

  /**
   * @notice Reverts when a lockbox is trying to be deployed from a malicious address
   */

  error IXERC20Factory_BadTokenAddress();

  /**
   * @notice Reverts when a lockbox is already deployed
   */

  error IXERC20Factory_LockboxAlreadyDeployed();

  /**
   * @notice Reverts when a the length of arrays sent is incorrect
   */
  error IXERC20Factory_InvalidLength();
}
