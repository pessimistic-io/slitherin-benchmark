// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./IFunWallet.sol";

interface IFunWalletFactory {
	/**
	 * @notice Deploys a new FunWallet contract and initializes it with the given initializer call data.
	 * @dev If a contract with the given salt already exists, returns the existing contract.
	 * @param initializerCallData The call data for initializing the FunWallet contract.
	 * @param data The social login data struct from IWalletInit. See IWalletInit.sol for more info
	 * @return funWallet The deployed FunWallet contract.
	 */
	function createAccount(bytes calldata initializerCallData, bytes calldata data) external returns (IFunWallet funWallet);

	/**
	 * @dev Calculate the counterfactual address of this account as it would be returned by createAccount()
	 * @param data The social login data struct from IWalletInit. See IWalletInit.sol for more info
	 * @return The computed address of the contract deployment.
	 */
	function getAddress(bytes calldata data, bytes calldata initializerCallData) external view returns (address);

	/**
	 * @return The address of the feeOracle
	 */
	function getFeeOracle() external view returns (address payable);

	/**
	 * @param _feeOracle The address of the feeOracle to use
	 */
	function setFeeOracle(address payable _feeOracle) external;

	/**
	 * Verify the contract was deployed from the Create3Deployer
	 * @param salt Usually the moduleId()
	 * @param sender The sender of the transaction, usually the module
	 */
	function verifyDeployedFrom(bytes32 salt, address sender) external view returns (bool);
}

