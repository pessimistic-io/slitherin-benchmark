// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IKana} from "./IKana.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibAllowList} from "./LibAllowList.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SwapperV2, LibSwap} from "./SwapperV2.sol";
import {Validatable} from "./Validatable.sol";
import {LibUtil} from "./LibUtil.sol";
import {InvalidReceiver, ContractCallNotAllowed, IsNotOwner} from "./GenericErrors.sol";
import {LibDiamond} from "./LibDiamond.sol";

/// @title Generic Swap Facet
/// @author KANA
/// @notice Provides functionality for swapping through ANY APPROVED DEX
/// @dev Uses calldata to execute APPROVED arbitrary methods on DEXs
contract GenericSwapFacet is IKana, ReentrancyGuard, SwapperV2, Validatable {
	/// Events ///

	struct FeeData {
		address kanaWallet;
		address integrator;
		uint256 kanaFee;
		uint256 integratorFee;
	}

	event KanaSwappedGeneric(
		bytes32 indexed transactionId,
		string integrator,
		string referrer,
		address fromAssetId,
		address toAssetId,
		uint256 fromAmount,
		uint256 toAmount
	);
	event IntegratorFeeSent(bytes32 indexed transactionId, address integrator, address token, uint256 fee);
	event KanaFeeSent(bytes32 indexed transactionId, address kanaWallet, address token, uint256 fee);

	/// External Methods ///

	/// @notice Performs multiple swaps in one transaction
	/// @param _transactionId the transaction id associated with the operation
	/// @param _integrator the name of the integrator
	/// @param _referrer the address of the referrer
	/// @param _receiver the address to receive the swapped tokens into (also excess tokens)
	/// @param _minAmount the minimum amount of the final asset to receive
	/// @param _swapData an object containing swap related data to perform swaps before bridging
	function swapTokensGeneric(
		bytes32 _transactionId,
		string calldata _integrator,
		string calldata _referrer,
		address payable _receiver,
		uint256 _minAmount,
		FeeData calldata _feeData,
		LibSwap.SwapData[] calldata _swapData
	) external payable refundExcessNative(_receiver) nonReentrant {
		if (LibUtil.isZeroAddress(_receiver)) {
			revert InvalidReceiver();
		}

	uint256 postSwapBalance = _depositAndSwap(_transactionId, _minAmount, _swapData, _receiver);
	 address receivingAssetId = _swapData[_swapData.length - 1].receivingAssetId;
		if (_feeData.integrator != address(0)) {
			LibAsset.transferAsset(receivingAssetId, payable(_feeData.integrator), _feeData.integratorFee);
			emit IntegratorFeeSent(_transactionId, _feeData.integrator, receivingAssetId, _feeData.integratorFee);
		}
		if (_feeData.kanaWallet != address(0)) {
			LibAsset.transferAsset(receivingAssetId, payable(_feeData.kanaWallet), _feeData.kanaFee);
			emit KanaFeeSent(_transactionId, _feeData.kanaWallet, receivingAssetId, _feeData.kanaFee);
		}
		postSwapBalance = postSwapBalance - (_feeData.integratorFee + _feeData.kanaFee);
		LibAsset.transferAsset(receivingAssetId, _receiver, postSwapBalance);

		emit KanaSwappedGeneric(
			_transactionId,
			_integrator,
			_referrer,
			_swapData[0].sendingAssetId,
			receivingAssetId,
			_swapData[0].fromAmount,
			postSwapBalance
		);
	}
}

