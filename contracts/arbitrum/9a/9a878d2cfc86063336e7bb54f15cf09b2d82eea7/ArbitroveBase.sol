// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

error IsNotWstETH();

contract ArbitroveBase {
	// address public contractOwner;
	// address public wstETH = 0x5979D7b546E38E414F7E9822514be443A4800529;
	// address public wstETH = 0x69C735ce75B3Dec7c1Cdf21306628A6eb1b81346;
	address public wstETH;

	modifier onlyWstETH(address _asset) {
		if (wstETH != _asset) {
			revert IsNotWstETH();
		}
		_;
	}

	function _isWstETH(address _asset) internal view {
		if (wstETH != _asset) {
			revert IsNotWstETH();
		}
	}
}

