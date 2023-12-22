// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

struct Lock {
	//chunk
	address user;
	bool autoLock;
	uint128 lockDay;
	//chunk
	uint128 claimed;
	uint128 end;
	//chunk
	uint128 initialAmount;
	uint128 cappedShare;
	uint256 lastTimeClaimed;
}


