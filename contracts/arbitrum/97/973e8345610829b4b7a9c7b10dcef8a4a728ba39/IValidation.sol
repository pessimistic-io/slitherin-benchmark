// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./UserOperation.sol";

interface IValidation {
	function init(bytes calldata initData) external;

	/**
	 * @notice Validates the UserOperation based on its rules.
	 * @param userOp UserOperation to validate.
	 * @param userOpHash Hash of the UserOperation.
	 * @param helperData Unused
	 * @return sigTimeRange Valid Time Range of the signature.
	 */
	function authenticateUserOp(
		UserOperation calldata userOp,
		bytes32 userOpHash,
		bytes memory helperData
	) external view returns (uint256 sigTimeRange);

	/**
	 * @notice Validates if a user can call: target.call(data) in the FunWallet
	 * @return sigTimeRange Valid Time Range of the signature.
	 */
	function isValidAction(address target, uint256 value, bytes memory data, bytes memory signature, bytes32 _hash) external view returns (uint256);
}

