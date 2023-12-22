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
    address airdropRecipient;
    uint256 saleValuation;
    uint256 saleWethValue;
    uint256 collateralWethValue;
  }

  error AlreadyRedeemed();
  error BlurAmountAlreadySet();
  error BlurAmountNotSet();
  error BeforeMinRedemptionEndTime();
  error CollateralRatioTooLow();
  error InsufficientWethAllowance();
  error InsufficientWethBalance();
  error ListingCancelled();
  error SaleWethValueExceeded();
  error SaleWethValueBelowMin();
  error MaxListingsExceeded();
  error MinCollateralRatioBelowOne();
  error MsgSenderIsNotSeller();
  error RedemptionsEnded();
  error WethPerBlurAlreadySet();
  error WethPerBlurNotSet();

  function createListing(
    address airdropRecipient,
    uint256 saleValuation,
    uint256 saleWethValue,
    uint256 collateralWethValue,
    Permit calldata permit
  ) external;

  function cancelListing(uint256 id) external;

  function reclaimCollateral(uint256[] calldata ids) external;

  function buy(
    uint256 id,
    uint256 wethAmount,
    Permit calldata permit
  ) external;

  function redeem(uint256 id) external;

  function setMinSaleWethValue(uint256 wethValue) external;

  function setMinCollateralRatio(uint256 ratio) external;

  function setMaxListingsPerSeller(uint256 count) external;

  function setSettlementWethPerBlur(uint256 settlementWethPerBlur) external;

  function setSettlementBlurAmount(
    address airdropRecipient,
    uint256 blurAmount
  ) external;

  function endRedemptions() external;

  function getListing(uint256 id) external view returns (Listing memory);

  function isListingCancelled(uint256 id) external view returns (bool);

  function getHighestListingId() external view returns (uint256);

  function getMinSaleWethValue() external view returns (uint256);

  function getCollateralRatio(uint256 id) external view returns (uint256);

  function getMinCollateralRatio() external view returns (uint256);

  function getListingCount(address seller) external view returns (uint256);

  function getMaxListingsPerSeller() external view returns (uint256);

  function getWethSpent() external view returns (uint256);

  function getWethSpent(uint256 id) external view returns (uint256);

  function getWethSpent(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getWethRedeemed(uint256 id) external view returns (uint256);

  function getWethReclaimed(uint256 id) external view returns (uint256);

  function getSettlementWethPerBlur() external view returns (uint256);

  function isSettlementBlurAmountSet(
    address airdropRecipient
  ) external view returns (bool);

  function getSettlementBlurAmount(
    address airdropRecipient
  ) external view returns (uint256);

  function getSettlementValuation(uint256 id) external view returns (uint256);

  function getAllBuyersShare(uint256 id) external view returns (uint256);

  function getRedeemableWeth(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getReclaimableCollateralWethValue(
    uint256 id
  ) external view returns (uint256);

  function getSettlementWethPerBlurSetTime() external view returns (uint256);

  function getMinRedemptionEndTime() external view returns (uint256);

  function hasRedemptionEnded() external view returns (bool);

  function getLockedCollateralWethValue(
    uint256 id
  ) external view returns (uint256);

  function getMaxSpendableWeth(uint256 id) external view returns (uint256);

  function getAdditionalCollateralNeeded(
    uint256 id
  ) external view returns (uint256);

  function getAdditionalAllowanceNeeded(
    uint256 id
  ) external view returns (uint256);

  function REDEMPTION_WINDOW() external view returns (uint256);

  function HUNDRED_PERCENT() external view returns (uint256);

  function WETH() external view returns (IERC20);
}

