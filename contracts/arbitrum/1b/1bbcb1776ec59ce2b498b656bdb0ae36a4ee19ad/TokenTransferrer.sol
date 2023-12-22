// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./TokenTransferrerConstants.sol";
import { TokenTransferrerErrors } from "./TokenTransferrerErrors.sol";
import { IERC20 } from "./interface_IERC20.sol";
import { IERC20Callback } from "./IERC20Callback.sol";

/**
 * @title TokenTransferrer
 * @custom:source https://github.com/ProjectOpenSea/seaport
 * @dev Modified version of Seaport.
 */
abstract contract TokenTransferrer is TokenTransferrerErrors {
	function _performTokenTransfer(
		address token,
		address to,
		uint256 amount,
		bool sendCallback
	) internal {
		if (token == address(0)) {
			(bool success, ) = to.call{ value: amount }(new bytes(0));

			if (!success) revert ErrorTransferETH(address(this), token, amount);

			return;
		}

		address from = address(this);

		// Utilize assembly to perform an optimized ERC20 token transfer.
		assembly {
			// The free memory pointer memory slot will be used when populating
			// call data for the transfer; read the value and restore it later.
			let memPointer := mload(FreeMemoryPointerSlot)

			// Write call data into memory, starting with function selector.
			mstore(ERC20_transfer_sig_ptr, ERC20_transfer_signature)
			mstore(ERC20_transfer_to_ptr, to)
			mstore(ERC20_transfer_amount_ptr, amount)

			// Make call & copy up to 32 bytes of return data to scratch space.
			// Scratch space does not need to be cleared ahead of time, as the
			// subsequent check will ensure that either at least a full word of
			// return data is received (in which case it will be overwritten) or
			// that no data is received (in which case scratch space will be
			// ignored) on a successful call to the given token.
			let callStatus := call(
				gas(),
				token,
				0,
				ERC20_transfer_sig_ptr,
				ERC20_transfer_length,
				0,
				OneWord
			)

			// Determine whether transfer was successful using status & result.
			let success := and(
				// Set success to whether the call reverted, if not check it
				// either returned exactly 1 (can't just be non-zero data), or
				// had no return data.
				or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
				callStatus
			)

			// Handle cases where either the transfer failed or no data was
			// returned. Group these, as most transfers will succeed with data.
			// Equivalent to `or(iszero(success), iszero(returndatasize()))`
			// but after it's inverted for JUMPI this expression is cheaper.
			if iszero(and(success, iszero(iszero(returndatasize())))) {
				// If the token has no code or the transfer failed: Equivalent
				// to `or(iszero(success), iszero(extcodesize(token)))` but
				// after it's inverted for JUMPI this expression is cheaper.
				if iszero(and(iszero(iszero(extcodesize(token))), success)) {
					// If the transfer failed:
					if iszero(success) {
						// If it was due to a revert:
						if iszero(callStatus) {
							// If it returned a message, bubble it up as long as
							// sufficient gas remains to do so:
							if returndatasize() {
								// Ensure that sufficient gas is available to
								// copy returndata while expanding memory where
								// necessary. Start by computing the word size
								// of returndata and allocated memory. Round up
								// to the nearest full word.
								let returnDataWords := div(
									add(returndatasize(), AlmostOneWord),
									OneWord
								)

								// Note: use the free memory pointer in place of
								// msize() to work around a Yul warning that
								// prevents accessing msize directly when the IR
								// pipeline is activated.
								let msizeWords := div(memPointer, OneWord)

								// Next, compute the cost of the returndatacopy.
								let cost := mul(CostPerWord, returnDataWords)

								// Then, compute cost of new memory allocation.
								if gt(returnDataWords, msizeWords) {
									cost := add(
										cost,
										add(
											mul(sub(returnDataWords, msizeWords), CostPerWord),
											div(
												sub(
													mul(returnDataWords, returnDataWords),
													mul(msizeWords, msizeWords)
												),
												MemoryExpansionCoefficient
											)
										)
									)
								}

								// Finally, add a small constant and compare to
								// gas remaining; bubble up the revert data if
								// enough gas is still available.
								if lt(add(cost, ExtraGasBuffer), gas()) {
									// Copy returndata to memory; overwrite
									// existing memory.
									returndatacopy(0, 0, returndatasize())

									// Revert, specifying memory region with
									// copied returndata.
									revert(0, returndatasize())
								}
							}

							// Otherwise revert with a generic error message.
							mstore(
								TokenTransferGenericFailure_error_sig_ptr,
								TokenTransferGenericFailure_error_signature
							)
							mstore(TokenTransferGenericFailure_error_token_ptr, token)
							mstore(TokenTransferGenericFailure_error_from_ptr, from)
							mstore(TokenTransferGenericFailure_error_to_ptr, to)
							mstore(TokenTransferGenericFailure_error_id_ptr, 0)
							mstore(TokenTransferGenericFailure_error_amount_ptr, amount)
							revert(
								TokenTransferGenericFailure_error_sig_ptr,
								TokenTransferGenericFailure_error_length
							)
						}

						// Otherwise revert with a message about the token
						// returning false or non-compliant return values.
						mstore(
							BadReturnValueFromERC20OnTransfer_error_sig_ptr,
							BadReturnValueFromERC20OnTransfer_error_signature
						)
						mstore(BadReturnValueFromERC20OnTransfer_error_token_ptr, token)
						mstore(BadReturnValueFromERC20OnTransfer_error_from_ptr, from)
						mstore(BadReturnValueFromERC20OnTransfer_error_to_ptr, to)
						mstore(BadReturnValueFromERC20OnTransfer_error_amount_ptr, amount)
						revert(
							BadReturnValueFromERC20OnTransfer_error_sig_ptr,
							BadReturnValueFromERC20OnTransfer_error_length
						)
					}

					// Otherwise, revert with error about token not having code:
					mstore(NoContract_error_sig_ptr, NoContract_error_signature)
					mstore(NoContract_error_token_ptr, token)
					revert(NoContract_error_sig_ptr, NoContract_error_length)
				}

				// Otherwise, the token just returned no data despite the call
				// having succeeded; no need to optimize for this as it's not
				// technically ERC20 compliant.
			}

			// Restore the original free memory pointer.
			mstore(FreeMemoryPointerSlot, memPointer)

			// Restore the zero slot to zero.
			mstore(ZeroSlot, 0)
		}

		_tryPerformCallback(token, to, amount, sendCallback);
	}

	function _performTokenTransferFrom(
		address token,
		address from,
		address to,
		uint256 amount,
		bool sendCallback
	) internal {
		// Utilize assembly to perform an optimized ERC20 token transfer.
		assembly {
			// The free memory pointer memory slot will be used when populating
			// call data for the transfer; read the value and restore it later.
			let memPointer := mload(FreeMemoryPointerSlot)

			// Write call data into memory, starting with function selector.
			mstore(ERC20_transferFrom_sig_ptr, ERC20_transferFrom_signature)
			mstore(ERC20_transferFrom_from_ptr, from)
			mstore(ERC20_transferFrom_to_ptr, to)
			mstore(ERC20_transferFrom_amount_ptr, amount)

			// Make call & copy up to 32 bytes of return data to scratch space.
			// Scratch space does not need to be cleared ahead of time, as the
			// subsequent check will ensure that either at least a full word of
			// return data is received (in which case it will be overwritten) or
			// that no data is received (in which case scratch space will be
			// ignored) on a successful call to the given token.
			let callStatus := call(
				gas(),
				token,
				0,
				ERC20_transferFrom_sig_ptr,
				ERC20_transferFrom_length,
				0,
				OneWord
			)

			// Determine whether transfer was successful using status & result.
			let success := and(
				// Set success to whether the call reverted, if not check it
				// either returned exactly 1 (can't just be non-zero data), or
				// had no return data.
				or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
				callStatus
			)

			// Handle cases where either the transfer failed or no data was
			// returned. Group these, as most transfers will succeed with data.
			// Equivalent to `or(iszero(success), iszero(returndatasize()))`
			// but after it's inverted for JUMPI this expression is cheaper.
			if iszero(and(success, iszero(iszero(returndatasize())))) {
				// If the token has no code or the transfer failed: Equivalent
				// to `or(iszero(success), iszero(extcodesize(token)))` but
				// after it's inverted for JUMPI this expression is cheaper.
				if iszero(and(iszero(iszero(extcodesize(token))), success)) {
					// If the transfer failed:
					if iszero(success) {
						// If it was due to a revert:
						if iszero(callStatus) {
							// If it returned a message, bubble it up as long as
							// sufficient gas remains to do so:
							if returndatasize() {
								// Ensure that sufficient gas is available to
								// copy returndata while expanding memory where
								// necessary. Start by computing the word size
								// of returndata and allocated memory. Round up
								// to the nearest full word.
								let returnDataWords := div(
									add(returndatasize(), AlmostOneWord),
									OneWord
								)

								// Note: use the free memory pointer in place of
								// msize() to work around a Yul warning that
								// prevents accessing msize directly when the IR
								// pipeline is activated.
								let msizeWords := div(memPointer, OneWord)

								// Next, compute the cost of the returndatacopy.
								let cost := mul(CostPerWord, returnDataWords)

								// Then, compute cost of new memory allocation.
								if gt(returnDataWords, msizeWords) {
									cost := add(
										cost,
										add(
											mul(sub(returnDataWords, msizeWords), CostPerWord),
											div(
												sub(
													mul(returnDataWords, returnDataWords),
													mul(msizeWords, msizeWords)
												),
												MemoryExpansionCoefficient
											)
										)
									)
								}

								// Finally, add a small constant and compare to
								// gas remaining; bubble up the revert data if
								// enough gas is still available.
								if lt(add(cost, ExtraGasBuffer), gas()) {
									// Copy returndata to memory; overwrite
									// existing memory.
									returndatacopy(0, 0, returndatasize())

									// Revert, specifying memory region with
									// copied returndata.
									revert(0, returndatasize())
								}
							}

							// Otherwise revert with a generic error message.
							mstore(
								TokenTransferGenericFailure_error_sig_ptr,
								TokenTransferGenericFailure_error_signature
							)
							mstore(TokenTransferGenericFailure_error_token_ptr, token)
							mstore(TokenTransferGenericFailure_error_from_ptr, from)
							mstore(TokenTransferGenericFailure_error_to_ptr, to)
							mstore(TokenTransferGenericFailure_error_id_ptr, 0)
							mstore(TokenTransferGenericFailure_error_amount_ptr, amount)
							revert(
								TokenTransferGenericFailure_error_sig_ptr,
								TokenTransferGenericFailure_error_length
							)
						}

						// Otherwise revert with a message about the token
						// returning false or non-compliant return values.
						mstore(
							BadReturnValueFromERC20OnTransfer_error_sig_ptr,
							BadReturnValueFromERC20OnTransfer_error_signature
						)
						mstore(BadReturnValueFromERC20OnTransfer_error_token_ptr, token)
						mstore(BadReturnValueFromERC20OnTransfer_error_from_ptr, from)
						mstore(BadReturnValueFromERC20OnTransfer_error_to_ptr, to)
						mstore(BadReturnValueFromERC20OnTransfer_error_amount_ptr, amount)
						revert(
							BadReturnValueFromERC20OnTransfer_error_sig_ptr,
							BadReturnValueFromERC20OnTransfer_error_length
						)
					}

					// Otherwise, revert with error about token not having code:
					mstore(NoContract_error_sig_ptr, NoContract_error_signature)
					mstore(NoContract_error_token_ptr, token)
					revert(NoContract_error_sig_ptr, NoContract_error_length)
				}

				// Otherwise, the token just returned no data despite the call
				// having succeeded; no need to optimize for this as it's not
				// technically ERC20 compliant.
			}

			// Restore the original free memory pointer.
			mstore(FreeMemoryPointerSlot, memPointer)

			// Restore the zero slot to zero.
			mstore(ZeroSlot, 0)
		}

		_tryPerformCallback(token, to, amount, sendCallback);
	}

	function _tryPerformCallback(
		address _token,
		address _to,
		uint256 _amount,
		bool _useCallback
	) private {
		if (!_useCallback || _to.code.length == 0) return;

		if (address(this) == _to) {
			revert SelfCallbackTransfer();
		}

		IERC20Callback(_to).receiveERC20(_token, _amount);
	}

	/**
		@notice SanitizeAmount allows to convert an 1e18 value to the token decimals
		@dev only supports 18 and lower
		@param token The contract address of the token
		@param value The value you want to sanitize
	*/
	function _sanitizeValue(address token, uint256 value)
		internal
		view
		returns (uint256)
	{
		if (token == address(0) || value == 0) return value;

		(bool success, bytes memory data) = token.staticcall(
			abi.encodeWithSignature("decimals()")
		);

		if (!success) return value;

		uint8 decimals = abi.decode(data, (uint8));

		if (decimals < 18) {
			return value / (10**(18 - decimals));
		}

		return value;
	}

	function _tryPerformMaxApprove(address _token, address _to) internal {
		if (IERC20(_token).allowance(address(this), _to) == type(uint256).max) {
			return;
		}

		_performApprove(_token, _to, type(uint256).max);
	}

	function _performApprove(
		address _token,
		address _spender,
		uint256 _value
	) internal {
		IERC20(_token).approve(_spender, _value);
	}

	function _balanceOf(address _token, address _of) internal view returns (uint256) {
		return IERC20(_token).balanceOf(_of);
	}
}

