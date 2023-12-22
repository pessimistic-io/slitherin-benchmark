//SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4;

/**
 * @title   Modified Compound's InterestRateModel Interface
 * @author  Honey Labs Inc.
 * @custom:coauthor BowTiedPickle
 * @custom:contributor m4rio
 */
interface InterestRateModelI {
  /**
   * @notice Calculates the current borrow rate per block
   * @param _cash The amount of cash in the market
   * @param _borrows The amount of borrows in the market
   * @param _reserves The amount of reserves in the market
   * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getBorrowRate(
    uint256 _cash,
    uint256 _borrows,
    uint256 _reserves
  ) external view returns (uint256);

  /**
   * @notice Calculates the current supply rate per block
   * @param _cash The amount of cash in the market
   * @param _borrows The amount of borrows in the market
   * @param _reserves The amount of reserves in the market
   * @param _reserveFactorMantissa The current reserve factor for the market
   * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getSupplyRate(
    uint256 _cash,
    uint256 _borrows,
    uint256 _reserves,
    uint256 _reserveFactorMantissa
  ) external view returns (uint256);

  /**
   * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
   * @param _cash The amount of cash in the market
   * @param _borrows The amount of borrows in the market
   * @param _reserves The amount of reserves in the market
   * @return The utilization rate as a mantissa between [0, 1e18]
   */
  function utilizationRate(
    uint256 _cash,
    uint256 _borrows,
    uint256 _reserves
  ) external pure returns (uint256);

  /**
   *
   * @param _interfaceId The interface identifier, as specified in ERC-165
   */
  function supportsInterface(bytes4 _interfaceId) external view returns (bool);
}

