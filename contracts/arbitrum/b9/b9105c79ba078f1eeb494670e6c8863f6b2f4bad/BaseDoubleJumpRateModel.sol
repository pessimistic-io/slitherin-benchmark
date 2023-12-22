//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import "./Ownable.sol";
import "./InterestRateModelI.sol";

/**
 * @title   Double Jump Rate Interest Model
 * @author  Honey Labs Inc.
 * @notice  Implements a base rate and three linear interest rate curves anchored by two kink points
 * @custom:coauthor     BowTiedPickle
 * @custom:coauthor     m4rio
 */
abstract contract BaseDoubleJumpRateModel is Ownable, InterestRateModelI {
  /**
   * @notice  The approximate number of blocks per year that is assumed by the interest rate model
   * @dev     Based on 12 second block time
   */
  uint256 public constant blocksPerYear = 2628000;

  /**
   * @notice The multiplier of utilization rate that gives the slope of the interest rate
   */
  uint256 public multiplierPerBlock;

  /**
   * @notice The base interest rate which is the y-intercept when utilization rate is 0
   */
  uint256 public baseRatePerBlock;

  /**
   * @notice The multiplierPerBlock after hitting a specified utilization point
   */
  uint256 public jumpMultiplierPerBlock1;

  /**
   * @notice The multiplierPerBlock after hitting a specified utilization point
   */
  uint256 public jumpMultiplierPerBlock2;

  /**
   * @notice The utilization point at which the 1st jump multiplier is applied
   */
  uint256 public kink1;

  /**
   * @notice The utilization point at which the 2nd jump multiplier is applied
   */
  uint256 public kink2;

  event NewInterestParams(
    uint256 _baseRatePerBlock,
    uint256 _multiplierPerBlock,
    uint256 _jumpMultiplierPerBlock1,
    uint256 _kink1,
    uint256 _kink2
  );

  /**
   * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
   * @param _cash The amount of cash in the market
   * @param _borrows The amount of borrows in the market
   * @param _reserves The amount of reserves in the market
   * @return The utilization rate as a mantissa between [0, 1e18]
   */
  function utilizationRate(uint256 _cash, uint256 _borrows, uint256 _reserves) public pure override returns (uint256) {
    // Utilization rate is 0 when there are no borrows
    if (_borrows == 0) {
      return 0;
    }

    return (_borrows * 1e18) / (_cash + _borrows - _reserves);
  }

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
  ) external view override returns (uint256) {
    uint256 oneMinusReserveFactor = uint256(1e18) - _reserveFactorMantissa;
    uint256 borrowRate = getBorrowRateInternal(_cash, _borrows, _reserves);
    uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / 1e18;
    uint256 supplyRate = (utilizationRate(_cash, _borrows, _reserves) * rateToPool) / 1e18;
    return supplyRate;
  }

  /**
   * @notice  Update the parameters of the interest rate model (only callable by owner, i.e. Timelock)
   * @dev     The sum of the rates should equal the desired APR at 100% utilization
   * @param   _baseRatePerYear          The approximate target base APR, as a mantissa (scaled by 1e18)
   * @param   _multiplierPerYear        The mantissa-formatted total additional APR applied by the first curve
   * @param   _jumpMultiplierPerYear1   The mantissa-formatted total additional APR applied by the second curve
   * @param   _jumpMultiplierPerYear2   The mantissa-formatted total additional APR applied by the third curve
   * @param   _kink1                    The utilization point at which the first jump multiplier is applied
   * @param   _kink2                    The utilization point at which the second jump multiplier is applied
   */
  function _updateJumpRateModel(
    uint256 _baseRatePerYear,
    uint256 _multiplierPerYear,
    uint256 _jumpMultiplierPerYear1,
    uint256 _jumpMultiplierPerYear2,
    uint256 _kink1,
    uint256 _kink2
  ) public onlyOwner {
    require(1e18 > _kink2 && _kink2 > _kink1 && _kink1 > 0, "Invalid kinks");
    uint256 newBaseRatePerBlock = _baseRatePerYear / blocksPerYear;
    uint256 newMultiplierPerBlock = (_multiplierPerYear * 1e18) / (blocksPerYear * _kink1);
    uint256 newjumpMultiplierPerBlock1 = (_jumpMultiplierPerYear1 * 1e18) / (blocksPerYear * (_kink2 - _kink1));
    uint256 newjumpMultiplierPerBlock2 = (_jumpMultiplierPerYear2 * 1e18) / (blocksPerYear * (1e18 - _kink2));
    baseRatePerBlock = newBaseRatePerBlock;
    multiplierPerBlock = newMultiplierPerBlock;
    jumpMultiplierPerBlock1 = newjumpMultiplierPerBlock1;
    jumpMultiplierPerBlock2 = newjumpMultiplierPerBlock2;
    kink1 = _kink1;
    kink2 = _kink2;

    emit NewInterestParams(newBaseRatePerBlock, newMultiplierPerBlock, newjumpMultiplierPerBlock1, _kink1, _kink2);
  }

  /**
   * @notice Calculates the current borrow rate per block, with the error code expected by the market
   * @param _cash The amount of cash in the market
   * @param _borrows The amount of borrows in the market
   * @param _reserves The amount of reserves in the market
   * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
   */
  function getBorrowRateInternal(uint256 _cash, uint256 _borrows, uint256 _reserves) internal view returns (uint256) {
    uint256 util = utilizationRate(_cash, _borrows, _reserves);
    uint256 cachedkink1 = kink1;
    uint256 cachedkink2 = kink2;

    if (util <= cachedkink1) {
      return ((util * multiplierPerBlock) / 1e18) + baseRatePerBlock;
    } else if (util <= cachedkink2) {
      uint256 normalRate = ((cachedkink1 * multiplierPerBlock) / 1e18) + baseRatePerBlock;
      uint256 excessUtil;
      unchecked {
        excessUtil = util - cachedkink1;
      }
      return ((excessUtil * jumpMultiplierPerBlock1) / 1e18) + normalRate;
    } else {
      uint256 normalRate = ((cachedkink1 * multiplierPerBlock) / 1e18) + baseRatePerBlock;
      uint256 kink1Rate = ((cachedkink2 - cachedkink1) * jumpMultiplierPerBlock1) / 1e18;
      uint256 excessUtil;
      unchecked {
        excessUtil = util - cachedkink2;
      }
      return ((excessUtil * jumpMultiplierPerBlock2) / 1e18) + kink1Rate + normalRate;
    }
  }

  /**
   * @notice Calculates the current borrow rate per block
   * @param _cash The amount of cash in the market
   * @param _borrows The amount of borrows in the market
   * @param _reserves The amount of reserves in the market
   */
  function getBorrowRate(
    uint256 _cash,
    uint256 _borrows,
    uint256 _reserves
  ) external view virtual override returns (uint256);

  function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
    return _interfaceId == type(InterestRateModelI).interfaceId;
  }
}

