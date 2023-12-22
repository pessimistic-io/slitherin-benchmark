// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

struct Snapshots {
	mapping(address => uint256) S; // asset address -> S value
	uint256 P;
	mapping(address => uint256) G; // asset address -> G value
	uint128 scale;
	uint128 epoch;
}


