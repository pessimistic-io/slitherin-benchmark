// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library MultiplierLib {

	uint256 public constant MAX_REWARDED_PROXIMITY = 1 weeks;
	uint256 public constant MAX_POSSIBLE_RATIO = 10000;

	function calculateMultiplier(uint256 _x, uint256[] memory _xValues, uint256[] memory _yValues) internal pure returns (uint256) {
		uint256 xValuesNum = _xValues.length;
		uint256 firstBiggerIndex = xValuesNum;
		uint256 currXValue = 0;
		uint256 lastXValue = 0;
		for (uint256 i = 0; i < xValuesNum; i++) {

			if (i > 0) {
				lastXValue = currXValue;
			}
			currXValue = _xValues[i];

			if (currXValue > _x) {
				firstBiggerIndex = i;
				break;
			}
		}

		if (firstBiggerIndex == xValuesNum) {
			return _yValues[_yValues.length - 1];
		} else if (firstBiggerIndex == 0) {
			return _yValues[0];
		} else {
			return (_yValues[firstBiggerIndex] * (_x - lastXValue) + _yValues[firstBiggerIndex - 1] * (currXValue - _x)) / 
				(currXValue - lastXValue);
		}
	}

	function validateOrder(uint256[] memory _yValues, bool isAscending, bool notZero) internal pure {
		for (uint256 i = 0; i < _yValues.length - 1; i++) {
			require(!notZero || _yValues[i] > 0, "Not positive");

			if (isAscending) {
				require(_yValues[i] <= _yValues[i + 1], "Not ascending");
			} else {
				require(_yValues[i] >= _yValues[i + 1], "Not descending");
			}
		}
	}

	function validateProximity(uint256[] memory _values) internal pure {
		for (uint256 i = 0; i < _values.length; i++) {	
			require (_values[i] <= MAX_REWARDED_PROXIMITY, "Proximity domain too big");
		}
	}

	function validateRatio(uint256[] memory _values) internal pure {
		for (uint256 i = 0; i < _values.length; i++) {	
			require (_values[i] < MAX_POSSIBLE_RATIO, "Ratio domain too big");
		}
	}
}
