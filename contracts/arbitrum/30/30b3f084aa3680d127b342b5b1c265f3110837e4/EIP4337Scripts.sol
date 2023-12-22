// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Copyright (C) 2023 VALK
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.18;

import "./SmartWalletRegistry.sol";
import "./ISmartWallet.sol";
import "./IAccount.sol";
import "./IEntryPoint.sol";
import "./ECDSA.sol";
import "./StorageSlot.sol";
import "./ScriptsBase.sol";

interface IEIP4337Scripts is IAccount {
  function withdrawDepositTo(address payable withdrawAddress, uint256 amount) external;

	function claimAndExec(bytes20 target, bytes memory data) external payable;
}

interface IEIP4337ScriptsGlobal {
	function entryPoint() external view returns (address);

  function getNonce() external view returns (uint);

  function getDeposit() external view returns (uint256);

  function addDeposit() external payable;
}

/* implemantation of EIP-4337 IAccount for the smart wallet */
contract EIP4337Scripts is ScriptsBase, IEIP4337Scripts, IEIP4337ScriptsGlobal {
	// return value in case of signature failure, with no time-range.
	// equivalent to _packValidationData(true,0,0);
	uint256 internal constant SIG_VALIDATION_FAILED = 1;
	bytes32 private constant NONCE_SLOT = keccak256("EIP4337Scripts.nonce");
	address public immutable entryPoint;

	using ECDSA for bytes32;

	constructor(address _entryPoint) {
		entryPoint = _entryPoint;
	}

	function getNonce() public view delegated returns (uint) {
		return StorageSlot.getUint256Slot(NONCE_SLOT).value;
	}

	function setNonce(uint newNonce) private {
		StorageSlot.getUint256Slot(NONCE_SLOT).value = newNonce;
	}

	/**
	 * ensure the request comes from the known entrypoint.
	 */
	function _requireFromEntryPoint() internal view {
		require(msg.sender == entryPoint, "#AAL: not from EntryPoint");
	}

	/**
	 * validate the signature is valid for this message.
	 * @param userOp validate the userOp.signature field
	 * @param userOpHash convenient field: the hash of the request, to check the signature against
	 *          (also hashes the entrypoint and chain id)
	 * @return validationData signature and time-range of this operation
	 *      <20-byte> sigAuthorizer - 0 for valid signature, 1 to mark signature failure,
	 *         otherwise, an address of an "authorizer" contract.
	 *      <6-byte> validUntil - last timestamp this operation is valid. 0 for "indefinite"
	 *      <6-byte> validAfter - first timestamp this operation is valid
	 *      If the account doesn't use time-range, it is enough to return SIG_VALIDATION_FAILED value (1) for signature failure.
	 *      Note that the validation code cannot use block.timestamp (or block.number) directly.
	 */
	function _validateSignature(
		UserOperation calldata userOp,
		bytes32 userOpHash
	) internal view returns (uint256 validationData) {
		address owner = $owner;
		bytes32 hash = userOpHash.toEthSignedMessageHash();
		if (owner != hash.recover(userOp.signature)) {
			return SIG_VALIDATION_FAILED;
		}
		return 0;
	}

	/**
	 * sends to the entrypoint (msg.sender) the missing funds for this transaction.
	 * subclass MAY override this method for better funds management
	 * (e.g. send to the entryPoint more than the minimum required, so that in future transactions
	 * it will not be required to send again)
	 * @param missingAccountFunds the minimum value this method should send the entrypoint.
	 *  this value MAY be zero, in case there is enough deposit, or the userOp has a paymaster.
	 */
	function _payPrefund(uint256 missingAccountFunds) internal {
		if (missingAccountFunds != 0) {
			(bool success, ) = payable(msg.sender).call{ value: missingAccountFunds, gas: type(uint256).max }("");
			(success);
			//ignore failure (its EntryPoint's job to verify, not account.)
		}
	}

	/**
	 * validate the current nonce matches the UserOperation nonce.
	 * then it should update the account's state to prevent replay of this UserOperation.
	 * called only if initCode is empty (since "nonce" field is used as "salt" on account creation)
	 * @param userOp the op to validate.
	 */
	function _validateAndUpdateNonce(UserOperation calldata userOp) internal {
		uint nonce = getNonce();
		require(nonce == userOp.nonce, "#AAL: invalid nonce");
		setNonce(nonce);
	}

	/**
	 * Validate user's signature and nonce.
	 */
	function validateUserOp(
		UserOperation calldata userOp,
		bytes32 userOpHash,
		uint256 missingAccountFunds
	) external delegated returns (uint256 validationData) {
		_requireFromEntryPoint();
		validationData = _validateSignature(userOp, userOpHash);
		if (userOp.initCode.length == 0) {
			_validateAndUpdateNonce(userOp);
		}
		_payPrefund(missingAccountFunds);
	}

	/**
	 * check current account deposit in the entryPoint
	 */
	function getDeposit() public view delegated returns (uint256) {
		return IEntryPoint(entryPoint).balanceOf(address(this));
	}

	/**
	 * deposit more funds for this account in the entryPoint
	 */
	function addDeposit() public payable delegated logged {
		 IEntryPoint(entryPoint).depositTo{ value: msg.value }(address(this));
	}

	/**
	 * withdraw value from the account's deposit
	 * @param withdrawAddress target to send to
	 * @param amount to withdraw
	 */
	function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public delegated logged {
		IEntryPoint(entryPoint).withdrawTo(withdrawAddress, amount);
	}

	/**
	 * for use in wallet creation UserOperation
	 */
	function claimAndExec(bytes20 target, bytes memory data) external payable delegated {
		smartWalletRegistry().claim(address(this), true);
		ISmartWallet(address(this)).exec(target, data);
	}
}

