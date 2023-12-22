// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Math} from "./Math.sol";

import {FeeCalculation} from "./FeeCalculation.sol";

/// @param liquidity The amount of liquidity owned.
/// @param long0FeeGrowth The long0 position fee growth stored when the user entered the positions.
/// @param long1FeeGrowth The long1 position fee growth stored when the user entered the positions.
/// @param shortFeeGrowth The short position fee growth stored when the user entered the positions.
/// @param long0Fees The stored amount of long0 position fees owned.
/// @param long1Fees The stored amount of long1 position fees owned.
/// @param shortFees The stored amount of short position fees owned.
struct LiquidityPosition {
  uint160 liquidity;
  uint256 long0FeeGrowth;
  uint256 long1FeeGrowth;
  uint256 shortFeeGrowth;
  uint256 long0Fees;
  uint256 long1Fees;
  uint256 shortFees;
}

/// @title library for liquidity position utils
/// @author Timeswap Labs
library LiquidityPositionLibrary {
  using Math for uint256;

  /// @dev Get the total fees earned by the owner.
  /// @param liquidityPosition The liquidity position of the owner.
  /// @param long0FeeGrowth The current global long0 position fee growth to be compared.
  /// @param long1FeeGrowth The current global long1 position fee growth to be compared.
  /// @param shortFeeGrowth The current global short position fee growth to be compared.
  function feesEarnedOf(
    LiquidityPosition memory liquidityPosition,
    uint256 long0FeeGrowth,
    uint256 long1FeeGrowth,
    uint256 shortFeeGrowth
  ) internal pure returns (uint256 long0Fee, uint256 long1Fee, uint256 shortFee) {
    uint160 liquidity = liquidityPosition.liquidity;

    long0Fee = liquidityPosition.long0Fees.unsafeAdd(
      FeeCalculation.getFees(liquidity, liquidityPosition.long0FeeGrowth, long0FeeGrowth)
    );
    long1Fee = liquidityPosition.long1Fees.unsafeAdd(
      FeeCalculation.getFees(liquidity, liquidityPosition.long1FeeGrowth, long1FeeGrowth)
    );
    shortFee = liquidityPosition.shortFees.unsafeAdd(
      FeeCalculation.getFees(liquidity, liquidityPosition.shortFeeGrowth, shortFeeGrowth)
    );
  }

  /// @dev Update the liquidity position after mint and/or burn functions.
  /// @param liquidityPosition The liquidity position of the owner.
  /// @param long0FeeGrowth The current global long0 position fee growth to be compared.
  /// @param long1FeeGrowth The current global long1 position fee growth to be compared.
  /// @param shortFeeGrowth The current global short position fee growth to be compared.
  function update(
    LiquidityPosition storage liquidityPosition,
    uint256 long0FeeGrowth,
    uint256 long1FeeGrowth,
    uint256 shortFeeGrowth
  ) internal {
    uint160 liquidity = liquidityPosition.liquidity;

    if (liquidity != 0) {
      liquidityPosition.long0Fees += FeeCalculation.getFees(
        liquidity,
        liquidityPosition.long0FeeGrowth,
        long0FeeGrowth
      );
      liquidityPosition.long1Fees += FeeCalculation.getFees(
        liquidity,
        liquidityPosition.long1FeeGrowth,
        long1FeeGrowth
      );
      liquidityPosition.shortFees += FeeCalculation.getFees(
        liquidity,
        liquidityPosition.shortFeeGrowth,
        shortFeeGrowth
      );
    }

    liquidityPosition.long0FeeGrowth = long0FeeGrowth;
    liquidityPosition.long1FeeGrowth = long1FeeGrowth;
    liquidityPosition.shortFeeGrowth = shortFeeGrowth;
  }

  /// @dev updates the liquidity position by the given amount
  /// @param liquidityPosition the position that is to be updated
  /// @param liquidityAmount the amount that is to be incremented in the position
  function mint(LiquidityPosition storage liquidityPosition, uint160 liquidityAmount) internal {
    liquidityPosition.liquidity += liquidityAmount;
  }

  /// @dev updates the fess in the liquidity position
  /// @param liquidityPosition the position that is to be updated
  /// @param long0Fees the long0Fees increment in the liquidityPosition
  /// @param long1Fees the long1Fees increment in the liquidityPosition
  /// @param shortFees the shortFees increment in the liquidityPosition
  function mintFees(
    LiquidityPosition storage liquidityPosition,
    uint256 long0Fees,
    uint256 long1Fees,
    uint256 shortFees
  ) internal {
    liquidityPosition.long0Fees += long0Fees;
    liquidityPosition.long1Fees += long1Fees;
    liquidityPosition.shortFees += shortFees;
  }

  /// @dev updates the liquidity position by the given amount
  /// @param liquidityPosition the position that is to be updated
  /// @param liquidityAmount the amount that is to be decremented in the position
  function burn(LiquidityPosition storage liquidityPosition, uint160 liquidityAmount) internal {
    liquidityPosition.liquidity -= liquidityAmount;
  }

  /// @dev updates the fess in the liquidity position
  /// @dev updates the fess in the liquidity position
  /// @param liquidityPosition the position that is to be updated
  /// @param long0Fees the long0Fees decrement in the liquidityPosition
  /// @param long1Fees the long1Fees decrement in the liquidityPosition
  /// @param shortFees the shortFees decrement in the liquidityPosition
  function burnFees(
    LiquidityPosition storage liquidityPosition,
    uint256 long0Fees,
    uint256 long1Fees,
    uint256 shortFees
  ) internal {
    liquidityPosition.long0Fees -= long0Fees;
    liquidityPosition.long1Fees -= long1Fees;
    liquidityPosition.shortFees -= shortFees;
  }

  /// @dev function to collect the transaction fees accrued for a given liquidity position
  /// @param liquidityPosition the liquidity position that whose fees is collected
  /// @param long0Requested the long0Fees requested
  /// @param long1Requested the long1Fees requested
  /// @param shortRequested the shortFees requested
  function collectTransactionFees(
    LiquidityPosition storage liquidityPosition,
    uint256 long0Requested,
    uint256 long1Requested,
    uint256 shortRequested
  ) internal returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees) {
    if (long0Requested >= liquidityPosition.long0Fees) {
      long0Fees = liquidityPosition.long0Fees;
      liquidityPosition.long0Fees = 0;
    } else {
      long0Fees = long0Requested;
      liquidityPosition.long0Fees = liquidityPosition.long0Fees.unsafeSub(long0Requested);
    }

    if (long1Requested >= liquidityPosition.long1Fees) {
      long1Fees = liquidityPosition.long1Fees;
      liquidityPosition.long1Fees = 0;
    } else {
      long1Fees = long1Requested;
      liquidityPosition.long1Fees = liquidityPosition.long1Fees.unsafeSub(long1Requested);
    }

    if (shortRequested >= liquidityPosition.shortFees) {
      shortFees = liquidityPosition.shortFees;
      liquidityPosition.shortFees = 0;
    } else {
      shortFees = shortRequested;
      liquidityPosition.shortFees = liquidityPosition.shortFees.unsafeSub(shortRequested);
    }
  }
}

