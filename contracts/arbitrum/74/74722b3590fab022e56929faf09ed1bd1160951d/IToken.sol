// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./IERC20.sol";

interface IToken is IERC20 {
	function mint(address _to, uint256 _amount) external;
	function burn(uint256 amount) external;
	function safeTokenTransfer(address _to, uint256 _amount) external;
}

