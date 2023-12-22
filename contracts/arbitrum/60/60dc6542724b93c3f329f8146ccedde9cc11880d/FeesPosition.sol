// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {FeeCalculation} from "./FeeCalculation.sol";
import {Math} from "./Math.sol";

struct FeesPosition {
  uint256 long0FeeGrowth;
  uint256 long1FeeGrowth;
  uint256 shortFeeGrowth;
  uint256 shortReturnedGrowth;
  uint256 long0Fees;
  uint256 long1Fees;
  uint256 shortFees;
  uint256 shortReturned;
}

/// @title library for calulating the fees earned
library FeesPositionLibrary {
  /// @dev returns the fees earned and short returned for a given position, liquidity and respective fee growths
  function feesEarnedAndShortReturnedOf(
    FeesPosition memory feesPosition,
    uint160 liquidity,
    uint256 long0FeeGrowth,
    uint256 long1FeeGrowth,
    uint256 shortFeeGrowth,
    uint256 shortReturnedGrowth
  ) internal pure returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees, uint256 shortReturned) {
    long0Fees = feesPosition.long0Fees + FeeCalculation.getFees(liquidity, feesPosition.long0FeeGrowth, long0FeeGrowth);
    long1Fees = feesPosition.long1Fees + FeeCalculation.getFees(liquidity, feesPosition.long1FeeGrowth, long1FeeGrowth);
    shortFees = feesPosition.shortFees + FeeCalculation.getFees(liquidity, feesPosition.shortFeeGrowth, shortFeeGrowth);
    shortReturned =
      feesPosition.shortReturned +
      FeeCalculation.getFees(liquidity, feesPosition.shortReturnedGrowth, shortReturnedGrowth);
  }

  /// @dev update fee for a given position, liquidity and respective feeGrowth
  function update(
    FeesPosition storage feesPosition,
    uint160 liquidity,
    uint256 long0FeeGrowth,
    uint256 long1FeeGrowth,
    uint256 shortFeeGrowth,
    uint256 shortReturnedGrowth
  ) internal {
    if (liquidity != 0) {
      feesPosition.long0Fees += FeeCalculation.getFees(liquidity, feesPosition.long0FeeGrowth, long0FeeGrowth);
      feesPosition.long1Fees += FeeCalculation.getFees(liquidity, feesPosition.long1FeeGrowth, long1FeeGrowth);
      feesPosition.shortFees += FeeCalculation.getFees(liquidity, feesPosition.shortFeeGrowth, shortFeeGrowth);
      feesPosition.shortReturned += FeeCalculation.getFees(
        liquidity,
        feesPosition.shortReturnedGrowth,
        shortReturnedGrowth
      );
    }

    feesPosition.long0FeeGrowth = long0FeeGrowth;
    feesPosition.long1FeeGrowth = long1FeeGrowth;
    feesPosition.shortFeeGrowth = shortFeeGrowth;
    feesPosition.shortReturnedGrowth = shortReturnedGrowth;
  }

  /// @dev get the fees and short returned given the position
  function getFeesAndShortReturned(
    FeesPosition storage feesPosition,
    uint256 long0FeesDesired,
    uint256 long1FeesDesired,
    uint256 shortFeesDesired,
    uint256 shortReturnedDesired
  ) internal view returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees, uint256 shortReturned) {
    long0Fees = Math.min(feesPosition.long0Fees, long0FeesDesired);
    long1Fees = Math.min(feesPosition.long1Fees, long1FeesDesired);
    shortFees = Math.min(feesPosition.shortFees, shortFeesDesired);
    shortReturned = Math.min(feesPosition.shortReturned, shortReturnedDesired);
  }

  /// @dev remove fees and short returned from the position
  function burn(
    FeesPosition storage feesPosition,
    uint256 long0Fees,
    uint256 long1Fees,
    uint256 shortFees,
    uint256 shortReturned
  ) internal {
    feesPosition.long0Fees -= long0Fees;
    feesPosition.long1Fees -= long1Fees;
    feesPosition.shortFees -= shortFees;
    feesPosition.shortReturned -= shortReturned;
  }
}

