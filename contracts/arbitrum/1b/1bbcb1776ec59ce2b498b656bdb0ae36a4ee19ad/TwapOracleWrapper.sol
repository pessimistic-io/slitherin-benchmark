pragma solidity ^0.8.7;

import { BaseWrapper } from "./BaseWrapper.sol";
import { ITwapOracleWrapper } from "./ITwapOracleWrapper.sol";

import { OracleLibrary } from "./OracleLibrary.sol";
import { VestaMath } from "./VestaMath.sol";
import { OracleAnswer } from "./OracleModels.sol";

import { AggregatorV2V3Interface } from "./AggregatorV2V3Interface.sol";
import { FlagsInterface } from "./FlagsInterface.sol";

contract TwapOracleWrapper is BaseWrapper, ITwapOracleWrapper {
	uint8 public constant ethDecimals = 8;

	address public weth;
	AggregatorV2V3Interface public sequencerUptimeFeed;
	AggregatorV2V3Interface public ethChainlinkAggregator;

	uint32 public twapPeriodInSeconds;

	mapping(address => address) internal pools;

	function setUp(
		address _weth,
		address _ethChainlinkAggregator,
		address _sequencerUptimeFeed
	)
		external
		initializer
		onlyContract(_weth)
		onlyContracts(_ethChainlinkAggregator, _sequencerUptimeFeed)
	{
		__BASE_VESTA_INIT();

		weth = _weth;
		ethChainlinkAggregator = AggregatorV2V3Interface(_ethChainlinkAggregator);
		sequencerUptimeFeed = AggregatorV2V3Interface(_sequencerUptimeFeed);
		twapPeriodInSeconds = 1800;
	}

	function getPrice(address _token)
		external
		view
		override
		returns (OracleAnswer memory answer_)
	{
		try this.getTokenPriceInETH(_token, twapPeriodInSeconds) returns (
			uint256 priceInETH
		) {
			uint256 ethPriceInUSD = getETHPrice();
			uint256 tokenPrice = VestaMath.mulDiv(priceInETH, ethPriceInUSD, 1e18);

			if (tokenPrice == 0) return answer_;

			answer_.currentPrice = tokenPrice;
			answer_.lastPrice = tokenPrice;
			answer_.lastUpdate = block.timestamp;
		} catch {}

		return answer_;
	}

	function getTokenPriceInETH(address _token, uint32 _twapPeriod)
		external
		view
		override
		notZero(_twapPeriod)
		returns (uint256)
	{
		address v3Pool = pools[_token];
		if (v3Pool == address(0)) revert TokenIsNotRegistered(_token);

		(int24 arithmeticMeanTick, ) = OracleLibrary.consult(v3Pool, _twapPeriod);
		return OracleLibrary.getQuoteAtTick(arithmeticMeanTick, 1e18, _token, weth);
	}

	function getETHPrice() public view override returns (uint256) {
		if (!_isSequencerUp()) {
			return 0;
		}

		try ethChainlinkAggregator.latestAnswer() returns (int256 price) {
			if (price <= 0) return 0;
			return scalePriceByDigits(uint256(price), ethDecimals);
		} catch {
			return 0;
		}
	}

	function _isSequencerUp() internal view returns (bool sequencerIsUp) {
		(, int256 answer, , uint256 updatedAt, ) = sequencerUptimeFeed.latestRoundData();

		// Answer -> 0: Sequencer is up  |  1: Sequencer is down
		return (answer == 0 && (block.timestamp - updatedAt) < 3600);
	}

	function changeTwapPeriod(uint32 _timeInSecond)
		external
		notZero(_timeInSecond)
		onlyOwner
	{
		twapPeriodInSeconds = _timeInSecond;

		emit TwapChanged(_timeInSecond);
	}

	function addOracle(address _token, address _pool)
		external
		onlyContract(_pool)
		onlyOwner
	{
		pools[_token] = _pool;

		if (this.getPrice(_token).currentPrice == 0) {
			revert UniswapFailedToGetPrice();
		}

		emit OracleAdded(_token, _pool);
	}

	function removeOracle(address _token) external onlyOwner {
		delete pools[_token];

		emit OracleRemoved(_token);
	}

	function getPool(address _token) external view returns (address) {
		return pools[_token];
	}
}

