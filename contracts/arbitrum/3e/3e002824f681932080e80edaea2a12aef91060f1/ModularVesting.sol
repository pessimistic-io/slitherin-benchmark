// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IERC20 {
	function balanceOf(address account) external view returns (uint256);

	function transfer(address recipient, uint amount) external returns (bool);
}

contract ModularVesting is Ownable, ReentrancyGuard {
	uint constant ONE_WEEK = 7 days;

	bool public vestingIsCreated;

	mapping(uint => Vesting) public vesting;

	IERC20 public token;

	address public constant investor1 =
		0xdec08cb92a506B88411da9Ba290f3694BE223c26;
	address public constant investor2 =
		0x198E18EcFdA347c6cdaa440E22b2ff89eaA2cB6f;
	address public constant investor3 =
		0x5BCf75FF702e90c889Ae5c41ee25aF364ABC77cb;
	address public constant investor4 =
		0x5b15BAa075982Ccc6Edc7C830646030757d5272d;

	// @notice                              provide full information of exact vesting
	struct Vesting {
		address owner; // The only owner can call vesting claim function
		uint claimCounter; // Currect claim number
		uint totalClaimNum; // Maximum amount of claims for this vesting
		uint nextUnlockDate; // Next date of tokens unlock
		uint tokensRemaining; // Remain amount of token
		uint tokenToUnclockPerCycle; // Amount of token can be uncloked each cycle
	}

	modifier checkLock(uint _index) {
		require(
			vesting[_index].owner == msg.sender,
			"Not an owner of this vesting"
		);
		require(
			block.timestamp > vesting[_index].nextUnlockDate,
			"Tokens are still locked"
		);
		require(vesting[_index].tokensRemaining > 0, "Nothing to claim");
		_;
	}

	constructor(IERC20 _token) {
		token = _token;
	}

	// @notice                             only contract deployer can call this method and only once
	function createVesting() external onlyOwner {
		require(!vestingIsCreated, "vesting is already created");
		vestingIsCreated = true;

		vesting[0] = Vesting(
			investor1,
			0,
			4,
			block.timestamp + ONE_WEEK,
			27_500 ether,
			6_875 ether
		);
		vesting[1] = Vesting(
			investor2,
			0,
			4,
			block.timestamp + ONE_WEEK,
			27_500 ether,
			6_875 ether
		);
		vesting[2] = Vesting(
			investor3,
			0,
			4,
			block.timestamp + ONE_WEEK,
			27_500 ether,
			6_875 ether
		);
		vesting[3] = Vesting(
			investor4,
			0,
			4,
			block.timestamp + ONE_WEEK,
			27_500 ether,
			6_875 ether
		);

		token.transfer(investor1, 6_875 ether);
		token.transfer(investor2, 6_875 ether);
		token.transfer(investor3, 6_875 ether);
		token.transfer(investor4, 6_875 ether);
	}

	// @notice                             please use _index from table below
	//
	// 0 - investor1
	// 1 - investor2
	// 2 - investor3
	// 3 - investor4

	function claim(uint256 _index) public checkLock(_index) nonReentrant {
		if (vesting[_index].claimCounter + 1 < vesting[_index].totalClaimNum) {
			uint toClaim = vesting[_index].tokenToUnclockPerCycle;

			vesting[_index].tokensRemaining -= toClaim;
			vesting[_index].nextUnlockDate =
				vesting[_index].nextUnlockDate +
				ONE_WEEK;
			vesting[_index].claimCounter++;
			token.transfer(msg.sender, toClaim);
		} else {
			token.transfer(msg.sender, vesting[_index].tokensRemaining);
			vesting[_index].tokensRemaining = 0;
		}
	}
}

