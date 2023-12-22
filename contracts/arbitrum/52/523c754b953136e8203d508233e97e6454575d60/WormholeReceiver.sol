// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IWormholeRelayer.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {LibSwap} from "./LibSwap.sol";
import {LibAsset} from "./LibAsset.sol";
import {IKana} from "./IKana.sol";
import {IExecutor} from "./IExecutor.sol";
import {IStargateReceiver} from "./IStargateReceiver.sol";
import {IWormholeReceiver} from "./IWormholeReceiver.sol";
import {IWormholeRelayer} from "./IWormholeRelayer.sol";
import {ITokenBridge} from "./ITokenBridge.sol";
import {IWormhole} from "./IWormhole.sol";
import {TransferrableOwnership} from "./TransferrableOwnership.sol";
import {ExternalCallFailed, UnAuthorized} from "./GenericErrors.sol";

/// @title Executor
/// @author KANA
/// @notice Arbitrary execution contract used for cross-chain swaps and message passing
/// @custom:version 2.0.0
contract WormholeReceiver is IKana, ReentrancyGuard, TransferrableOwnership {
	using SafeERC20 for IERC20;

	/// Storage ///
	IExecutor public executor;
	uint256 public recoverGas;
	ITokenBridge private immutable wormholeRouter;
	IWormhole private immutable wormhole;

	address internal constant NON_EVM_ADDRESS = 0x11f111f111f111F111f111f111F111f111f111F1;
	/// Events ///
	event WormholeSet(address indexed router, address indexed core);
	event ExecutorSet(address indexed executor);
	event RecoverGasSet(uint256 indexed recoverGas);

	/// Constructor
	constructor(
		address _owner,
		address _wormhole,
		address _wormholeRouter,
		address _executor,
		uint256 _recoverGas
	) TransferrableOwnership(_owner) {
		owner = _owner;
		executor = IExecutor(_executor);
		wormhole = IWormhole(_wormhole);
		wormholeRouter = ITokenBridge(_wormholeRouter);
		recoverGas = _recoverGas;
		emit RecoverGasSet(_recoverGas);
		emit WormholeSet(address(wormholeRouter), address(wormhole));
	}

	/// External Methods ///
	function claimTokens(bytes[] memory additionalVaas) external payable {
		// IWormhole.VM memory parsedVM = wormhole.parseVM(additionalVaas[0]);
		// ITokenBridge.Transfer memory transfer = wormholeRouter.parseTransfer(parsedVM.payload);
		wormholeRouter.completeTransfer(additionalVaas[0]);

		// address wrappedTokenAddress = transfer.tokenChain == wormhole.chainId()
		// 	? fromWormholeFormat(transfer.tokenAddress)
		// 	: wormholeRouter.wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
		// IERC20(wrappedTokenAddress).transfer(recipient, amount); //
	}

	function claimAndSwapTokens(
		bytes32 _transactionId,
		bytes[] memory additionalVaas,
		LibSwap.SwapData[] calldata _swapData,
		address receiver,
		uint256 amount
	) external payable {
		wormholeRouter.completeTransfer(additionalVaas[0]);
		IWormhole.VM memory parsedVM = wormhole.parseVM(additionalVaas[0]);
		ITokenBridge.Transfer memory transfer = wormholeRouter.parseTransfer(parsedVM.payload);
		address wrappedTokenAddress = transfer.tokenChain == wormhole.chainId()
			? fromWormholeFormat(transfer.tokenAddress)
			: wormholeRouter.wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
		_swapAndCompleteBridgeTokens(_transactionId, _swapData, wrappedTokenAddress, payable(receiver), amount, false);
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

			//false				 (387184 	<	100000) false
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

function toWormholeFormat(address addr) pure returns (bytes32) {
	return bytes32(uint256(uint160(addr)));
}

function fromWormholeFormat(bytes32 whFormatAddress) pure returns (address) {
	if (uint256(whFormatAddress) >> 160 != 0) {
		revert NotAnEvmAddress(whFormatAddress);
	}
	return address(uint160(uint256(whFormatAddress)));
}

function getDecimals(address tokenAddress) view returns (uint8 decimals) {
	// query decimals
	(, bytes memory queriedDecimals) = address(tokenAddress).staticcall(abi.encodeWithSignature("decimals()"));
	decimals = abi.decode(queriedDecimals, (uint8));
}

