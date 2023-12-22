// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./HashLib.sol";
import "./IFunWallet.sol";
import "./IWalletFee.sol";

struct ExtraParams {
	bytes32[] targetMerkleProof;
	bytes32[] selectorMerkleProof;
	bytes32[] recipientMerkleProof;
	bytes32[] tokenMerkleProof;
}

struct ValidationData {
	address aggregator;
	uint48 validAfter;
	uint48 validUntil;
}

library DataLib {
	/**
	 * @notice Extracts authType, userId, and signature from UserOperation.signature.
	 * @param signature The UserOperation of the user.
	 * @return authType Attempted authentication method of user.
	 * @return userId Attempted identifier of user.
	 * @return roleId Attempted identifier of user role.
	 * @return ruleId Attempted identifier of user rule.
	 * @return signature Attempted signature of user.
	 * @return simulate Attempted in simulate mode.
	 */
	function getAuthData(bytes memory signature) internal pure returns (uint8, bytes32, bytes32, bytes32, bytes memory, ExtraParams memory) {
		return abi.decode(signature, (uint8, bytes32, bytes32, bytes32, bytes, ExtraParams));
	}

	/**
	 * @notice Extracts the relevant data from the callData parameter.
	 * @param callData The calldata containing the user operation details.
	 * @return to The target address of the call.
	 * @return value The value being transferred in the call.
	 * @return data The data payload of the call.
	 * @return fee The fee details of the user operation (if present).
	 * @return feeExists Boolean indicating whether a fee exists in the user operation.
	 * @dev This function decodes the callData parameter and extracts the target address, value, data, and fee (if present) based on the function selector.
	 * @dev If the function selector matches `execFromEntryPoint`, the to, value, and data are decoded.
	 * @dev If the function selector matches `execFromEntryPointWithFee`, the to, value, data, and fee are decoded, and feeExists is set to true.
	 * @dev If the function selector doesn't match any supported functions, the function reverts with an error message "FW600".
	 */
	function getCallData(
		bytes calldata callData
	) internal pure returns (address to, uint256 value, bytes memory data, UserOperationFee memory fee, bool feeExists) {
		if (bytes4(callData[:4]) == IWalletFee.execFromEntryPoint.selector) {
			(to, value, data) = abi.decode(callData[4:], (address, uint256, bytes));
		} else if (bytes4(callData[:4]) == IWalletFee.execFromEntryPointWithFee.selector) {
			(to, value, data, fee) = abi.decode(callData[4:], (address, uint256, bytes, UserOperationFee));
			feeExists = true;
		} else {
			revert("FW600");
		}
	}

	/**
	 * @notice Validates the Merkle proof provided to verify the existence of a leaf in a Merkle tree. It doesn't validate the proof length or hash the leaf.
	 * @param root The root of the Merkle tree.
	 * @param leaf The leaf which existence in the Merkle tree is being verified.
	 * @param proof An array of bytes32 that represents the Merkle proof.
	 * @return Returns true if the computed hash equals the root, i.e., the leaf exists in the tree.
	 * @dev This function assumes that the leaf passed into it has already been hashed. 
	 		This is a safe assumption as all current invocations of this function adhere to this standard. 
			Future uses of this function should ensure that the leaf input is hashed to maintain safety. Avoid calling in unsafe contexts.
			Otherwise, a user could just pass in a leaf where leaf == merkleRoot and an empty bytes array for the merkle proof to successfully validate any merkle root
	 */
	function validateMerkleRoot(bytes32 root, bytes32 leaf, bytes32[] memory proof) internal pure returns (bool) {
		bytes32 computedHash = leaf;
		for (uint256 i = 0; i < proof.length; ++i) {
			bytes32 proofElement = proof[i];
			if (computedHash < proofElement) {
				computedHash = HashLib.hash2(computedHash, proofElement);
			} else {
				computedHash = HashLib.hash2(proofElement, computedHash);
			}
		}
		return computedHash == root;
	}

	/**
	 * @notice Parses the validation data and returns a ValidationData struct.
	 * @param validationData An unsigned integer from which the validation data is extracted.
	 * @return data Returns a ValidationData struct containing the aggregator address, validAfter, and validUntil timestamps.
	 */
	function parseValidationData(uint validationData) internal pure returns (ValidationData memory data) {
		address aggregator = address(uint160(validationData));
		uint48 validUntil = uint48(validationData >> 160);
		uint48 validAfter = uint48(validationData >> (48 + 160));
		return ValidationData(aggregator, validAfter, validUntil);
	}

	/**
	 * @notice Composes a ValidationData struct into an unsigned integer.
	 * @param data A ValidationData struct containing the aggregator address, validAfter, and validUntil timestamps.
	 * @return validationData Returns an unsigned integer representation of the ValidationData struct.
	 */
	function getValidationData(ValidationData memory data) internal pure returns (uint256 validationData) {
		return uint160(data.aggregator) | (uint256(data.validUntil) << 160) | (uint256(data.validAfter) << (160 + 48));
	}
}

