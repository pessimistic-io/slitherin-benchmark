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
    uint256 saleEthValue;
    uint256 collateralEthValue;
  }

  error AlreadyRedeemed();
  error BlurAmountAlreadySet();
  error BlurAmountNotSet();
  error BeforeMinRedemptionEndTime();
  error CollateralRatioTooLow();
  error InsufficientWETHAllowance();
  error InsufficientWETHBalance();
  error ListingCancelled();
  error SaleEthValueExceeded();
  error SaleEthValueBelowMin();
  error MaxListingsExceeded();
  error MinCollateralRatioBelowOne();
  error MsgSenderIsNotSeller();
  error RedemptionsEnded();
  error WethPerBlurAlreadySet();
  error WethPerBlurNotSet();

  function createListing(
    address airdropRecipient,
    uint256 leverage,
    uint256 saleEthValue,
    uint256 collateralEthValue,
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

  function setMinSaleEthValue(uint256 ethValue) external;

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

  function getMinSaleEthValue() external view returns (uint256);

  function getCollateralRatio(uint256 id) external view returns (uint256);

  function getMinCollateralRatio() external view returns (uint256);

  function getListingCount(address seller) external view returns (uint256);

  function getMaxListingsPerSeller() external view returns (uint256);

  function getEthSpent() external view returns (uint256);

  function getEthSpent(uint256 id) external view returns (uint256);

  function getEthSpent(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getEthRedeemed(uint256 id) external view returns (uint256);

  function getEthReclaimed(uint256 id) external view returns (uint256);

  function getSettlementWethPerBlur() external view returns (uint256);

  function isSettlementBlurAmountSet(
    address airdropRecipient
  ) external view returns (bool);

  function getSettlementBlurAmount(
    address airdropRecipient
  ) external view returns (uint256);

  function getSettlementValuation(uint256 id) external view returns (uint256);

  function getSettlementEthValue(uint256 id) external view returns (uint256);

  function getRedeemableEth(
    uint256 id,
    address buyer
  ) external view returns (uint256);

  function getReclaimableCollateralEthValue(
    uint256 id
  ) external view returns (uint256);

  function getSettlementWethPerBlurSetTime() external view returns (uint256);

  function getMinRedemptionEndTime() external view returns (uint256);

  function hasRedemptionEnded() external view returns (bool);

  function getLockedCollateralEthValue(
    uint256 id
  ) external view returns (uint256);

  function getMaxSpendableEth(uint256 id) external view returns (uint256);

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

