// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

struct CustomOracle {
	address contractAddress;
	uint8 decimals;
	bytes callCurrentPrice;
	bytes callLastPrice;
	bytes callLastUpdate;
	bytes callDecimals;
}

