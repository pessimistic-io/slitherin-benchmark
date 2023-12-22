// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.7;

import {IERC20} from "./IERC20.sol";

interface IPointsMarketplace {
  struct Permit {
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  struct Listing {
    address seller;
    uint256 pointsForSale;
    uint256 saleWethPerPoint;
    uint256 initialCollateralWethPerPoint;
    uint256 promisedCollateralWethPerPoint;
  }

  event CollateralDelivery(
    uint256 indexed id,
    address deliverer,
    uint256 amount
  );
  event CollateralReclamation(
    uint256 indexed id,
    address indexed reclaimer,
    uint256 amount
  );
  event ListingCancellation(uint256 indexed id);
  event ListingCreation(
    uint256 indexed id,
    address indexed seller,
    uint256 pointsForSale,
    uint256 saleWethPerPoint,
    uint256 initialCollateralWethPerPoint,
    uint256 promisedCollateralWethPerPoint
  );
  event MaxListingsPerSellerChange(uint256 count);
  event MinSaleWethChange(uint256 amount);
  event Redemption(
    uint256 indexed id,
    address indexed redeemer,
    address indexed buyer,
    uint256 amount
  );
  event Sale(uint256 indexed id, address indexed buyer, uint256 amount);
  event SettlementWethPerPointChange(uint256 amount);

  error DeliveryExceedsUndeliveredCollateral();
  error InsufficientWethAllowance();
  error InsufficientWethBalance();
  error ListingCancelled();
  error NoWethToSpend();
  error SaleWethExceeded();
  error SaleWethBelowMin();
  error SettlementWethPerPointNotSet();
  error SettlementWethPerPointAlreadySet();
  error MaxListingsExceeded();
  error MsgSenderIsNotSeller();
  error PromisedBelowInitialCollateralWethPerPoint();
  error PromisedCollateralNotAboveSaleWethPerPoint();

  function createListing(
    uint256 pointsForSale,
    uint256 saleWethPerPoint,
    uint256 initialCollateralWethPerPoint,
    uint256 initialPromisedWethPerPoint,
    Permit calldata permit
  ) external payable;

  function cancelListing(uint256 id) external;

  function deliverCollateral(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external payable;

  function reclaimCollateral(uint256[] calldata ids) external;

  function buy(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external payable;

  function redeem(uint256 id, address buyer) external;

  function setMinSaleWeth(uint256 amount) external;

  function setMaxListingsPerSeller(uint256 count) external;

  function setSettlementWethPerPoint(uint256 settlementWethPerPoint) external;

  function getListing(uint256 id) external view returns (Listing memory);

  function isCancelledListing(uint256 id) external view returns (bool);

  function isReclaimedListing(uint256 id) external view returns (bool);

  function getHighestListingId() external view returns (uint256);

  function getMinSaleWeth() external view returns (uint256);

  function getListingCount(address seller) external view returns (uint256);

  function getMaxListingsPerSeller() external view returns (uint256);

  function getSoldWeth() external view returns (uint256);

  function getSoldWeth(uint256 id) external view returns (uint256);

  function getSoldWeth(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getRedeemedWeth(uint256 id) external view returns (uint256);

  function getRedeemedWeth(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getDeliveredWeth(uint256 id) external view returns (uint256);

  function getSettlementWethPerPoint() external view returns (uint256);

  function getMaxUnredeemedWeth(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getSettlementWethPerPointSetTime() external view returns (uint256);

  function getSaleWeth(uint256 id) external view returns (uint256);

  function getTakenCollateralWeth(uint256 id) external view returns (uint256);

  function getTakenAndDeliveredCollateralWeth(
    uint256 id
  ) external view returns (uint256);

  function getUnsoldWeth(uint256 id) external view returns (uint256);

  function getUnredeemedWeth(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getUnreclaimedWeth(uint256 id) external view returns (uint256);

  function getUntakenCollateralWeth(
    uint256 id
  ) external view returns (uint256);

  function getUndeliveredCollateralWeth(
    uint256 id
  ) external view returns (uint256);

  function getMaxSpendableWeth(uint256 id) external view returns (uint256);

  function getAdditionalBalanceNeeded(
    uint256 id
  ) external view returns (uint256);

  function getAdditionalAllowanceNeeded(
    uint256 id
  ) external view returns (uint256);

  function WETH() external view returns (IERC20);
}

