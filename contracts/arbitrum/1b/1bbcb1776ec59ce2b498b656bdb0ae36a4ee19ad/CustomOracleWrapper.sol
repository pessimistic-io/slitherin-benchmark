// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.7;

import { BaseWrapper } from "./BaseWrapper.sol";
import { ICustomOracleWrapper } from "./ICustomOracleWrapper.sol";

import { OracleAnswer } from "./OracleModels.sol";
import "./CustomOracleModels.sol";

import { AddressCalls } from "./AddressCalls.sol";
import { VestaMath } from "./VestaMath.sol";

contract CustomOracleWrapper is BaseWrapper, ICustomOracleWrapper {
	mapping(address => CustomOracle) private oracles;

	function setUp() external initializer {
		__BASE_VESTA_INIT();
	}

	function getPrice(address _token)
		external
		view
		override
		returns (OracleAnswer memory answer_)
	{
		CustomOracle memory oracle = oracles[_token];
		if (oracle.contractAddress == address(0)) {
			revert TokenIsNotRegistered(_token);
		}

		uint8 decimals = _getDecimals(
			oracle.contractAddress,
			oracle.callDecimals,
			oracle.decimals
		);

		answer_.lastUpdate = _getLastUpdate(
			oracle.contractAddress,
			oracle.callLastUpdate
		);

		answer_.currentPrice = scalePriceByDigits(
			_getPrice(oracle.contractAddress, oracle.callCurrentPrice),
			decimals
		);

		uint256 lastPrice = _getPrice(oracle.contractAddress, oracle.callLastPrice);

		answer_.lastPrice = (lastPrice == 0)
			? answer_.currentPrice
			: scalePriceByDigits(lastPrice, decimals);

		return answer_;
	}

	function _getDecimals(
		address _contractAddress,
		bytes memory _callData,
		uint8 _default
	) internal view returns (uint8) {
		(uint8 response, bool success) = AddressCalls.callReturnsUint8(
			_contractAddress,
			_callData
		);

		return success ? response : _default;
	}

	function _getPrice(address _contractAddress, bytes memory _callData)
		internal
		view
		returns (uint256)
	{
		(uint256 response, bool success) = AddressCalls.callReturnsUint256(
			_contractAddress,
			_callData
		);

		return success ? response : 0;
	}

	function _getLastUpdate(address _contractAddress, bytes memory _callData)
		internal
		view
		returns (uint256)
	{
		(uint256 response, bool success) = AddressCalls.callReturnsUint256(
			_contractAddress,
			_callData
		);

		return success ? response : block.timestamp;
	}

	function addOracle(
		address _token,
		address _externalOracle,
		uint8 _decimals,
		bytes memory _callCurrentPrice,
		bytes memory _callLastPrice,
		bytes memory _callLastUpdate,
		bytes memory _callDecimals
	) external onlyOwner onlyContract(_externalOracle) notZero(_decimals) {
		oracles[_token] = CustomOracle(
			_externalOracle,
			_decimals,
			_callCurrentPrice,
			_callLastPrice,
			_callLastUpdate,
			_callDecimals
		);

		if (_getPrice(_externalOracle, _callCurrentPrice) == 0) {
			revert ResponseFromOracleIsInvalid(_token, _externalOracle);
		}

		emit OracleAdded(_token, _externalOracle);
	}

	function removeOracle(address _token) external onlyOwner {
		delete oracles[_token];

		emit OracleRemoved(_token);
	}

	function getOracle(address _token)
		external
		view
		override
		returns (CustomOracle memory)
	{
		return oracles[_token];
	}
}

