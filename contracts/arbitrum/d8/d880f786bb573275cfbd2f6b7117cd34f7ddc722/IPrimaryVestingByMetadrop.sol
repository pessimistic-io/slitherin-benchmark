// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

/**
 *
 * @title IPrimaryVestingByMetadrop.sol. Interface for base primary vesting module contract
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {IConfigStructures} from "./IConfigStructures.sol";
import {IErrors} from "./IErrors.sol";

interface IPrimaryVestingByMetadrop is IErrors, IConfigStructures {
  /** ====================================================================================================================
   *                                                        EVENTS
   * =====================================================================================================================
   */
  event PayeeAdded(
    address account,
    uint256 shares,
    uint256 vestingPeriodInDays
  );
  event PaymentReleased(address to, uint256 amount);
  event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
  event PaymentReceived(address from, uint256 amount);

  /** ====================================================================================================================
   *                                                      FUNCTIONS
   * =====================================================================================================================
   */

  /**
   * @dev Getter for the total shares held by payees.
   */
  function sharesTotal() external view returns (uint256);

  /**
   * @dev Getter for the amount of shares held by the project that are vested.
   */
  function sharesProjectVested() external view returns (uint256);

  /**
   * @dev Getter for the amount of shares held by the project that are upfront.
   */
  function sharesProjectUpfront() external view returns (uint256);

  /**
   * @dev Getter for the total amount of Ether already released.
   */
  function releasedETHTotal() external view returns (uint256);

  /**
   * @dev Getter for the amount of ETH release for the project vested.
   */
  function releasedETHProjectVested() external view returns (uint256);

  /**
   * @dev Getter for the amount of ETH release for the project upfront.
   */
  function releasedETHProjectUpfront() external view returns (uint256);

  /**
   * @dev Getter for the total amount of `token` already released. `token` should be the address of an IERC20
   * contract.
   */
  function releasedERC20Total(IERC20 token) external view returns (uint256);

  /**
   * @dev Getter for the amount of `token` tokens already released to the project vested. `token` should be the address of an
   * IERC20 contract.
   */
  function releasedERC20ProjectVested(
    IERC20 token
  ) external view returns (uint256);

  /**
   * @dev Getter for the amount of `token` tokens already released to the project upfront. `token` should be the address of an
   * IERC20 contract.
   */
  function releasedERC20ProjectUpfront(
    IERC20 token
  ) external view returns (uint256);

  /**
   * @dev Getter for project address
   */
  function projectAddresses()
    external
    view
    returns (ProjectBeneficiary[] memory);

  /**
   * @dev Calculates the amount of ether that has already vested. Default implementation is a linear vesting curve.
   */
  function vestedAmountEth(
    uint256 balance,
    uint256 timestamp
  ) external view returns (uint256);

  /**
   * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
   */
  function vestedAmountERC20(
    uint256 balance,
    uint256 timestamp
  ) external view returns (uint256);

  /**
   * @dev Getter for the amount of project's vested releasable Ether.
   */
  function releasableETHProjectVested() external view returns (uint256);

  /**
   * @dev Getter for the amount of the project's upfront releasable Ether.
   */
  function releasableETHProjectUpfront() external view returns (uint256);

  /**
   * @dev Getter for the amount of project's vested releasable `token` tokens. `token` should be the address of an
   * IERC20 contract.
   */
  function releasableERC20ProjectVested(
    IERC20 token
  ) external view returns (uint256);

  /**
   * @dev Getter for the amount of project's releasable upfront `token` tokens. `token` should be the address of an
   * IERC20 contract.
   */
  function releasableERC20ProjectUpfront(
    IERC20 token
  ) external view returns (uint256);

  /**
   * @dev Triggers a transfer to the project of the amount of Ether they are owed, according to their percentage of the
   * total shares and their previous withdrawals.
   */
  function releaseProjectETH(uint256 gasLimit_) external;

  /**
   * @dev Triggers a transfer to the project of the amount of `token` tokens they are owed, according to their
   * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
   * contract.
   */
  function releaseProjectERC20(IERC20 token) external;
}

