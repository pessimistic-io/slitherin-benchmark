// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./LibMarketplaces.sol";
import "./ITroveMarketplace.sol";
import "./ConsiderationStructs.sol";


/// @notice Order struct for any marketplace
/// @dev Only a single payment token is allowed. Use address(0) for ETH
struct BuyOrder {
  BuyItemParams buyItemParamsOrder;
  Order[] seaportOrders;
  CriteriaResolver[] criteriaResolvers;
  Fulfillment[] fulfillments;
  address marketplaceAddress;
  MarketplaceType marketplaceType;
  address paymentToken;
}

/// @notice Multitoken Order struct for any marketplace
/// @dev Multiple payment tokens are allowed. Use address(0) for ETH. The tokenIndex must be the correct corresponding index in the paymentTokens array
struct MultiTokenBuyOrder {
  BuyItemParams buyItemParamsOrder;
  Order[] seaportOrders;
  CriteriaResolver[] criteriaResolvers;
  Fulfillment[] fulfillments;
  address marketplaceAddress;
  MarketplaceType marketplaceType;
  address paymentToken;
  uint16 tokenIndex;
}

