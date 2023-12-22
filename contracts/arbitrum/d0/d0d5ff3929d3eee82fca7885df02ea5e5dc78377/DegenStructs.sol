// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * NOTE a DEGEN contract is specifically deployed for a single targetMarketToken. So you have a different contract for ETH as for WBTC!
 * @notice struct submitted by the player, contains all the information needed to open a position
 * @param player address of the user opening the position
 * @param timestampCreated timestamp when the order was created
 * @param positionLeverage amount of leverage to use for the position
 * @param wagerAmount amount of margin/wager to use for the position, this is in the asset of the contract or in USDC
 * @param minOpenPrice minimum price to open the position
 * @param maxOpenPrice maximum price to open the position
 * @param timestampExpired timestamp when the order expires
 * @param positionKey key of the position, only populated if the order was executed
 * @param isOpened true if the position is opened, false if it is not
 * @param isLong true if the user is betting on the price going up, if false the user is betting on the price going down
 * @param isCancelled true if the order was cancelled, false if it was not
 */
struct OrderInfo {
  address player;
  address marginAsset;
  uint32 timestampCreated;
  uint16 positionLeverage;
  uint96 wagerAmount; // could be in USDC or the asset depending on marginInStables
  uint96 minOpenPrice;
  uint96 maxOpenPrice;
  uint32 timestampExpired;
  bool isOpened;
  bool isLong;
  bool isCancelled;
}

/**
 * @param isLong true if the user is betting on the price going up, if false the user is betting on the price going down
 * @param isOpen true if the position is opened, false if it is not
 * @param player address of the user opening the position
 * @param orderIndex index of the OrderInfo struct in the orders mapping
 * @param timestampOpened timestamp when the position was opened
 * @param priceOpened price when the position was opened
 * @param fundingRateOpen funding rate when the position was opened
 * @param positionSizeUsd size of the position, this is marginAmount * leverage
 * @param marginAmountOnOpenNet amount of margin used to open the position, this is in the asset of the contract - note probably will be removed
 * @param marginAmountUsd amount of margin used to open the position, this is in USDC
 * @param maxPositionProfitUsd maximum profit of the position set at the time of opening
 */
struct PositionInfo {
  bool isLong;
  bool isOpen;
  address marginAsset;
  address player;
  uint32 timestampOpened;
  uint96 priceOpened;
  uint96 positionSizeUsd; // in the asset (ETH or BTC)
  uint32 fundingRateOpen;
  uint32 orderIndex;
  uint96 marginAmountUsd; // amount of margin in USD
  uint96 maxPositionProfitUsd;
  uint96 positionSizeInTargetAsset;
}

/**
 * @notice struct containing all the information of a position when it is closed
 * @param player address of the user opening the position
 * @param isLiquidated address of the liquidator, 0x0 if the position was not liquidated
 * @param timestampClosed timestamp when the position was closed
 * @param priceClosed price when the position was closed
 * @param totalFundingRatePaidUsd total funding rate paid for the position
 * @param closeFeeProtocolUsd fee paid to close a profitable position
 * @param totalPayoutUsd total payout of the position in USD, this is the marginAmount + pnl, even if the user is paid out in the asset this is denominated in USD
 */
struct ClosedPositionInfo {
  address player;
  address liquidatorAddress;
  address marginAsset;
  bool pnlIsNegative;
  uint32 timestampClosed;
  uint96 priceClosed;
  uint96 totalFundingRatePaidUsd;
  uint96 closeFeeProtocolUsd;
  uint96 liquidationFeePaidUsd;
  uint256 totalPayoutUsd;
  int256 pnlUsd;
}

