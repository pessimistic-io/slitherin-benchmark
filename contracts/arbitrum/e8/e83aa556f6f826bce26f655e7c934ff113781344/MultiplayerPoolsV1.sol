// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {ERC20, IERC20} from "./ERC20.sol";

import {Ownable} from "./Ownable.sol";

import {Strings} from "./Strings.sol";

import {ECDSA} from "./ECDSA.sol";

import {IMultiplayerPoolsV1} from "./IMultiplayerPoolsV1.sol";

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

contract MultiplayerPoolsV1 is IMultiplayerPoolsV1, Ownable {
	using ECDSA for bytes32;

	/**
	 * Errors
	 */

	error PoolNotFinished();
	error EntriesFinished();
	error PoolIsSettled();
	error TooManyBets();
	error BetUnderMinBet();
	error PoolNotSetup();
	error InvalidToken();
	error EntryDurationLimits();
	error PoolDurationLimits();
	error EntryDurationOverPoolDuration();
	error MinBetTooLow();
	error AggregatorNotWhitelisted();
	error CallerNotSettler();
	error AggregatorNotUpdated();
	error PoolCreationFee();
	error SettlementPriceNotSet();
	error SignatureDeadline();

	/**
	 * Events
	 */

	event PoolCreated(
		uint256 indexed poolId,
		bytes20 indexed token,
		SourceType indexed sourceType,
		uint256 minBet,
		uint256 entryEndTime,
		uint256 poolEndTime,
		uint256 timestamp
	);

	event UserJoined(uint256 indexed poolId, address indexed user, BetDirection direction, uint256 bet, uint256 timestamp);

	event PoolSettled(
		uint256 indexed poolId,
		BetDirection winDirection,
		uint256 winDirectionBetValue,
		uint256 loseDirectionBetValue,
		uint256 timestamp
	);

	/**
	 * Constants
	 */

	address private constant TREASURY = 0x9D7fE9Fd062B0a2acAf413975853f44462F2B7dE;
	address private constant SETTLER = 0x9D7fE9Fd062B0a2acAf413975853f44462F2B7dE;
	address private constant SIGNER = 0xa0aaA83042a7F964eAc69ED40e6E1fFe395d56d9;

	uint256 private constant MAX_BETS = 250;

	uint256 private constant MIN_POOL_DURATION = 45 minutes;
	uint256 private constant MAX_POOL_DURATION = 365 days;

	uint256 private constant MIN_ENTRY_DURATION = 15 minutes;

	/* The settler has 1 hour to settle the pool, otherwise anyone can if it's not a YoyoApi source type pool */
	uint256 private constant SETTLE_DURATION = 1 hours;

	uint256 private constant FORCE_SETTLE_DELAY = 1 days;

	uint256 private constant INITIAL_POOL_CREATION_FEE = 0.002 ether;

	uint256 private constant BPS = 10_000;

	uint256 private constant INITIAL_FEE = (BPS * 5) / 100;

	uint256 private constant MIN_BET = 0.001 ether;

	uint256 private constant ADDRESS_MASK = uint256(type(uint160).max) << 96;

	/**
	 * Storage
	 */

	mapping(bytes20 => mapping(address => bool)) private _tokenToAggregatorToWhitelisted;

	mapping(uint256 => PoolStorage) private _poolsStorage;

	uint256 private _poolId = 0;

	uint256 private _feeBps = INITIAL_FEE;

	uint256 private _poolCreationFee = INITIAL_POOL_CREATION_FEE;

	/**
	 * Non-View Functions
	 */

	function createNewPool(
		bytes20 token,
		SourceType sourceType,
		bytes32 sourceAdditionalData,
		uint88 minBet,
		uint80 entryDuration,
		uint80 poolDuration,
		uint256 startingPrice,
		uint256 deadline,
		Signature calldata signature,
		BetDirection direction
	) external payable {
		if (msg.sender != tx.origin) revert();
		uint256 poolCreationFee = _poolCreationFee;
		if (msg.value < poolCreationFee || msg.value - poolCreationFee < minBet) revert PoolCreationFee();

		if (sourceType == SourceType.ChainlinkAggregatorV3) {
			if (_tokenToAggregatorToWhitelisted[token][address(bytes20(sourceAdditionalData))] == false) {
				revert AggregatorNotWhitelisted();
			}
		} else {
			// if (sourceType == SourceType.YoyoApi)
			if (startingPrice == 0 || startingPrice > type(uint88).max) revert();
			if (deadline < block.timestamp) revert SignatureDeadline();

			bytes32 hash = keccak256(abi.encodePacked(token, startingPrice, deadline));
			if (hash.toEthSignedMessageHash().recover(signature.v, signature.r, signature.s) != SIGNER) revert();
		}

		if (minBet < MIN_BET) revert MinBetTooLow();
		if (entryDuration > poolDuration) revert EntryDurationOverPoolDuration();
		if (poolDuration < MIN_POOL_DURATION || poolDuration > MAX_POOL_DURATION) revert PoolDurationLimits();
		if (entryDuration < MIN_ENTRY_DURATION) revert EntryDurationLimits();
		if (token == bytes20(0)) revert InvalidToken();

		uint256 poolId;
		unchecked {
			poolId = ++_poolId;
		}

		PoolStorage storage _poolStorage = _poolsStorage[poolId];
		PoolConfig storage _poolConfig = _poolStorage.poolConfig;

		_poolConfig.token = token;
		_poolConfig.minBet = minBet;

		if (uint8(sourceType) != 0) _poolConfig.sourceType = sourceType;
		if (sourceAdditionalData != 0) _poolConfig.sourceAdditionalData = sourceAdditionalData;

		_poolConfig.entryEndTime = uint80(block.timestamp) + entryDuration;
		_poolConfig.poolEndTime = uint80(block.timestamp) + poolDuration;

		_poolStorage.bets.push(Bet({direction: direction, value: uint88(msg.value - poolCreationFee), user: msg.sender}));
		_poolStorage.betDirectionToValue[uint8(direction)] = msg.value - poolCreationFee;

		if (sourceType == SourceType.ChainlinkAggregatorV3) {
			uint80 roundId;
			(startingPrice, roundId) = _fetchAggregatorData(sourceAdditionalData);

			if (startingPrice == 0 || startingPrice > type(uint88).max) revert();
			_poolConfig.startingPrice = uint88(startingPrice);
			/* Mask out the address (top 160 bits) and add the roundId at the lower 80 bits */
			_poolConfig.sourceAdditionalData = bytes32(
				(uint256(_poolConfig.sourceAdditionalData) & (ADDRESS_MASK)) + uint256(roundId)
			);
		} else {
			// if (sourceType == SourceType.YoyoApi)
			_poolConfig.startingPrice = uint88(startingPrice);
		}

		emit PoolCreated(
			poolId,
			token,
			sourceType,
			minBet,
			block.timestamp + entryDuration,
			block.timestamp + poolDuration,
			block.timestamp
		);

		emit UserJoined(poolId, msg.sender, direction, msg.value - poolCreationFee, block.timestamp);

		_handleRemainingEth(poolCreationFee);
	}

	function enter(uint256 poolId, BetDirection direction) external payable {
		if (msg.sender != tx.origin) revert();

		PoolStorage storage _poolStorage = _poolsStorage[poolId];
		PoolConfig storage _poolConfig = _poolStorage.poolConfig;

		if (block.timestamp > _poolConfig.entryEndTime) revert EntriesFinished();
		if (msg.value < _poolConfig.minBet) revert BetUnderMinBet();

		if (_poolStorage.bets.length >= MAX_BETS) revert TooManyBets();

		_poolStorage.bets.push(Bet({user: msg.sender, value: uint88(msg.value), direction: direction}));

		_poolStorage.betDirectionToValue[uint256(direction)] += msg.value;

		emit UserJoined(poolId, msg.sender, direction, msg.value, block.timestamp);
	}

	function settle(uint256 poolId, uint256 settlementPrice) external {
		if (msg.sender != tx.origin) revert();

		PoolStorage storage _poolStorage = _poolsStorage[poolId];
		PoolConfig storage _poolConfig = _poolStorage.poolConfig;

		if (_poolStorage.settled == true) revert PoolIsSettled();
		if (block.timestamp < _poolConfig.poolEndTime) revert PoolNotFinished();

		if (_poolConfig.sourceType == SourceType.ChainlinkAggregatorV3) {
			if (settlementPrice != 0) revert();

			if (msg.sender != SETTLER && block.timestamp < _poolConfig.poolEndTime + SETTLE_DURATION) revert CallerNotSettler();

			(uint256 price, uint80 roundId) = _fetchAggregatorData(_poolConfig.sourceAdditionalData);
			if (price == 0 || uint80(uint256(_poolConfig.sourceAdditionalData)) == roundId) revert AggregatorNotUpdated();

			_poolStorage.settlementPrice = price;
			_settle(poolId);
		} else {
			// if (sourceType == SourceType.YoyoApi)
			if (settlementPrice == 0) revert();

			if (msg.sender != SETTLER) revert CallerNotSettler();

			_poolStorage.settlementPrice = settlementPrice;
			_settle(poolId);
		}
	}

	/**
	 * View Functions
	 */

	function getPoolConfig(uint256 poolId) external view returns (PoolConfig memory poolConfig) {
		return _poolsStorage[poolId].poolConfig;
	}

	function getPools(uint256 pageSize, uint256 page) external view returns (PoolData[] memory) {
		return _getPoolsFromEnd(pageSize, page);
	}

	function isAggregatorWhitelisted(bytes20 token, address aggregator) external view returns (bool) {
		return _tokenToAggregatorToWhitelisted[token][aggregator];
	}

	/**
	 * Owner Only Functions
	 */

	function setPoolCreationFee(uint256 poolCreationFee) external onlyOwner {
		_poolCreationFee = poolCreationFee;
	}

	function setFee(uint256 feeBps) external onlyOwner {
		if (feeBps > INITIAL_FEE) revert();
		_feeBps = feeBps;
	}

	function setAggregators(
		bytes20[] calldata tokens,
		address[] calldata aggregators,
		bool[] calldata allowed
	) external onlyOwner {
		if (tokens.length != aggregators.length || aggregators.length != allowed.length) revert();

		uint256 len = tokens.length;

		for (uint256 i = 0; i < len; ) {
			_tokenToAggregatorToWhitelisted[tokens[i]][aggregators[i]] = allowed[i];

			unchecked {
				++i;
			}
		}
	}

	function forceSettle(uint256 poolId, uint256 settlementPrice) external onlyOwner {
		if (block.timestamp < _poolsStorage[poolId].poolConfig.poolEndTime + FORCE_SETTLE_DELAY) revert();

		_poolsStorage[poolId].settlementPrice = settlementPrice;
		_settle(poolId);
	}

	/**
	 * Internal functions
	 */

	function _settle(uint256 poolId) internal {
		PoolStorage storage _poolStorage = _poolsStorage[poolId];
		PoolConfig storage _poolConfig = _poolStorage.poolConfig;
		Bet[] storage _bets = _poolStorage.bets;

		if (_poolStorage.settled == true) revert PoolIsSettled();
		if (block.timestamp < _poolConfig.poolEndTime) revert PoolNotFinished();
		if (_poolStorage.settlementPrice == 0) revert SettlementPriceNotSet();

		_poolStorage.settled = true;

		BetDirection winDirection = _poolStorage.settlementPrice > _poolConfig.startingPrice
			? BetDirection.Up
			: BetDirection.Down;

		uint256 totalWinBetValue;
		uint256 totalLoseBetValue;

		if (winDirection == BetDirection.Up) {
			totalWinBetValue = _poolStorage.betDirectionToValue[uint256(BetDirection.Up)];
			totalLoseBetValue = _poolStorage.betDirectionToValue[uint256(BetDirection.Down)];
		} else {
			totalWinBetValue = _poolStorage.betDirectionToValue[uint256(BetDirection.Down)];
			totalLoseBetValue = _poolStorage.betDirectionToValue[uint256(BetDirection.Up)];
		}

		emit PoolSettled(poolId, winDirection, totalWinBetValue, totalLoseBetValue, block.timestamp);

		if (totalWinBetValue == 0) {
			// Only Losers/No Bets
			_handleRemainingEth(totalLoseBetValue);
			return;
		}

		if (totalLoseBetValue == 0) {
			// Only winners
			_refundBets(_bets, totalWinBetValue);
			return;
		}

		uint256 balanceBefore = address(this).balance;

		uint256 len = _bets.length;

		for (uint256 i = 0; i < len; ) {
			Bet memory bet = _bets[i];
			if (bet.direction == winDirection) {
				(bool success, ) = bet.user.call{
					value: ((bet.value + ((bet.value * totalLoseBetValue) / totalWinBetValue)) * (BPS - _feeBps)) / BPS,
					gas: 2300
				}('');
				success;
			}

			unchecked {
				++i;
			}
		}

		/* (Starting pool value - total amount transferred) == (fees + failed transfers) */
		_handleRemainingEth((totalWinBetValue + totalLoseBetValue) - (balanceBefore - address(this).balance));
	}

	function _fetchAggregatorData(bytes32 sourceAdditionalData) internal view returns (uint256 price, uint80 roundId) {
		(uint80 _roundId, int256 _price, , , ) = AggregatorV3Interface(address(bytes20(sourceAdditionalData))).latestRoundData();
		return (uint256(_price), _roundId);
	}

	function _handleRemainingEth(uint256 amount) internal {
		if (amount > 0) {
			(bool success, ) = TREASURY.call{value: amount}('');
			if (!success) revert();
		}
	}

	function _refundBets(Bet[] storage _bets, uint256 totalValue) internal {
		uint256 balanceBefore = address(this).balance;

		uint256 len = _bets.length;

		for (uint256 i = 0; i < len; ) {
			Bet memory bet = _bets[i];

			(bool success, ) = bet.user.call{value: bet.value, gas: 2300}('');
			success;

			unchecked {
				++i;
			}
		}

		/* (Starting pool value - total amount transferred) */
		_handleRemainingEth(totalValue - (balanceBefore - address(this).balance));
	}

	function _getPoolsFromEnd(uint256 pageSize, uint256 page) internal view returns (PoolData[] memory) {
		uint256 len = _poolId;
		if (pageSize == 0 || pageSize * page >= len) {
			return new PoolData[](0);
		}

		uint256 numElements = _min(pageSize, len - pageSize * page);

		PoolData[] memory pools = new PoolData[](numElements);

		for (uint256 i = 0; i < numElements; ) {
			uint256 poolId = len - (i + page * pageSize);
			PoolStorage storage _poolStorage = _poolsStorage[poolId];

			pools[i] = PoolData({
				poolId: poolId,
				betCount: _poolStorage.bets.length,
				upBetValue: _poolStorage.betDirectionToValue[uint256(BetDirection.Up)],
				downBetValue: _poolStorage.betDirectionToValue[uint256(BetDirection.Down)],
				poolConfig: _poolStorage.poolConfig,
				settled: _poolStorage.settled,
				settlementPrice: _poolStorage.settlementPrice
			});

			unchecked {
				++i;
			}
		}

		return pools;
	}

	function _min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}
}

