// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import { BaseWrapper } from "./BaseWrapper.sol";
import { IChainlinkWrapper } from "./IChainlinkWrapper.sol";

import { VestaMath } from "./VestaMath.sol";
import { OracleAnswer } from "./OracleModels.sol";
import "./ChainlinksModels.sol";

import { AggregatorV2V3Interface } from "./AggregatorV2V3Interface.sol";
import { FlagsInterface } from "./FlagsInterface.sol";

contract ChainlinkWrapper is BaseWrapper, IChainlinkWrapper {
	AggregatorV2V3Interface internal sequencerUptimeFeed;

	mapping(address => Aggregators) private aggregators;

	function setUp(address _sequencerUptimeFeed)
		external
		onlyContract(_sequencerUptimeFeed)
		initializer
	{
		__BASE_VESTA_INIT();
		sequencerUptimeFeed = AggregatorV2V3Interface(_sequencerUptimeFeed);
	}

	function addOracle(
		address _token,
		address _priceAggregator,
		address _indexAggregator
	) external onlyOwner onlyContract(_priceAggregator) {
		if (_indexAggregator != address(0) && !isContract(_indexAggregator)) {
			revert InvalidContract();
		}

		aggregators[_token] = Aggregators(_priceAggregator, _indexAggregator);

		(ChainlinkWrappedReponse memory currentResponse, ) = _getResponses(
			_priceAggregator,
			false
		);

		(ChainlinkWrappedReponse memory currentResponseIndex, ) = _getResponses(
			_indexAggregator,
			true
		);

		if (_isBadOracleResponse(currentResponse)) {
			revert ResponseFromOracleIsInvalid(_token, _priceAggregator);
		}

		if (_isBadOracleResponse(currentResponseIndex)) {
			revert ResponseFromOracleIsInvalid(_token, _indexAggregator);
		}

		emit OracleAdded(_token, _priceAggregator, _indexAggregator);
	}

	function getPrice(address _token)
		public
		view
		override
		returns (OracleAnswer memory answer_)
	{
		Aggregators memory tokenAggregators = aggregators[_token];

		if (tokenAggregators.price == address(0)) {
			revert TokenIsNotRegistered(_token);
		}

		(
			ChainlinkWrappedReponse memory currentResponse,
			ChainlinkWrappedReponse memory previousResponse
		) = _getResponses(tokenAggregators.price, false);

		(
			ChainlinkWrappedReponse memory currentResponseIndex,
			ChainlinkWrappedReponse memory previousResponseIndex
		) = _getResponses(tokenAggregators.index, true);

		if (
			_isBadOracleResponse(currentResponse) ||
			_isBadOracleResponse(currentResponseIndex)
		) {
			return answer_;
		}

		answer_.currentPrice = _sanitizePrice(
			currentResponse.answer,
			currentResponseIndex.answer
		);

		answer_.lastPrice = _sanitizePrice(
			previousResponse.answer,
			previousResponseIndex.answer
		);

		answer_.lastUpdate = currentResponse.timestamp;

		return answer_;
	}

	function _getResponses(address _aggregator, bool _isIndex)
		internal
		view
		returns (
			ChainlinkWrappedReponse memory currentResponse_,
			ChainlinkWrappedReponse memory lastResponse_
		)
	{
		if (_aggregator == address(0) && _isIndex) {
			currentResponse_ = ChainlinkWrappedReponse(1, 18, 1 ether, block.timestamp);
			lastResponse_ = currentResponse_;
		} else {
			currentResponse_ = _getCurrentChainlinkResponse(
				AggregatorV2V3Interface(_aggregator)
			);
			lastResponse_ = _getPrevChainlinkResponse(
				AggregatorV2V3Interface(_aggregator),
				currentResponse_.roundId,
				currentResponse_.decimals
			);
		}

		return (currentResponse_, lastResponse_);
	}

	function _getCurrentChainlinkResponse(AggregatorV2V3Interface _aggregator)
		internal
		view
		returns (ChainlinkWrappedReponse memory oracleResponse_)
	{
		if (!_isSequencerUp()) {
			return oracleResponse_;
		}

		try _aggregator.decimals() returns (uint8 decimals) {
			if (decimals == 0) return oracleResponse_;

			oracleResponse_.decimals = decimals;
		} catch {
			return oracleResponse_;
		}

		try _aggregator.latestRoundData() returns (
			uint80 roundId,
			int256 answer,
			uint256, /* startedAt */
			uint256 timestamp,
			uint80 /* answeredInRound */
		) {
			oracleResponse_.roundId = roundId;
			oracleResponse_.answer = scalePriceByDigits(
				uint256(answer),
				oracleResponse_.decimals
			);
			oracleResponse_.timestamp = timestamp;
		} catch {}

		return oracleResponse_;
	}

	function _getPrevChainlinkResponse(
		AggregatorV2V3Interface _aggregator,
		uint80 _currentRoundId,
		uint8 _currentDecimals
	) internal view returns (ChainlinkWrappedReponse memory prevOracleResponse_) {
		if (_currentRoundId == 0) {
			return prevOracleResponse_;
		}

		try _aggregator.getRoundData(_currentRoundId - 1) returns (
			uint80 roundId,
			int256 answer,
			uint256, /* startedAt */
			uint256 timestamp,
			uint80 /* answeredInRound */
		) {
			if (answer == 0) return prevOracleResponse_;

			prevOracleResponse_.roundId = roundId;
			prevOracleResponse_.answer = scalePriceByDigits(
				uint256(answer),
				_currentDecimals
			);
			prevOracleResponse_.timestamp = timestamp;
			prevOracleResponse_.decimals = _currentDecimals;
		} catch {}

		return prevOracleResponse_;
	}

	function _sanitizePrice(uint256 price, uint256 index)
		internal
		pure
		returns (uint256)
	{
		return VestaMath.mulDiv(price, index, 1e18);
	}

	function _isBadOracleResponse(ChainlinkWrappedReponse memory _answer)
		internal
		view
		returns (bool)
	{
		return (_answer.answer == 0 ||
			_answer.roundId == 0 ||
			_answer.timestamp > block.timestamp ||
			_answer.timestamp == 0 ||
			!_isSequencerUp());
	}

	function _isSequencerUp() internal view returns (bool sequencerIsUp) {
		(, int256 answer, , uint256 updatedAt, ) = sequencerUptimeFeed.latestRoundData();

		return (answer == 0 && (block.timestamp - updatedAt) < 3600);
	}

	function removeOracle(address _token) external onlyOwner {
		delete aggregators[_token];
		emit OracleRemoved(_token);
	}

	function getAggregators(address _token)
		external
		view
		override
		returns (Aggregators memory)
	{
		return aggregators[_token];
	}
}

