pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {IInterestRateModel} from "./IInterestRateModel.sol";

contract JumpRateInterestModel is Ownable, IInterestRateModel {
    uint256 constant PRECISION = 1e10;
    /// @notice default rate on anycase
    uint256 public baseRate;
    /// @notice the rate of increase interest rate by utilization (scaled by 1e10)
    uint256 public baseMultiplierPerInterval;
    /// @notice the multiplier after hitting a specified point
    uint256 public jumpMultiplierPerInterval;
    /// @notice the utilization point at which jump multipler is applied (scaled by 1e10)
    uint256 public kink;

    constructor(
        uint256 _baseRate,
        uint256 _baseMultiplierPerInterval,
        uint256 _jumpMultiplierPerInterval,
        uint256 _kink
    ) {
        _setParams(_baseRate, _baseMultiplierPerInterval, _jumpMultiplierPerInterval, _kink);
    }

    function getBorrowRatePerInterval(uint256 _totalCash, uint256 _reserved) external view returns (uint256) {
        uint256 util = _reserved * PRECISION / _totalCash;
        if (util < kink) {
            return baseRate + baseMultiplierPerInterval * util / PRECISION;
        }
        uint256 normalRate = baseRate + baseMultiplierPerInterval * kink / PRECISION;
        uint256 exessRate = (util - kink) * jumpMultiplierPerInterval / PRECISION;
        return normalRate + exessRate;
    }

    function update(
        uint256 _baseRate,
        uint256 _baseMultiplierPerInterval,
        uint256 _jumpMultiplierPerInterval,
        uint256 _kink
    ) external onlyOwner {
        _setParams(_baseRate, _baseMultiplierPerInterval, _jumpMultiplierPerInterval, _kink);
    }

    function _setParams(
        uint256 _baseRate,
        uint256 _baseMultiplierPerInterval,
        uint256 _jumpMultiplierPerInterval,
        uint256 _kink
    ) internal {
        baseRate = _baseRate;
        baseMultiplierPerInterval = _baseMultiplierPerInterval;
        jumpMultiplierPerInterval = _jumpMultiplierPerInterval;
        kink = _kink;

        emit NewParams(_baseRate, _baseMultiplierPerInterval, _jumpMultiplierPerInterval, _kink);
    }

    event NewParams(
        uint256 baseRate, uint256 baseMultiplierPerInterval, uint256 jumpMultiplierPerInterval, uint256 kink
    );
}

