// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

/**
 *
 * @title IRoyaltyPaymentSplitterByMetadrop.sol. Interface for royalty module contract
 *
 * @author metadrop https://metadrop.com/
 *
 */
pragma solidity 0.8.19;

import {IERC20} from "./SafeERC20.sol";
import {IConfigStructures} from "./IConfigStructures.sol";

interface IRoyaltyPaymentSplitterByMetadrop is IConfigStructures {
  /** ====================================================================================================================
   *                                                    ENUMS AND STRUCTS
   * =====================================================================================================================
   */
  struct RoyaltyPaymentSplitterConfig {
    address[] projectRoyaltyAddresses;
    uint256[] projectRoyaltySharesInBasisPoints;
    uint256 royaltyFromSalesInBasisPoints;
    uint256 metadropShareOfRoyaltiesInBasisPoints;
  }

  /** ====================================================================================================================
   *                                                        EVENTS
   * =====================================================================================================================
   */
  event PayeeAdded(address account, uint256 shares);
  event PaymentReleased(address to, uint256 amount);
  event ERC20PaymentReleased(IERC20 indexed token, address to, uint256 amount);
  event PaymentReceived(address from, uint256 amount);

  /** ====================================================================================================================
   *                                                       FUNCTIONS
   * =====================================================================================================================
   */
  /** ____________________________________________________________________________________________________________________
   *                                                                                                         -->INITIALISE
   * @dev (function) initialiseRoyaltyPaymentSplitter  Initialise data on the royalty contract
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param royaltyModule_                        Configuration object for this instance of vesting
   * ---------------------------------------------------------------------------------------------------------------------
   * @param platformTreasury_                     The address for payments to the platform
   * ---------------------------------------------------------------------------------------------------------------------
   * @return royaltyFromSalesInBasisPoints_       The royalty share from sales in basis points
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function initialiseRoyaltyPaymentSplitter(
    RoyaltySplitterModuleConfig calldata royaltyModule_,
    address platformTreasury_
  ) external returns (uint96 royaltyFromSalesInBasisPoints_);
}

