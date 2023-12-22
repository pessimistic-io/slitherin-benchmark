// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

interface IOracleMaster {
	function queryInfo(address token_) external view returns (uint256);
}

