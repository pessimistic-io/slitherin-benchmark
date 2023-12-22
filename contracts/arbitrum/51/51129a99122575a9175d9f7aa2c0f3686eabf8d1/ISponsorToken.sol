// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;
import { IERC20 } from "./IERC20.sol";

interface ISponsorToken is IERC20 {
	function core() external view returns (address);

	function mint(address user_, uint256 amount_) external;

	function burn(address user_, uint256 amount_) external;
}

