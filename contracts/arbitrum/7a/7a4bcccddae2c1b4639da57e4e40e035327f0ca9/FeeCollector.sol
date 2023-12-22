// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {LibAsset} from "./LibAsset.sol";
import {IKana} from "./IKana.sol";

/// @title Fee Collector
/// @author kana
/// @notice Provides functionality for collecting integrator fees
/// @custom:version 1.0.0
contract FeeCollector is IKana {
	event IntegratorFeeSent(bytes32 indexed transactionId, address integrator, address token, uint256 fee);
	event KanaFeeSent(bytes32 indexed transactionId, address kanaWallet, address token, uint256 fee);

	function _sendFee(BridgeData memory _bridgeData) internal returns (uint256) {
		if (_bridgeData.integrator != address(0) && _bridgeData.integratorFee != 0) {
			LibAsset.transferAsset(
				_bridgeData.sendingAssetId,
				payable(_bridgeData.integrator),
				_bridgeData.integratorFee
			);
			emit IntegratorFeeSent(
				_bridgeData.transactionId,
				_bridgeData.integrator,
				_bridgeData.sendingAssetId,
				_bridgeData.integratorFee
			);
		}

		if (_bridgeData.kanaWallet != address(0) && _bridgeData.kanaFee != 0) {
			LibAsset.transferAsset(_bridgeData.sendingAssetId, payable(_bridgeData.kanaWallet), _bridgeData.kanaFee);
			emit KanaFeeSent(
				_bridgeData.transactionId,
				_bridgeData.kanaWallet,
				_bridgeData.sendingAssetId,
				_bridgeData.kanaFee
			);
		}

		return _bridgeData.minAmount - (_bridgeData.integratorFee + _bridgeData.kanaFee);
	}
}

