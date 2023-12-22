// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

struct Snapshots {
	mapping(address => uint256) S;
	uint256 P;
	uint128 scale;
	uint128 epoch;
}


