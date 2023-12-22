// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import { BaseVesta } from "./BaseVesta.sol";
import { IOracleWrapper } from "./IOracleWrapper.sol";

abstract contract BaseWrapper is BaseVesta, IOracleWrapper {
	uint256 public constant TARGET_DIGITS = 18;

	function scalePriceByDigits(uint256 _price, uint256 _answerDigits)
		internal
		pure
		returns (uint256)
	{
		return
			_answerDigits < TARGET_DIGITS
				? _price * (10**(TARGET_DIGITS - _answerDigits))
				: _price / (10**(_answerDigits - TARGET_DIGITS));
	}
}

