// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IWormholeRelayer.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {LibSwap} from "./LibSwap.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibUtil} from "./LibUtil.sol";
import {IKana} from "./IKana.sol";
import {IExecutor} from "./IExecutor.sol";
import {TransferrableOwnership} from "./TransferrableOwnership.sol";
import {ExternalCallFailed, UnAuthorized} from "./GenericErrors.sol";
import {IMessageTransmitter} from "./IMessageTransmitter.sol";

contract CircleReceiver is IKana, ReentrancyGuard, TransferrableOwnership {
	using SafeERC20 for IERC20;

	uint256 public recoverGas;
	IMessageTransmitter private immutable messageTransmitter;

	/// @notice The USDC address on the source chain.
	address private immutable usdc;
	IExecutor public executor;

	event CircleReceiverSet(address indexed messageTransmitter, address indexed usdc);

	constructor(
		address _owner,
		address _executor,
		address _messageTransmitter,
		address _usdc,
		uint256 _recoverGas
	) TransferrableOwnership(_owner) {
		owner = _owner;
		usdc = _usdc;
		executor = IExecutor(_executor);
		messageTransmitter = IMessageTransmitter(_messageTransmitter);
		recoverGas = _recoverGas;

		emit CircleReceiverSet(_messageTransmitter, _usdc);
	}

	/// External Methods ///
	function claimTokens(
		address receiver,
		uint256 amount,
		bytes calldata message,
		bytes calldata signature
	) external payable {
		bool success = messageTransmitter.receiveMessage(message, signature);
		if (!success) {
			revert("Transaction reverted at from signature");
		}
		IERC20(usdc).transfer(receiver, amount);
	}

	function claimAndSwapTokens(
		bytes32 _transactionId,
		bytes calldata message,
		bytes calldata signature,
		LibSwap.SwapData[] calldata _swapData,
		address receiver,
		uint256 amount
	) external payable {
		bool success = messageTransmitter.receiveMessage(message, signature);
		if (!success) {
			revert("Transaction reverted from signature");
		}
		_swapAndCompleteBridgeTokens(_transactionId, _swapData, usdc, payable(receiver), amount, false);
	}

	/// Private Methods ///

	/// @notice Performs a swap before completing a cross-chain transaction
	/// @param _transactionId the transaction id associated with the operation
	/// @param _swapData array of data needed for swaps
	/// @param assetId token received from the other chain
	/// @param receiver address that will receive tokens in the end
	/// @param amount amount of token
	/// @param reserveRecoverGas whether we need a gas buffer to recover
	function _swapAndCompleteBridgeTokens(
		bytes32 _transactionId,
		LibSwap.SwapData[] memory _swapData,
		address assetId,
		address payable receiver,
		uint256 amount,
		bool reserveRecoverGas
	) private {
		uint256 _recoverGas = reserveRecoverGas ? recoverGas : 0;

		uint256 cacheGasLeft = gasleft();
		IERC20 token = IERC20(assetId);
		token.safeApprove(address(executor), 0);

		//false				 (387184 	<	0) false
		if (reserveRecoverGas && cacheGasLeft < _recoverGas) {
			// case 2a: not enough gas left to execute calls
			token.safeTransfer(receiver, amount);

			emit KanaTransferRecovered(_transactionId, assetId, receiver, amount, block.timestamp);
			return;
		}

		// case 2b: enough gas left to execute calls
		token.safeIncreaseAllowance(address(executor), amount);
		try
			executor.swapAndCompleteBridgeTokens{gas: cacheGasLeft - _recoverGas}(
				_transactionId,
				_swapData,
				assetId,
				receiver
			)
		{} catch {
			token.safeTransfer(receiver, amount);
			emit KanaTransferRecovered(_transactionId, assetId, receiver, amount, block.timestamp);
		}

		token.safeApprove(address(executor), 0);
	}

	/// @dev required for receiving native assets from destination swaps
	// solhint-disable-next-line no-empty-blocks
	receive() external payable {}
}

