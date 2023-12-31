// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
import {ERC20Upgradeable} from "./ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

contract TestTokenInvest is OwnableUpgradeable, ERC20Upgradeable {

	function initialize(address _mintTo) external initializer {
		__Ownable_init();
		__ERC20_init('TestTokenInvest', 'TestTokenInvest');
		_mint(_mintTo, 10_000_000 ether);
	}

}

