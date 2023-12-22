//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./FixedPointMathLib.sol";

import "./IContangoView.sol";
import "./IFeeModel.sol";

uint256 constant MAX_YEARLY_FEE = 5e18; // 500%
uint256 constant MIN_YEARLY_FEE = 0.05e18; // 5%
uint256 constant HOURS_PER_YEAR = 365 * 24;
uint256 constant MAX_GRACE_PERIOD = 4 weeks;

contract PenaltyModel is IFeeModel {
    using FixedPointMathLib for uint256;

    error AboveMaxFee(uint256 hourlyFee);
    error BelowMinFee(uint256 hourlyFee);
    error AboveMaxGracePeriod(uint256 gracePeriod);

    IFeeModel public immutable delegate;
    IContangoView public immutable contango;
    uint256 public immutable hourlyFee; // percentage in wad, e.g. 0.0015e18 -> 0.15%
    uint256 public immutable gracePeriod;

    constructor(IFeeModel _delegate, IContangoView _contango, uint256 yearlyFee, uint256 _gracePeriod) {
        if (yearlyFee > MAX_YEARLY_FEE) revert AboveMaxFee(yearlyFee);
        if (yearlyFee < MIN_YEARLY_FEE) revert BelowMinFee(yearlyFee);
        if (_gracePeriod > MAX_GRACE_PERIOD) revert AboveMaxGracePeriod(_gracePeriod);

        hourlyFee = yearlyFee / HOURS_PER_YEAR;

        delegate = _delegate;
        contango = _contango;
        gracePeriod = _gracePeriod / 1 hours;
    }

    /// @inheritdoc IFeeModel
    function calculateFee(address trader, PositionId positionId, uint256 cost)
        external
        view
        override
        returns (uint256 calculatedFee)
    {
        calculatedFee = delegate.calculateFee(trader, positionId, cost);

        uint256 positionMaturity = contango.position(positionId).maturity;

        uint256 hoursSinceExpiry =
            block.timestamp > positionMaturity ? (block.timestamp - positionMaturity) / 1 hours : 0; // solhint-disable-line not-rely-on-time

        if (hoursSinceExpiry > gracePeriod) {
            calculatedFee += cost.mulWadUp(hourlyFee) * (hoursSinceExpiry - gracePeriod);
        }
    }
}

