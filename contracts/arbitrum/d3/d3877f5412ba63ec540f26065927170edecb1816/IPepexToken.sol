// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./IERC20.sol";

interface IPepexToken is IERC20 {
	function mint(uint256 _amount) external returns (bool);
	function mintFor(address _address, uint256 _amount) external returns (bool); 
	function safePepexTransfer(address _to, uint256 _amount) external;
}

