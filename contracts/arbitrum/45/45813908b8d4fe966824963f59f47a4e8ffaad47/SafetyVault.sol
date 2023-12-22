// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";

/*
SafetyVault is still in-development.
It has been deployed to start receiving interest rate
*/
contract SafetyVault is OwnableUpgradeable {
	address public vst;

	function setUp(address _vst) external initializer {
		__Ownable_init();

		vst = _vst;
	}

	function transfer(address _to, uint256 _amount) external onlyOwner {
		IERC20(vst).transfer(_to, _amount);
	}
}


