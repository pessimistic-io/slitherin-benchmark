// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./FundingFee.sol";
import "./Constants.sol";

/* ========== STRUCTS ========== */
/**
 * @notice Struct to store the fee integral values
 * @custom:member longFundingFeeIntegral long funding fee gets paid to short positions
 * @custom:member shortFundingFeeIntegral short funding fee gets paid to long positions
 * @custom:member fundingFeeRate max rate of funding fee
 * @custom:member maxExcessRatio max ratio of long to short positions at which funding fees are capped. Denominated in FEE_MULTIPLIER
 * @custom:member borrowFeeIntegral borrow fee gets paid to the liquidity pools
 * @custom:member borrowFeeRate Rate of borrow fee, measured in fee basis points (FEE_BPS_MULTIPLIER) per hour
 * @custom:member lastUpdatedAt last time fee integral was updated
 */
struct FeeIntegral {
    int256 longFundingFeeIntegral;
    int256 shortFundingFeeIntegral;
    int256 fundingFeeRate;
    int256 maxExcessRatio;
    int256 borrowFeeIntegral;
    int256 borrowFeeRate;
    uint256 lastUpdatedAt;
}

/**
 * @title FeeIntegral
 * @notice Provides data structures and functions for calculating the fee integrals
 * @dev This contract is a library and should be used by a contract that implements the ITradePair interface
 */
library FeeIntegralLib {
    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice update fee integrals
     * @dev Update needs to happen before volumes change.
     */
    function update(FeeIntegral storage _self, uint256 longVolume, uint256 shortVolume) external {
        // Update integrals for the period since last update
        uint256 elapsedTime = block.timestamp - _self.lastUpdatedAt;
        if (elapsedTime > 0) {
            _self._updateBorrowFeeIntegral();
            _self._updateFundingFeeIntegrals(longVolume, shortVolume);
        }
        _self.lastUpdatedAt = block.timestamp;
    }

    /**
     * @notice get current funding fee integrals
     * @param longVolume long position volume
     * @param shortVolume short position volume
     * @return longFundingFeeIntegral long funding fee integral
     * @return shortFundingFeeIntegral short funding fee integral
     */
    function getCurrentFundingFeeIntegrals(FeeIntegral storage _self, uint256 longVolume, uint256 shortVolume)
        external
        view
        returns (int256, int256)
    {
        (int256 elapsedLongIntegral, int256 elapsedShortIntegral) =
            _self._getElapsedFundingFeeIntegrals(longVolume, shortVolume);
        int256 longIntegral = _self.longFundingFeeIntegral + elapsedLongIntegral;
        int256 shortIntegral = _self.shortFundingFeeIntegral + elapsedShortIntegral;
        return (longIntegral, shortIntegral);
    }

    /**
     * @notice get current borrow fee integral
     * @dev calculated by stored integral + elapsed integral
     * @return borrowFeeIntegral current borrow fee integral
     */
    function getCurrentBorrowFeeIntegral(FeeIntegral storage _self) external view returns (int256) {
        return _self.borrowFeeIntegral + _self._getElapsedBorrowFeeIntegral();
    }

    /**
     * @notice get the borrow fee integral since last update
     * @return borrowFeeIntegral borrow fee integral since last update
     */
    function getElapsedBorrowFeeIntegral(FeeIntegral storage _self) external view returns (int256) {
        return _self._getElapsedBorrowFeeIntegral();
    }

    /**
     * @notice Calculates the current funding fee rates
     * @param longVolume long position volume
     * @param shortVolume short position volume
     * @return longFundingFeeRate long funding fee rate
     * @return shortFundingFeeRate short funding fee rate
     */
    function getCurrentFundingFeeRates(FeeIntegral storage _self, uint256 longVolume, uint256 shortVolume)
        external
        view
        returns (int256, int256)
    {
        return FundingFee.getFundingFeeRates({
            longVolume: longVolume,
            shortVolume: shortVolume,
            maxRatio: _self.maxExcessRatio,
            maxFeeRate: _self.fundingFeeRate
        });
    }

    /**
     * ========== INTERNAL FUNCTIONS ==========
     */

    /**
     * @notice update the integral of borrow fee calculated since last update
     */
    function _updateBorrowFeeIntegral(FeeIntegral storage _self) internal {
        _self.borrowFeeIntegral += _self._getElapsedBorrowFeeIntegral();
    }

    /**
     * @notice get the borrow fee integral since last update
     * @return borrowFeeIntegral borrow fee integral since last update
     */
    function _getElapsedBorrowFeeIntegral(FeeIntegral storage _self) internal view returns (int256) {
        uint256 elapsedTime = block.timestamp - _self.lastUpdatedAt;
        return (int256(elapsedTime) * _self.borrowFeeRate) / 1 hours;
    }

    /**
     * @notice update the integrals of funding fee calculated since last update
     * @dev the integrals can be negative, when one side pays the other.
     * longVolume and shortVolume can also be sizes, the ratio is important.
     * @param longVolume volume of long positions
     * @param shortVolume volume of short positions
     */
    function _updateFundingFeeIntegrals(FeeIntegral storage _self, uint256 longVolume, uint256 shortVolume) internal {
        (int256 elapsedLongIntegral, int256 elapsedShortIntegral) =
            _self._getElapsedFundingFeeIntegrals(longVolume, shortVolume);
        _self.longFundingFeeIntegral += elapsedLongIntegral;
        _self.shortFundingFeeIntegral += elapsedShortIntegral;
    }

    /**
     * @notice get the integral of funding fee calculated since last update
     * @dev the integrals can be negative, when one side pays the other.
     * longVolume and shortVolume can also be sizes, the ratio is important.
     * @param longVolume volume of long positions
     * @param shortVolume volume of short positions
     * @return elapsedLongIntegral integral of long funding fee
     * @return elapsedShortIntegral integral of short funding fee
     */
    function _getElapsedFundingFeeIntegrals(FeeIntegral storage _self, uint256 longVolume, uint256 shortVolume)
        internal
        view
        returns (int256, int256)
    {
        (int256 longFee, int256 shortFee) = FundingFee.getFundingFeeRates({
            longVolume: longVolume,
            shortVolume: shortVolume,
            maxRatio: _self.maxExcessRatio,
            maxFeeRate: _self.fundingFeeRate
        });
        uint256 elapsedTime = block.timestamp - _self.lastUpdatedAt;
        int256 longIntegral = (longFee * int256(elapsedTime)) / 1 hours;
        int256 shortIntegral = (shortFee * int256(elapsedTime)) / 1 hours;
        return (longIntegral, shortIntegral);
    }
}

using FeeIntegralLib for FeeIntegral;

