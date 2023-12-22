// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.7;

import {IERC20} from "./IERC20.sol";

interface ILostMyGlasses {
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
    uint256 collateralWethPerPoint;
    string messageFromSeller;
  }

  error AlreadyRedeemed();
  error CollateralRatioTooLow();
  error InsufficientWethAllowance();
  error InsufficientWethBalance();
  error ListingCancelled();
  error SaleWethValueExceeded();
  error SaleWethValueBelowMin();
  error MaxListingsExceeded();
  error MsgSenderIsNotSeller();
  error WethPerPointAlreadySet();
  error WethPerPointNotSet();

  function createListing(
    uint256 pointsForSale,
    uint256 saleWethPerPoint,
    uint256 collateralWethPerPoint,
    string calldata messageFromSeller,
    string calldata contactUrl,
    string calldata verificationUrl,
    Permit calldata permit
  ) external payable;

  function cancelListing(uint256 id) external;

  function setContactUrl(string calldata url) external;

  function setVerificationUrl(string calldata url) external;

  function addCollateral(
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

  function redeem(uint256 id) external;

  function setMinSaleWethValue(uint256 wethValue) external;

  function setMinCollateralRatio(uint256 ratio) external;

  function setMaxListingsPerSeller(uint256 count) external;

  function setSettlementWethPerPoint(uint256 settlementWethPerPoint) external;

  function getListing(uint256 id) external view returns (Listing memory);

  function isListingCancelled(uint256 id) external view returns (bool);

  function getHighestListingId() external view returns (uint256);

  function getMinSaleWethValue() external view returns (uint256);

  function getCollateralRatio(uint256 id) external view returns (uint256);

  function getMinCollateralRatio() external view returns (uint256);

  function getListingCount(address seller) external view returns (uint256);

  function getContactUrl(address seller) external view returns (string memory);

  function getVerificationUrl(
    address seller
  ) external view returns (string memory);

  function getMaxListingsPerSeller() external view returns (uint256);

  function getWethSpent() external view returns (uint256);

  function getWethSpent(uint256 id) external view returns (uint256);

  function getWethSpent(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getWethDebt(uint256 id) external view returns (uint256);

  function getWethRedeemed(uint256 id) external view returns (uint256);

  function getSettlementWethPerPoint() external view returns (uint256);

  function getSettlementWethPerPointSetTime() external view returns (uint256);

  function getSaleWethValue(uint256 id) external view returns (uint256);

  function getCollateralWethValue(uint256 id) external view returns (uint256);

  function getRedeemableWeth(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getReclaimableCollateralWethValue(
    uint256 id
  ) external view returns (uint256);

  function getLockedCollateralWethValue(
    uint256 id
  ) external view returns (uint256);

  function getMaxSpendableWeth(uint256 id) external view returns (uint256);

  function getAdditionalBalanceNeeded(
    uint256 id
  ) external view returns (uint256);

  function getAdditionalAllowanceNeeded(
    uint256 id
  ) external view returns (uint256);

  function HUNDRED_PERCENT() external view returns (uint256);

  function WETH() external view returns (IERC20);
}

