// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IFlashLoanExecutor {
	/**
	 * @notice Executes an operation after receiving the flash-loaned VST
	 * @dev Ensure that the contract can return the debt + fee, e.g., has
	 *      enough funds to repay and has approved the flashloan contract to pull the total amount
	 * @param _amount The amount of the flash-loaned VST
	 * @param _fee The fee of the flash-loan. Flat amount calculated by the flashloan contract.
	 * @param _executor The address of the flashloan initiator
	 * @param _extraParams The byte-encoded params passed when initiating the flashloan. May not be needed.
	 */
	function executeOperation(
		uint256 _amount,
		uint256 _fee,
		address _executor,
		bytes calldata _extraParams
	) external;
}


