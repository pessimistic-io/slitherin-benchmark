// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IFlashLoanExecutor {
	/**
	 * @notice Executes an operation after receiving the flash-loaned VST
	 * @dev Ensure that the contract can return the debt + fee, e.g., has
	 *      enough funds to repay and has approved the flashloan contract to pull the total amount
	 * @param amount The amount of the flash-loaned VST
	 * @param fee The fee of the flash-loan. Flat amount calculated by the flashloan contract.
	 * @param initiator The address of the flashloan initiator
	 * @param extraParams The byte-encoded params passed when initiating the flashloan. May not be needed.
	 */
	function executeOperation(
		uint256 amount,
		uint256 fee,
		address initiator,
		bytes calldata extraParams
	) external;
}


