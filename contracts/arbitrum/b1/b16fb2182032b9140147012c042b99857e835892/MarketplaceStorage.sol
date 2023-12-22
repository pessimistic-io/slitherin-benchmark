// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

/**
 * @title Interface for contracts conforming to ERC-721
 */
import "./IERC20Upgradeable.sol";


contract MarketplaceStorage {
  struct Order {
    // Order ID
    uint256 id;
    // Owner of the asset
    address payable seller;
    // nft address
    address nftAddress;
    // Asset id
    uint256 assetId;
    // Price (in wei) for the published item
    uint256 price;
    // Fee amount
    uint256 fee;
  }

  mapping(uint256 => Order) public orders;

  address public currencyAddress;

  address public feeHolder;
  uint256 public feeRate;

  // EVENTS
  event OrderCreated(
    uint256 id,
    uint256 indexed assetId,
    address indexed seller,
    address nftAddress,
    uint256 price,
    uint256 fee
  );
  event OrderSuccessful(
    uint256 id,
    uint256 indexed assetId,
    address indexed seller,
    address nftAddress,
    uint256 price,
    address indexed buyer
  );
  event OrderCancelled(
    uint256 id,
    uint256 indexed assetId,
    address indexed seller,
    address nftAddress
  );

  event PriceUpdated(
    uint256 id,
    uint256 oldPrice,
    uint256 newPrice
  );

  event ChangedFeeRate(uint256 feeRate);
  event ChangedFeeHolder(address feeHolder);
}
