// SPDX-License-Identifier: MIT
// Metadrop Contracts (v0.0.1)

/**
 *
 * @title IAuctionByMetadrop.sol. Interface for metadrop auction primary sale module
 *
 * @author metadrop https://metadrop.com/
 *
 */

pragma solidity 0.8.19;

import {IConfigStructures} from "./IConfigStructures.sol";

interface IAuctionByMetadrop is IConfigStructures {
  /** ====================================================================================================================
   *                                                    STRUCTS and ENUMS
   * =====================================================================================================================
   */
  // Bid Status:
  enum Status {
    notYetOpen,
    open,
    finished,
    unknown
  }

  // Struct for module configuration
  struct AuctionConfig {
    uint256 phaseMaxSupply;
    uint256 phaseStart;
    uint256 phaseEnd;
    uint256 metadropPerMintFee;
    uint256 metadropPrimaryShareInBasisPoints;
    uint256 minUnitPrice;
    uint256 maxUnitPrice;
    uint256 minQuantity;
    uint256 maxQuantity;
    uint256 minBidIncrement;
  }

  // Object for bids:
  struct Bid {
    uint112 unitPrice;
    uint112 quantity;
    uint32 levelPosition;
  }
  /** ====================================================================================================================
   *                                                     EVENTS
   * =====================================================================================================================
   */

  // Event emitted at the end of the auction:
  event AuctionEnded();

  // Event emitted when a bid is placed:
  event BidPlaced(
    address indexed bidder,
    //uint256 bidIndex,
    uint256 unitPrice,
    uint256 quantity,
    uint256 balance
  );

  // Event emitted when a refund is issued. Note that a refund could be during the
  // auction for a bid below the floor price or after the completion of the auction.
  // Bidders are entitled to a refund when:
  // - They have not won any items (refund = total bid amount)
  // - They have won some of the items the bid on (refund = total bid amount for
  //   items that were not won + diff floor to bid amount for won items)
  // - They won items above the floor price (refund = total bid amount - quantity of
  //   bid multiplied by the end floor price)
  //
  // Users can mint and refund from the second the auction completed.
  event RefundIssued(address indexed refundRecipient, uint256 refundAmount);

  event AuctionFinalFloorDetailsSet(
    uint80 endAuctionFloorPrice,
    uint56 endAuctionAboveFloorBidQuantity,
    uint56 endAuctionLastFloorPosition,
    uint56 endAuctionRunningTotalAtLastFloorPosition
  );

  /** ====================================================================================================================
   *                                                     FUNCTIONS
   * =====================================================================================================================
   */

  /** ____________________________________________________________________________________________________________________
   *                                                                                                           -->WORKFLOW
   * @dev (function) auctionStatus  returns the status of the auction
   *                                  - notYetOpen: auction hasn't started yet
   *                                  - open: auction is currently active
   *                                  - finished: auction has ended
   *                                  - unknown: theoretically impossible
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return auctionStatus_        The status of the auction
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function auctionStatus() external view returns (Status auctionStatus_);

  /** ____________________________________________________________________________________________________________________
   *                                                                                                           -->WORKFLOW
   * @dev (function) endAuction  External function that can be called to execute _endAuction
   *                             when the block.timestamp exceeds the auction end time (i.e. the auction is over).
   * _____________________________________________________________________________________________________________________
   */
  function endAuction() external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->AUCTION
   * @dev (function) getBid    Returns the bid data for the passed address.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param bidder_             The bidder being queries
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bid_               Bid details for the bidder
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getBid(address bidder_) external view returns (Bid memory bid_);

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->AUCTION
   * @dev (function) getFloorLevel    returns the floor price for the give level and the array of values in the
   *                                  floor tracker for that level
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param index_             The bidder being queries
   * ---------------------------------------------------------------------------------------------------------------------
   * @return levelPrice_       The price at the queried level index
   * ---------------------------------------------------------------------------------------------------------------------
   * @return levelArray_       Array of values in the floor tracker at this level
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getFloorLevel(
    uint256 index_
  ) external view returns (uint256 levelPrice_, uint8[] memory levelArray_);

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->AUCTION
   * @dev (function) placeBid     When a bidder places a bid or updates their existing bid, they will use this function.
   *                                - total value can never be lowered
   *                                - unit price can never be lowered
   *                                - quantity can be raised
   *                                - if the bid is below the floor quantity can be lowered, but only if unit price
   *                                  is raised to meet or exceed previous total price
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param quantity_             The quantity of items the bid is for
   * ---------------------------------------------------------------------------------------------------------------------
   * @param unitPrice_            The unit price for each item bid upon
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function placeBid(uint256 quantity_, uint256 unitPrice_) external payable;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->AUCTION
   * @dev (function) bidIsBelowFloor     Returns if a bid is below the floor (or not)
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param bidAmount_            The unit price for each item bid upon
   * ---------------------------------------------------------------------------------------------------------------------
   * @return bidIsBelowFloor_     The bid IS below the floor
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function bidIsBelowFloor(
    uint256 bidAmount_
  ) external view returns (bool bidIsBelowFloor_);

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->AUCTION
   * @dev (function) getAuctionFloor     Return the auction floor and the quantity of bids that are above the floor.
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @return theFloor_                Current bid floor
   * ---------------------------------------------------------------------------------------------------------------------
   * @return aboveFloorBidQuantity_   Number of items above the floor
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getAuctionFloor()
    external
    view
    returns (uint80 theFloor_, uint56 aboveFloorBidQuantity_);

  /**
   *
   * @dev recordAuctionFinalFloorDetails: persist the final floor values to storage
   * so they can be read rather than calculated for all subsequent processing
   *
   */
  function recordAuctionFinalFloorDetails() external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                            -->AUCTION
   * @dev (function) setAuctionFinalFloorDetails   allow the setting of final auction floor details by the Owner.
   *
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionFloorPrice_                         The floor price at the end of the auction
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionAboveFloorBidQuantity_             Items above the floor price
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionLastFloorPosition_                  The last floor position for the auction
   * ---------------------------------------------------------------------------------------------------------------------
   * @param endAuctionRunningTotalAtLastFloorPosition_   Running total at the last floor position
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function setAuctionFinalFloorDetails(
    uint80 endAuctionFloorPrice_,
    uint56 endAuctionAboveFloorBidQuantity_,
    uint56 endAuctionLastFloorPosition_,
    uint56 endAuctionRunningTotalAtLastFloorPosition_
  ) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) refundAndMint   external function call to allow bidders to claim refunds and mint tokens
   *
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param recipient_              The recipient of NFTs for the caller
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function refundAndMint(address recipient_) external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) refund   External function call to allow bidders to claim refunds. Note that this can be
   *                          called DURING the auction but cannot be called AFTER the action. After the auction has ended
   *                          all claims go through refundAndMint. No mint will occur for losing bids, but this keeps the
   *                          post-auction refund and claim process in one function
   * _____________________________________________________________________________________________________________________
   */
  function refund() external;

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) getBidDetails     Get details of a bid including the winning quantity.
   *                                   during the auction the winning quantity will be at that point in time (as bids
   *                                   may move into losing positions as a result of subsequent bids).
   *
   * ---------------------------------------------------------------------------------------------------------------------
   * @param bidder_                    The bidder being queried
   * ---------------------------------------------------------------------------------------------------------------------
   * _____________________________________________________________________________________________________________________
   */
  function getBidDetails(
    address bidder_
  )
    external
    view
    returns (uint256 quantity, uint256 unitPrice, uint256 winningAllocation);

  /** ____________________________________________________________________________________________________________________
   *                                                                                                               -->MINT
   * @dev (function) auctionSupply     The supply for this auction (derived from the associated NFT contract
   *
   * _____________________________________________________________________________________________________________________
   */
  function auctionSupply() external view returns (uint32);
}

