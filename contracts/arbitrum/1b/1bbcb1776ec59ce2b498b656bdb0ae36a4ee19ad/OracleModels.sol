// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.6.0;

struct OracleAnswer {
	uint256 currentPrice;
	uint256 lastPrice;
	uint256 lastUpdate;
}

struct Oracle {
	address primaryWrapper;
	address secondaryWrapper;
	bool disabled;
}

