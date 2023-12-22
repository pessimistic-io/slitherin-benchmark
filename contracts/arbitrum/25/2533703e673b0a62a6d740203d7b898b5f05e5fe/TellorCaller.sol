// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "./ITellorCaller.sol";
import "./ITellor.sol";
import "./SafeMathUpgradeable.sol";

/*
 * This contract has a single external function that calls Tellor: getTellorCurrentValue().
 *
 * The function is called by the Vesta contract PriceFeed.sol. If any of its inner calls to Tellor revert,
 * this function will revert, and PriceFeed will catch the failure and handle it accordingly.
 *
 * The function comes from Tellor's own wrapper contract, 'UsingTellor.sol':
 * https://github.com/tellor-io/usingtellor/blob/master/contracts/UsingTellor.sol
 *
 */
contract TellorCaller is ITellorCaller {
	using SafeMathUpgradeable for uint256;

	ITellor public tellor;

	constructor(address _tellorMasterAddress) {
		tellor = ITellor(_tellorMasterAddress);
	}

	// Internal functions
	/**
	 * @dev Convert bytes to uint256
	 * @param _b bytes value to convert to uint256
	 * @return _number uint256 converted from bytes
	 */
	function _sliceUint(bytes memory _b) internal pure returns (uint256 _number) {
		for (uint256 _i = 0; _i < _b.length; _i++) {
			_number = _number * 256 + uint8(_b[_i]);
		}
	}

	/*
	 * getTellorCurrentValue(): identical to getCurrentValue() in UsingTellor.sol
	 *
	 * @dev Allows the user to get the latest value for the requestId specified
	 * @param _queryId is the requestId to look up the value for
	 * @return ifRetrieve bool true if it is able to retrieve a value, the value, and the value's timestamp
	 * @return value the value retrieved
	 * @return _timestampRetrieved the value's timestamp
	 */
	function getTellorCurrentValue(
		bytes32 _queryId
	)
		external
		view
		override
		returns (bool ifRetrieve, uint256 value, uint256 _timestampRetrieved)
	{
		uint256 _count = tellor.getNewValueCountbyQueryId(_queryId);
		uint256 _time = tellor.getTimestampbyQueryIdandIndex(_queryId, _count.sub(1));
		bytes memory _valuesBytes = tellor.retrieveData(_queryId, _time);
		uint256 _value = _sliceUint(_valuesBytes);
		if (_value > 0) return (true, _value, _time);
		return (false, 0, _time);
	}
}

