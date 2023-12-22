// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./BaseVesta.sol";
import "./TokenTransferrer.sol";
import "./ITrader.sol";

abstract contract BaseTrader is ITrader, BaseVesta, TokenTransferrer {
	uint16 public constant EXACT_AMOUNT_IN_CORRECTION = 3; //0.003
	uint128 public constant CORRECTION_DENOMINATOR = 100_000;

	function _validExpectingAmount(uint256 _in, uint256 _out) internal pure {
		if (_in == _out || (_in == 0 && _out == 0)) {
			revert AmountInAndOutAreZeroOrSameValue();
		}
	}
}


