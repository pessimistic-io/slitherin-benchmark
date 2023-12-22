// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./IERC20.sol";
import { DisbursementCliff } from "./DisbursementCliff.sol";

contract VestingVoter is Ownable {
	mapping(address => address) public voters;
	address public sect;
	uint256 public constant MAXTIME = 730 days;

	constructor(address _sect) {
		sect = _sect;
	}

	function setVoters(address[] memory account, address[] memory vestingContract)
		public
		onlyOwner
	{
		require(
			account.length == vestingContract.length,
			"Voters and VestedVoters must be the same length"
		);
		for (uint256 i = 0; i < account.length; i++) {
			voters[account[i]] = vestingContract[i];
			emit SetVoter(account[i], vestingContract[i]);
		}
	}

	function balanceOf(address user) public view returns (uint256) {
		DisbursementCliff vestingContract = DisbursementCliff(voters[user]);
		if (address(vestingContract) == address(0)) return 0;
		uint256 endDate = vestingContract.startDate() + vestingContract.disbursementPeriod();
		if (block.timestamp >= endDate) return 0;
		uint256 vestPeriod = endDate - block.timestamp;
		uint256 balance = IERC20(sect).balanceOf(address(vestingContract));
		return (balance * vestPeriod) / MAXTIME;
	}

	event SetVoter(address indexed account, address indexed vestingContract);
}

