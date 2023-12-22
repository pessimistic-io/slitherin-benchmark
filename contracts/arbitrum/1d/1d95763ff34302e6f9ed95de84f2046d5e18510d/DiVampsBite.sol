// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./AccessControl.sol";

interface IDiVamps {
	function balanceOf(address owner) external view returns (uint256);
}

contract DiVampBites is AccessControl {
	IDiVamps public diVamps;

	uint256 public biteFee = 0.0002 ether;

	mapping(address => mapping(address => bool)) public bites; // referrer => referee
	mapping(address => uint256) public biteCount;

	event Bite(
		address indexed referrer,
		address referee
	);

	constructor(address _diVamps) {
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

		diVamps = IDiVamps(_diVamps);
	}

	function bite(address[] calldata _targets) external payable {
		require(diVamps.balanceOf(msg.sender) == 1, "Must own a DiVamp to bite");
		require(msg.value == biteFee * _targets.length, "Incorrect fee amount");

		for (uint256 i = 0; i < _targets.length; i++) {
			require(_targets[i] != address(0), "Invalid address");
			require(diVamps.balanceOf(_targets[i]) == 0, "Target already owns a DiVamp");
			require(bites[msg.sender][_targets[i]] == false, "Can't bite same address twice");

			bites[msg.sender][_targets[i]] = true;

			biteCount[msg.sender]++;

			// send ETH to target
			(bool success, ) = payable(_targets[i]).call{value: biteFee}("");
			require(success, "Transfer failed.");

			emit Bite(msg.sender, _targets[i]);
		}
	}

	// update fee
	function updateBiteFee(uint256 _value) external onlyRole(DEFAULT_ADMIN_ROLE) {
		require(_value <= 0.002 ether, "Excessive bite fee");
		biteFee = _value;
	}
}

