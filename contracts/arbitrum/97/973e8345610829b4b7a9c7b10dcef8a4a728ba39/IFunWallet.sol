// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./IEntryPoint.sol";

struct UserOperationFee {
	address token;
	address payable recipient;
	uint256 amount;
}

interface IFunWallet {
	/**
	 * @notice deposit to entrypoint to prefund the execution.
	 * @dev This function can only be called by the owner of the contract.
	 * @param amount the amount to deposit.
	 */
	function depositToEntryPoint(uint256 amount) external;

	/**
	 * @notice Get the entry point for this contract
	 * @dev This function returns the contract's entry point interface.
	 * @return The contract's entry point interface.
	 */
	function entryPoint() external view returns (IEntryPoint);

	/**
	 * @notice Update the entry point for this contract
	 * @dev This function can only be called by the current entry point.
	 * @dev The new entry point address cannot be zero.
	 * @param _newEntryPoint The address of the new entry point.
	 */
	function updateEntryPoint(IEntryPoint _newEntryPoint) external;

	/**
	 * @notice withdraw deposit from entrypoint
	 * @dev This function can only be called by the owner of the contract.
	 * @param withdrawAddress the address to withdraw Eth to
	 * @param amount the amount to be withdrawn
	 */
	function withdrawFromEntryPoint(address payable withdrawAddress, uint256 amount) external;

	/**
	 * @notice Transfer ERC20 tokens from the wallet to a destination address.
	 * @param token ERC20 token address
	 * @param dest Destination address
	 * @param amount Amount of tokens to transfer
	 */
	function transferErc20(address token, address dest, uint256 amount) external;

	function isValidAction(address target, uint256 value, bytes memory data, bytes memory signature, bytes32 _hash) external view returns (uint256);

	event EntryPointChanged(address indexed newEntryPoint);
}

