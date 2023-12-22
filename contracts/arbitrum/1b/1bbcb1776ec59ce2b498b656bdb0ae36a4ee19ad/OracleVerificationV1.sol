// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import "./IOracleVerificationV1.sol";
import "./TimeoutChecker.sol";
import "./VestaMath.sol";

contract OracleVerificationV1 is IOracleVerificationV1 {
	uint256 private constant MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND = 5e17; // 50%
	uint256 private constant MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES = 5e16; // 5%
	uint256 private constant TIMEOUT = 25 hours;

	function verify(uint256 _lastGoodPrice, OracleAnswer[2] calldata _oracleAnswers)
		external
		view
		override
		returns (uint256 value)
	{
		bool isPrimaryOracleBroken = _isRequestBroken(_oracleAnswers[0]);
		bool isSecondaryOracleBroken = _isRequestBroken(_oracleAnswers[1]);

		bool oraclesHaveSamePrice = _bothOraclesSimilarPrice(
			_oracleAnswers[0].currentPrice,
			_oracleAnswers[1].currentPrice
		);

		bool primaryPriceIsAboveMax = _priceChangeAboveMax(
			_oracleAnswers[0].currentPrice,
			_oracleAnswers[0].lastPrice
		);

		bool secondaryPriceIsAboveMax = _priceChangeAboveMax(
			_oracleAnswers[1].currentPrice,
			_oracleAnswers[1].lastPrice
		);

		//prettier-ignore
		if (!isPrimaryOracleBroken) {
			if (primaryPriceIsAboveMax) {
				if (isSecondaryOracleBroken || secondaryPriceIsAboveMax) {
					return _lastGoodPrice;
				}

				return _oracleAnswers[1].currentPrice;
			}
			else if(!oraclesHaveSamePrice && !secondaryPriceIsAboveMax) {
				return _lastGoodPrice;
			}
			
			return _oracleAnswers[0].currentPrice;
		}
		else if (!isSecondaryOracleBroken) {
			if (secondaryPriceIsAboveMax) {
				return _lastGoodPrice;
			}

			return _oracleAnswers[1].currentPrice;
		}

		return _lastGoodPrice;
	}

	function _isRequestBroken(OracleAnswer memory response)
		internal
		view
		returns (bool)
	{
		bool isTimeout = TimeoutChecker.isTimeout(response.lastUpdate, TIMEOUT);
		return isTimeout || response.currentPrice == 0 || response.lastPrice == 0;
	}

	function _priceChangeAboveMax(uint256 _currentResponse, uint256 _prevResponse)
		internal
		pure
		returns (bool)
	{
		if (_currentResponse == 0 && _prevResponse == 0) return false;

		uint256 minPrice = VestaMath.min(_currentResponse, _prevResponse);
		uint256 maxPrice = VestaMath.max(_currentResponse, _prevResponse);

		uint256 percentDeviation = VestaMath.mulDiv(
			(maxPrice - minPrice),
			1e18,
			maxPrice
		);

		return percentDeviation > MAX_PRICE_DEVIATION_FROM_PREVIOUS_ROUND;
	}

	function _bothOraclesSimilarPrice(
		uint256 _primaryOraclePrice,
		uint256 _secondaryOraclePrice
	) internal pure returns (bool) {
		if (_primaryOraclePrice == 0) return false;
		if (_secondaryOraclePrice == 0) return true;

		uint256 minPrice = VestaMath.min(_primaryOraclePrice, _secondaryOraclePrice);
		uint256 maxPrice = VestaMath.max(_primaryOraclePrice, _secondaryOraclePrice);

		uint256 percentPriceDifference = VestaMath.mulDiv(
			(maxPrice - minPrice),
			1e18,
			minPrice
		);

		return percentPriceDifference <= MAX_PRICE_DIFFERENCE_BETWEEN_ORACLES;
	}
}

