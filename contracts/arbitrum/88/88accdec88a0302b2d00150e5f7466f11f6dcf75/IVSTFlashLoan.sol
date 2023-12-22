// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IVSTFlashLoan {
	event FlashLoanSuccess(address _caller, address _reciever, uint256 _amount);

	/**
	 * @notice Implements the simple flashloan feature that allow users to borrow VST to perform arbitrage
	 * as long as the amount taken plus fee is returned.
	 * @dev At the end of the transaction the contract will pull amount borrowed + fee from the receiver,
	 * if the receiver have not approved the pool the transaction will revert.
	 * @param _amount The amount of VST flashloaned
	 * @param _executor The contract recieving the flashloan funds and performing the flashloan operation.
	 * @param _extraParams The additional parameters needed to execute the simple flashloan function
	 */
	function executeFlashLoan(
		uint256 _amount,
		address _executor,
		bytes calldata _extraParams
	) external;
}


