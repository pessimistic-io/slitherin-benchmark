// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

struct ChainlinkWrappedReponse {
	uint80 roundId;
	uint8 decimals;
	uint256 answer;
	uint256 timestamp;
}

struct Aggregators {
	address price;
	address index;
}

