// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.17;

import { IERC20 } from "./IERC20.sol";

interface ITournamentToken is IERC20 {
	function burn(uint256 amount) external;
	function setPauseStatus(bool status) external;
    function setWhitelistStatus(address from, address to, bool status) external;
    function initialize(uint256 initialBalance, string memory name_, string memory symbol_) external;
}
