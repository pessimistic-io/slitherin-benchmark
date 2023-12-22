//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "./BaseDoubleJumpRateModel.sol";

/**
 * @title   Interest rate model with two rate kinks
 * @author  Honey Labs Inc.
 * @custom:coauthor     BowTiedPickle
 * @custom:contributor  m4rio
 */
contract DoubleJumpRateModel is BaseDoubleJumpRateModel {
  /// @notice this corresponds to 1.0.0
  uint256 public constant version = 1_000_001;

  /**
   * @notice Calculates the current borrow rate per block
   * @param _cash The amount of cash in the market
   * @param _borrows The amount of borrows in the market
   * @param _reserves The amount of reserves in the market
   * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getBorrowRate(uint256 _cash, uint256 _borrows, uint256 _reserves) external view override returns (uint256) {
    return getBorrowRateInternal(_cash, _borrows, _reserves);
  }

  /**
   * @notice Construct an interest rate model
   * @param baseRatePerYear_ The approximate target base APR, as a mantissa (scaled by 1e18)
   * @param multiplierPerYear_ The rate of increase in interest rate wrt utilization (scaled by 1e18)
   * @param jumpMultiplierPerYear1_ The _jumpMultiplierPerYear1 after hitting a specified utilization point
   * @param jumpMultiplierPerYear2_ The _jumpMultiplierPerYear2 after hitting a specified utilization point
   * @param kink1_ The utilization point at which the jump multiplier 1 is applied
   * @param kink2_ The utilization point at which the jump multiplier 2 is applied
   * @param blocksPerYear_ Approximation of blocks per year based on the chain's block time
   */
  constructor(
    uint256 baseRatePerYear_,
    uint256 multiplierPerYear_,
    uint256 jumpMultiplierPerYear1_,
    uint256 jumpMultiplierPerYear2_,
    uint256 kink1_,
    uint256 kink2_,
    uint256 blocksPerYear_
  ) BaseDoubleJumpRateModel(blocksPerYear_) {
    govUpdateJumpRateModel(
      baseRatePerYear_,
      multiplierPerYear_,
      jumpMultiplierPerYear1_,
      jumpMultiplierPerYear2_,
      kink1_,
      kink2_
    );
  }
}

