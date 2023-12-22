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
  uint256 public constant version = 1_000_000;

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
   * @param _baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
   * @param _multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
   * @param _jumpMultiplierPerYear1 The multiplierPerBlock after hitting a specified utilization point
   * @param _kink1 The utilization point at which the jump multiplier is applied
   */
  constructor(
    uint256 _baseRatePerYear,
    uint256 _multiplierPerYear,
    uint256 _jumpMultiplierPerYear1,
    uint256 _jumpMultiplierPerYear2,
    uint256 _kink1,
    uint256 _kink2
  ) {
    _updateJumpRateModel(
      _baseRatePerYear,
      _multiplierPerYear,
      _jumpMultiplierPerYear1,
      _jumpMultiplierPerYear2,
      _kink1,
      _kink2
    );
  }
}

