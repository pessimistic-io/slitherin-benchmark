// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {LibSwap} from "./LibSwap.sol";
import {LibAsset} from "./LibAsset.sol";
import {IKana} from "./IKana.sol";
import {IExecutor} from "./IExecutor.sol";
import {IStargateReceiver} from "./IStargateReceiver.sol";
import {TransferrableOwnership} from "./TransferrableOwnership.sol";
import {ExternalCallFailed, UnAuthorized} from "./GenericErrors.sol";

/// @title Executor
/// @author KANA
/// @notice Arbitrary execution contract used for cross-chain swaps and message passing
/// @custom:version 2.0.0
contract StargateReceiver is IKana, ReentrancyGuard, TransferrableOwnership {
	using SafeERC20 for IERC20;

	/// Storage ///
	address public sgRouter;
	IExecutor public executor;
	uint256 public recoverGas;

	/// Events ///
	event StargateRouterSet(address indexed router);
	event ExecutorSet(address indexed executor);
	event RecoverGasSet(uint256 indexed recoverGas);

	/// Modifiers ///
	modifier onlySGRouter() {
		if (msg.sender != sgRouter) {
			revert UnAuthorized();
		}
		_;
	}

	/// Constructor
	constructor(
		address _owner,
		address _sgRouter,
		address _executor,
		uint256 _recoverGas
	) TransferrableOwnership(_owner) {
		owner = _owner;
		sgRouter = _sgRouter;
		executor = IExecutor(_executor);
		recoverGas = _recoverGas;
		emit StargateRouterSet(_sgRouter);
		emit RecoverGasSet(_recoverGas);
	}

	/// External Methods ///

	/// @notice Completes a cross-chain transaction on the receiving chain.
	/// @dev This function is called from Stargate Router.
	/// @param * (unused) The remote chainId sending the tokens
	/// @param * (unused) The remote Bridge address
	/// @param * (unused) Nonce
	/// @param _token The token contract on the local chain
	/// @param _amountLD The amount of tokens received through bridging
	/// @param _payload The data to execute
	function sgReceive(
		uint16, // _srcChainId unused
		bytes memory, // _srcAddress unused
		uint256, // _nonce unused
		address _token,
		uint256 _amountLD,
		bytes memory _payload
	) external nonReentrant onlySGRouter {
		(bytes32 transactionId, LibSwap.SwapData[] memory swapData, address receiver) = abi.decode(
			_payload,
			(bytes32, LibSwap.SwapData[], address)
		);

		_swapAndCompleteBridgeTokens(
			transactionId,
			swapData,
			swapData.length > 0 ? swapData[0].sendingAssetId : _token, // If swapping assume sent token is the first token in swapData
			payable(receiver),
			_amountLD,
			true
		);
	}

	/// @notice Performs a swap before completing a cross-chain transaction
	/// @param _transactionId the transaction id associated with the operation
	/// @param _swapData array of data needed for swaps
	/// @param assetId token received from the other chain
	/// @param receiver address that will receive tokens in the end
	function swapAndCompleteBridgeTokens(
		bytes32 _transactionId,
		LibSwap.SwapData[] memory _swapData,
		address assetId,
		address payable receiver
	) external payable nonReentrant {
		if (LibAsset.isNativeAsset(assetId)) {
			_swapAndCompleteBridgeTokens(_transactionId, _swapData, assetId, receiver, msg.value, false);
		} else {
			uint256 allowance = IERC20(assetId).allowance(msg.sender, address(this));
			LibAsset.depositAsset(assetId, allowance);
			_swapAndCompleteBridgeTokens(_transactionId, _swapData, assetId, receiver, allowance, false);
		}
	}

	/// @notice Send remaining token to receiver
	/// @param assetId token received from the other chain
	/// @param receiver address that will receive tokens in the end
	/// @param amount amount of token
	function pullToken(address assetId, address payable receiver, uint256 amount) external onlyOwner {
		if (LibAsset.isNativeAsset(assetId)) {
			// solhint-disable-next-line avoid-low-level-calls
			(bool success, ) = receiver.call{value: amount}("");
			if (!success) revert ExternalCallFailed();
		} else {
			IERC20(assetId).safeTransfer(receiver, amount);
		}
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

		if (LibAsset.isNativeAsset(assetId)) {
			// case 1: native asset
			uint256 cacheGasLeft = gasleft();
			if (reserveRecoverGas && cacheGasLeft < _recoverGas) {
				// case 1a: not enough gas left to execute calls
				// solhint-disable-next-line avoid-low-level-calls
				(bool success, ) = receiver.call{value: amount}("");
				if (!success) revert ExternalCallFailed();

				emit KanaTransferRecovered(_transactionId, assetId, receiver, amount, block.timestamp);
				return;
			}

			// case 1b: enough gas left to execute calls
			// solhint-disable no-empty-blocks
			try
				executor.swapAndCompleteBridgeTokens{value: amount, gas: cacheGasLeft - _recoverGas}(
					_transactionId,
					_swapData,
					assetId,
					receiver
				)
			{} catch {
				// solhint-disable-next-line avoid-low-level-calls
				(bool success, ) = receiver.call{value: amount}("");
				if (!success) revert ExternalCallFailed();

				emit KanaTransferRecovered(_transactionId, assetId, receiver, amount, block.timestamp);
			}
		} else {
			// case 2: ERC20 asset
			uint256 cacheGasLeft = gasleft();
			IERC20 token = IERC20(assetId);
			token.safeApprove(address(executor), 0);

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
	}

	/// @notice Receive native asset directly.
	/// @dev Some bridges may send native asset before execute external calls.
	// solhint-disable-next-line no-empty-blocks
	receive() external payable {}
}

