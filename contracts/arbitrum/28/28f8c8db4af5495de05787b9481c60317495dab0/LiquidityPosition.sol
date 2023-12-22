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
  uint256 shortReturnedGrowth;
  uint256 long0Fees;
  uint256 long1Fees;
  uint256 shortFees;
  uint256 shortReturned;
}

/// @title library for liquidity position utils
/// @author Timeswap Labs
library LiquidityPositionLibrary {
  using Math for uint256;

  /// @dev Get the total fees earned and short returned by the owner.
  /// @param liquidityPosition The liquidity position of the owner.
  /// @param long0FeeGrowth The current global long0 position fee growth to be compared.
  /// @param long1FeeGrowth The current global long1 position fee growth to be compared.
  /// @param shortFeeGrowth The current global short position fee growth to be compared.
  /// @param shortReturnedGrowth The current glocal short position returned growth to be compared
  /// @return long0Fees The long0 fees owned.
  /// @return long1Fees The long1 fees owned.
  /// @return shortFees The short fees owned.
  /// @return shortReturned The short returned owned.
  function feesEarnedAndShortReturnedOf(
    LiquidityPosition memory liquidityPosition,
    uint256 long0FeeGrowth,
    uint256 long1FeeGrowth,
    uint256 shortFeeGrowth,
    uint256 shortReturnedGrowth
  ) internal pure returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees, uint256 shortReturned) {
    uint160 liquidity = liquidityPosition.liquidity;

    long0Fees = liquidityPosition.long0Fees.unsafeAdd(
      FeeCalculation.getFees(liquidity, liquidityPosition.long0FeeGrowth, long0FeeGrowth)
    );
    long1Fees = liquidityPosition.long1Fees.unsafeAdd(
      FeeCalculation.getFees(liquidity, liquidityPosition.long1FeeGrowth, long1FeeGrowth)
    );
    shortFees = liquidityPosition.shortFees.unsafeAdd(
      FeeCalculation.getFees(liquidity, liquidityPosition.shortFeeGrowth, shortFeeGrowth)
    );
    shortReturned = liquidityPosition.shortReturned.unsafeAdd(
      FeeCalculation.getFees(liquidityPosition.liquidity, liquidityPosition.shortReturnedGrowth, shortReturnedGrowth)
    );
  }

  /// @dev Update the liquidity position after collectTransactionFees, mint and/or burn functions.
  /// @param liquidityPosition The liquidity position of the owner.
  /// @param long0FeeGrowth The current global long0 position fee growth to be compared.
  /// @param long1FeeGrowth The current global long1 position fee growth to be compared.
  /// @param shortFeeGrowth The current global short position fee growth to be compared.
  /// @param shortReturnedGrowth The current global short position returned growth to be compared.
  function update(
    LiquidityPosition storage liquidityPosition,
    uint256 long0FeeGrowth,
    uint256 long1FeeGrowth,
    uint256 shortFeeGrowth,
    uint256 shortReturnedGrowth
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
      liquidityPosition.shortReturned += FeeCalculation.getFees(
        liquidity,
        liquidityPosition.shortReturnedGrowth,
        shortReturnedGrowth
      );
    }

    liquidityPosition.long0FeeGrowth = long0FeeGrowth;
    liquidityPosition.long1FeeGrowth = long1FeeGrowth;
    liquidityPosition.shortFeeGrowth = shortFeeGrowth;
    liquidityPosition.shortReturnedGrowth = shortReturnedGrowth;
  }

  /// @dev updates the liquidity position by the given amount
  /// @param liquidityPosition the position that is to be updated
  /// @param liquidityAmount the amount that is to be incremented in the position
  function mint(LiquidityPosition storage liquidityPosition, uint160 liquidityAmount) internal {
    liquidityPosition.liquidity += liquidityAmount;
  }

  /// @dev updates the liquidity position by the given amount
  /// @param liquidityPosition the position that is to be updated
  /// @param liquidityAmount the amount that is to be decremented in the position
  function burn(LiquidityPosition storage liquidityPosition, uint160 liquidityAmount) internal {
    liquidityPosition.liquidity -= liquidityAmount;
  }

  /// @dev function to collect the transaction fees accrued for a given liquidity position
  /// @param liquidityPosition the liquidity position that whose fees is collected
  /// @param long0FeesRequested the long0 fees requested
  /// @param long1FeesRequested the long1 fees requested
  /// @param shortFeesRequested the short fees requested
  /// @param shortReturnedRequested the short returned requested
  /// @return long0Fees the long0 fees collected
  /// @return long1Fees the long1 fees collected
  /// @return shortFees the short fees collected
  /// @return shortReturned the short returned collected
  function collectTransactionFeesAndShortReturned(
    LiquidityPosition storage liquidityPosition,
    uint256 long0FeesRequested,
    uint256 long1FeesRequested,
    uint256 shortFeesRequested,
    uint256 shortReturnedRequested
  ) internal returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees, uint256 shortReturned) {
    if (long0FeesRequested >= liquidityPosition.long0Fees) {
      long0Fees = liquidityPosition.long0Fees;
      liquidityPosition.long0Fees = 0;
    } else {
      long0Fees = long0FeesRequested;
      liquidityPosition.long0Fees = liquidityPosition.long0Fees.unsafeSub(long0FeesRequested);
    }

    if (long1FeesRequested >= liquidityPosition.long1Fees) {
      long1Fees = liquidityPosition.long1Fees;
      liquidityPosition.long1Fees = 0;
    } else {
      long1Fees = long1FeesRequested;
      liquidityPosition.long1Fees = liquidityPosition.long1Fees.unsafeSub(long1FeesRequested);
    }

    if (shortFeesRequested >= liquidityPosition.shortFees) {
      shortFees = liquidityPosition.shortFees;
      liquidityPosition.shortFees = 0;
    } else {
      shortFees = shortFeesRequested;
      liquidityPosition.shortFees = liquidityPosition.shortFees.unsafeSub(shortFeesRequested);
    }

    if (shortReturnedRequested >= liquidityPosition.shortReturned) {
      shortReturned = liquidityPosition.shortReturned;
      liquidityPosition.shortReturned = 0;
    } else {
      shortReturned = shortReturnedRequested;
      liquidityPosition.shortReturned = liquidityPosition.shortReturned.unsafeSub(shortReturnedRequested);
    }
  }
}

