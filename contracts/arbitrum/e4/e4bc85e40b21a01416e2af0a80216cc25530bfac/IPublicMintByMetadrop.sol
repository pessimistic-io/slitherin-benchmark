// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.1.0)

/**
 *
 * @title IPublicMintByMetadrop.sol. Interface for metadrop public mint primary sale module
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

import {IConfigStructures} from "./IConfigStructures.sol";

interface IPublicMintByMetadrop is IConfigStructures {
  /** ====================================================================================================================
   *                                                    STRUCTS and ENUMS
   * =====================================================================================================================
   */
  // Configuation options for this primary sale module.
  struct PublicMintConfig {
    uint256 phaseMaxSupply;
    uint256 phaseStart;
    uint256 phaseEnd;
    uint256 metadropPerMintFee;
    uint256 metadropPrimaryShareInBasisPoints;
    uint256 publicPrice;
    uint256 maxPublicQuantity;
    bool reservedAllocationPhase;
  }

  /** ====================================================================================================================
   *                                                        EVENTS
   * =====================================================================================================================
   */

  event PublicMintPriceUpdated(uint256 oldPrice, uint256 newPrice);

  /** ====================================================================================================================
   *                                                       FUNCTIONS
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) publicMintStatus  View of public mint status
   * _____________________________________________________________________________________________________________________
   */
  /**
   *
   * @dev publicMintStatus: View of public mint status
   *
   */
  function publicMintStatus() external view returns (MintStatus);

  /** ____________________________________________________________________________________________________________________
   *                                                                                                              -->SETUP
   * @dev (function) updatePublicMintPrice  Update the price per NFT for this drop (platform admin only)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param newPublicMintPrice_             The new price per mint
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function updatePublicMintPrice(uint256 newPublicMintPrice_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) publicMint  Public minting of tokens according to set config.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param quantityToMint_        The number of NFTs being minted in this call
   * ---------------------------------------------------------------------------------------------------------------------
   * @param recipient_             The address that will receive new assets
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageTimeStamp_      The timestamp of the signed message
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageHash_           The message hash signed by the trusted oracle signer. This will be checked as part of
   *                               antibot protection
   * ---------------------------------------------------------------------------------------------------------------------
   * @param messageSignature_      The signed message from the backend oracle signer for validation as part of anti-bot
   *                               protection
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function publicMint(
    uint256 quantityToMint_,
    address recipient_,
    uint256 messageTimeStamp_,
    bytes32 messageHash_,
    bytes calldata messageSignature_
  ) external payable;
}

