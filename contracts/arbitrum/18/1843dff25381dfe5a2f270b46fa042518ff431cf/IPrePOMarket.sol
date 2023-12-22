// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.7;

import {ICollateral} from "./ICollateral.sol";
import {IERC20, ILongShortToken} from "./ILongShortToken.sol";
import {IAddressBeacon} from "./IAddressBeacon.sol";
import {IUintBeacon} from "./IUintBeacon.sol";

interface IPrePOMarket {
  struct MarketParameters {
    address collateral;
    uint256 floorLongPayout;
    uint256 ceilingLongPayout;
    uint256 expiryLongPayout;
    uint256 floorValuation;
    uint256 ceilingValuation;
    uint256 expiryTime;
  }

  struct Permit {
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  event AddressBeaconChange(address beacon);
  event FinalLongPayoutSet(uint256 payout);
  event Mint(
    address indexed funder,
    address indexed recipient,
    uint256 amountAfterFee,
    uint256 fee
  );
  event Redemption(
    address indexed funder,
    address indexed recipient,
    uint256 amountAfterFee,
    uint256 fee
  );
  event UintBeaconChange(address beacon);

  error CeilingNotAboveFloor();
  error CeilingTooHigh();
  error ExpiryInPast();
  error ExpiryNotPassed();
  error FeePercentTooHigh();
  error FeeRoundsToZero();
  error FinalPayoutTooHigh();
  error FinalPayoutTooLow();
  error InsufficientCollateral();
  error InsufficientLongToken();
  error InsufficientShortToken();
  error MarketEnded();
  error UnequalRedemption();
  error ZeroCollateralAmount();

  function mint(
    uint256 amount,
    address recipient,
    bytes calldata data
  ) external returns (uint256);

  function permitAndMint(
    Permit calldata permit,
    uint256 collateralAmount,
    address recipient,
    bytes calldata data
  ) external returns (uint256);

  function redeem(
    uint256 longAmount,
    uint256 shortAmount,
    address recipient,
    bytes calldata data
  ) external;

  function setFinalLongPayout(uint256 finalLongPayout) external;

  function setFinalLongPayoutAfterExpiry() external;

  function getLongToken() external view returns (ILongShortToken);

  function getShortToken() external view returns (ILongShortToken);

  function getAddressBeacon() external view returns (IAddressBeacon);

  function getUintBeacon() external view returns (IUintBeacon);

  function getCollateral() external view returns (ICollateral);

  function getFloorLongPayout() external view returns (uint256);

  function getCeilingLongPayout() external view returns (uint256);

  function getExpiryLongPayout() external view returns (uint256);

  function getFinalLongPayout() external view returns (uint256);

  function getFloorValuation() external view returns (uint256);

  function getCeilingValuation() external view returns (uint256);

  function getExpiryTime() external view returns (uint256);

  function getFeePercent(bytes32 feeKey) external view returns (uint256);

  function PERCENT_UNIT() external view returns (uint256);

  function FEE_LIMIT() external view returns (uint256);

  function SET_FINAL_LONG_PAYOUT_ROLE() external view returns (bytes32);

  function MINT_HOOK_KEY() external view returns (bytes32);

  function REDEEM_HOOK_KEY() external view returns (bytes32);

  function MINT_FEE_PERCENT_KEY() external view returns (bytes32);

  function REDEEM_FEE_PERCENT_KEY() external view returns (bytes32);
}

