// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

import "./IGLPManager.sol";
import "./Errors.sol";

import { TokenUtils } from "./TokenUtils.sol";

contract Oracle {
	/// @notice The scalar used for conversion of integral numbers to fixed point numbers.
	uint256 public constant FIXED_POINT_SCALAR = 1e18;

	address public immutable glp;

	address public immutable manager;

	constructor(address _glp, address _manager) {
		glp = _glp;
		manager = _manager;
	}

	function getPrice() external view returns (uint256) {
		uint256 _aum = IGLPManager(manager).getAumInUsdg(false);
		uint256 _glpSupply = TokenUtils.safeTotalSupply(glp);
		uint256 _price = (_aum * FIXED_POINT_SCALAR) / _glpSupply;

		return _price;
	}
}

