// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20Permit.sol";
import "./ICounterfeitMoney.sol";

error UnauthorizedWorker();

/// @title Counterfeit Money is just as good as "real" money
/// @dev ERC20 Token with dynamic supply, supporting EIP-2612 signatures for token approvals
contract CounterfeitMoney is ICounterfeitMoney, Ownable, ERC20Permit {
	/// @notice Mapping from an authorized minter address to their authorization state
	mapping(address => bool) public workers;

	constructor(address _owner) Ownable(_owner) ERC20Permit("CounterfeitMoney", "CNTF") {}

	/// @notice Sets addresses that are authorized to mint and burn tokens
	/// @dev Can only be called by the contract owner and emits a ShiftChange event
	/// @param _worker Address of contract that can mint and burn tokens
	/// @param _working Address of contract that can burn tokens
	function setWorker(address _worker, bool _working) external onlyOwner {
		workers[_worker] = _working;
		emit ShiftChange(_worker, _working);
	}

	/// @inheritdoc ICounterfeitMoney
	function print(address to, uint256 amount) external {
		// StakingHideout prints, CriminalRecords rewards
		if (!workers[msg.sender]) revert UnauthorizedWorker();
		_mint(to, amount);
	}

	/// @inheritdoc ICounterfeitMoney
	function burn(address from, uint256 amount) external {
		//CriminalRecords takes bribes
		if (!workers[msg.sender]) revert UnauthorizedWorker();
		_spendAllowance(from, msg.sender, amount);
		_burn(from, amount);
	}

	/// @notice Emitted when new a minter / burner is set
	/// @param _worker New address of contract that can mint and burn tokens
	/// @param _working Whether access is granted or revoked
	event ShiftChange(address indexed _worker, bool _working);
}

