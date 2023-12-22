// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import "./IERC20.sol";

interface IAToken is IERC20 {
	/**
	 * @dev Returns the address of the underlying asset of this aToken (E.g. WETH for aWETH)
	 **/
	function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
