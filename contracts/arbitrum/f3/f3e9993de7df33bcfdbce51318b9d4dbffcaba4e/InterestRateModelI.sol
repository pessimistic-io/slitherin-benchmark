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
   * @param cash_ The amount of cash in the market
   * @param borrows_ The amount of borrows in the market
   * @param reserves_ The amount of reserves in the market
   * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getBorrowRate(uint256 cash_, uint256 borrows_, uint256 reserves_) external view returns (uint256);

  /**
   * @notice Calculates the current supply rate per block
   * @param cash_ The amount of cash in the market
   * @param borrows_ The amount of borrows in the market
   * @param reserves_ The amount of reserves in the market
   * @param reserveFactorMantissa_ The current reserve factor for the market
   * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getSupplyRate(
    uint256 cash_,
    uint256 borrows_,
    uint256 reserves_,
    uint256 reserveFactorMantissa_
  ) external view returns (uint256);

  /**
   * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
   * @param cash_ The amount of cash in the market
   * @param borrows_ The amount of borrows in the market
   * @param reserves_ The amount of reserves in the market
   * @return The utilization rate as a mantissa between [0, 1e18]
   */
  function utilizationRate(uint256 cash_, uint256 borrows_, uint256 reserves_) external pure returns (uint256);

  /**
   *
   * @param interfaceId_ The interface identifier, as specified in ERC-165
   */
  function supportsInterface(bytes4 interfaceId_) external view returns (bool);

  /*//////////////////////////////////////////////////////////////
                                GETTERS
  //////////////////////////////////////////////////////////////*/
  function baseRatePerBlock() external view returns (uint256);

  function multiplierPerBlock() external view returns (uint256);

  function jumpMultiplierPerBlock1() external view returns (uint256);

  function jumpMultiplierPerBlock2() external view returns (uint256);

  function kink1() external view returns (uint256);

  function kink2() external view returns (uint256);

  function blocksPerYear() external view returns (uint256);
}

