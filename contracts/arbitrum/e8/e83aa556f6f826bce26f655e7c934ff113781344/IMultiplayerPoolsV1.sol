// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

interface IMultiplayerPoolsV1 {
	/**
	 * Data Structures
	 */

	enum BetDirection {
		Up,
		Down
	}

	enum SourceType {
		ChainlinkAggregatorV3,
		YoyoApi
	}

	struct Bet {
		BetDirection direction;
		address user;
		uint88 value;
	}

	struct PoolConfig {
		bytes20 token;
		uint88 minBet;
		SourceType sourceType;
		uint88 startingPrice;
		uint80 entryEndTime;
		uint80 poolEndTime;
		bytes32 sourceAdditionalData;
	}

	struct PoolStorage {
		Bet[] bets;
		uint256[2] betDirectionToValue;
		PoolConfig poolConfig;
		bool settled;
		uint256 settlementPrice;
	}

	struct PoolData {
		uint256 poolId;
		uint256 betCount;
		uint256 upBetValue;
		uint256 downBetValue;
		PoolConfig poolConfig;
		bool settled;
		uint256 settlementPrice;
	}

	struct Signature {
		uint8 v;
		bytes32 r;
		bytes32 s;
	}

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
	) external payable;

	function enter(uint256 poolId, BetDirection direction) external payable;

	function settle(uint256 poolId, uint256 settlementPrice) external;

	/**
	 * View Functions
	 */

	function getPoolConfig(uint256 poolId) external view returns (PoolConfig memory poolConfig);

	function getPools(uint256 pageSize, uint256 page) external view returns (PoolData[] memory);

	function isAggregatorWhitelisted(bytes20 token, address aggregator) external view returns (bool);
}

