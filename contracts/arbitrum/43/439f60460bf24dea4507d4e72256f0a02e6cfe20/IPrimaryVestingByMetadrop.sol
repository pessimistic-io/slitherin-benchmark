// SPDX-License-Identifier: MIT
// Metadrop Contracts (v0.0.1)

/**
 *
 * @title IPrimaryVestingByMetadrop.sol. Interface for base primary vesting module contract
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./IConfigStructures.sol";

interface IPrimaryVestingByMetadrop is IConfigStructures {
  /** ====================================================================================================================
   *                                                    ENUMS AND STRUCTS
   * =====================================================================================================================
   */
  struct VestingConfig {
    uint256 start;
    uint256 projectUpFrontShare;
    uint256 projectVestedShare;
    uint256 vestingPeriodInDays;
    uint256 vestingCliff;
    ProjectBeneficiary[] projectPayees;
  }

  struct ProjectBeneficiary {
    address payable payeeAddress;
    uint256 payeeShares;
  }

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
  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) initialisePrimaryVesting  Initialise data on the vesting contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param vestingModule_    Configuration object for this instance of vesting
   * ---------------------------------------------------------------------------------------------------------------------
   * @param platformAddress_  The address for payments to the platform
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function initialisePrimaryVesting(
    VestingModuleConfig calldata vestingModule_,
    address platformAddress_,
    uint256 platformShare_
  ) external;

  /**
   * @dev The Ether received will be logged with {PaymentReceived} events. Note that these events are not fully
   * reliable: it's possible for a contract to receive Ether without triggering this function. This only affects the
   * reliability of the events, and not the actual splitting of Ether.
   *
   * To learn more about this see the Solidity documentation for
   * https://solidity.readthedocs.io/en/latest/contracts.html#fallback-function[fallback
   * functions].
   */
  receive() external payable;

  /**
   * @dev Getter for the total shares held by payees.
   */
  function sharesTotal() external view returns (uint256);

  /**
   * @dev Getter for the amount of shares held by the platform.
   */
  function sharesPlatform() external view returns (uint256);

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
   * @dev Getter for the amount of Ether already released to the platform.
   */
  function releasedETHPlatform() external view returns (uint256);

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
   * @dev Getter for the amount of `token` tokens already released to the platform. `token` should be the address of an
   * IERC20 contract.
   */
  function releasedERC20Platform(IERC20 token) external view returns (uint256);

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
   * @dev Getter for platform address
   */
  function platformAddress() external view returns (address);

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
   * @dev Getter for the amount of the platform's releasable Ether.
   */
  function releasableETHPlatform() external view returns (uint256);

  /**
   * @dev Getter for the amount of project's vested releasable Ether.
   */
  function releasableETHProjectVested() external view returns (uint256);

  /**
   * @dev Getter for the amount of the project's upfront releasable Ether.
   */
  function releasableETHProjectUpfront() external view returns (uint256);

  /**
   * @dev Getter for the amount of platform's releasable `token` tokens. `token` should be the address of an
   * IERC20 contract.
   */
  function releasableERC20Platform(
    IERC20 token
  ) external view returns (uint256);

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
   * @dev Triggers a transfer to the platform of the amount of Ether they are owed, according to their percentage of the
   * total shares and their previous withdrawals.
   */
  function releasePlatformETH() external;

  /**
   * @dev Triggers a transfer to the project of the amount of Ether they are owed, according to their percentage of the
   * total shares and their previous withdrawals.
   */
  function releaseProjectETH(uint256 gasLimit_) external;

  /**
   * @dev Triggers a transfer to the platform of the amount of `token` tokens they are owed, according to their
   * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
   * contract.
   */
  function releasePlatformERC20(IERC20 token) external;

  /**
   * @dev Triggers a transfer to the project of the amount of `token` tokens they are owed, according to their
   * percentage of the total shares and their previous withdrawals. `token` must be the address of an IERC20
   * contract.
   */
  function releaseProjectERC20(IERC20 token) external;
}

