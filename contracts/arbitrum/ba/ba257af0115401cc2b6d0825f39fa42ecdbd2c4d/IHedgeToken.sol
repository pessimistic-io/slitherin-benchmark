// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;
import { IERC20 } from "./IERC20.sol";

interface IHedgeToken is IERC20 {
	function core() external view returns (address);

	function index() external view returns (uint256);

	function mint(address user_, uint256 amount_) external;

	function burn(address user_, uint256 amount_) external;

	function updateIndex(uint256 idx_) external;

	function rawTotalSupply() external view returns (uint256);
}

