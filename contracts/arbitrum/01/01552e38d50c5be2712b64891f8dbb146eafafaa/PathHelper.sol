// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

library PathHelper {
	function tokenIn(address[] memory _path) internal pure returns (address) {
		return _path[0];
	}

	function tokenOut(address[] memory _path) internal pure returns (address) {
		return _path[_path.length - 1];
	}

	function isSinglePath(address[] memory _path) internal pure returns (bool) {
		return _path.length == 2;
	}
}


