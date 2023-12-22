// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

contract AcePoker is ERC20, Ownable {
    using SafeERC20 for IERC20;
	uint256 public constant MAX_SUPPLY = 1e8 * 1e18;


    constructor(address _vesting)  ERC20("ACE Poker", "ACE") {

		require(_vesting != address(0), "Vesting address can not be 0");

		 _mint(_vesting, MAX_SUPPLY);

	}

   
    function renounceOwnership() public override onlyOwner {
        revert("can't renounceOwnership"); 
    }
}
