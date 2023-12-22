// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

interface IModule {
	/**
	 * @dev Executes an operation in the context of the module contract.
	 * @param data Arbitrary data to be used by the execute function. Feel free to structure this however you wish
	 */
	function execute(bytes calldata data) external;

	/**
	 * @dev Return the moduleId, make sure this is unique!
	 */
	function moduleId() external view returns (bytes32);
}

