// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

struct CompactedParameters {
	uint192 mintCap;
	uint64 stabilityPoolLiquidationRatio;
	uint64 stabilityPoolLiquidationBonus;
	uint64 borrowingFeeFloor;
	uint64 borrowingMaxFloor;
	uint64 redemptionFeeFloor;
	bool lockable;
	bool riskable;
}

