// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;
import "./IPSYParameters.sol";

interface IPSYBase {
	event VaultParametersBaseChanged(address indexed newAddress);

	function psyParams() external view returns (IPSYParameters);
}

