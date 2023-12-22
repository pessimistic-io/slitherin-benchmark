// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IKana {
	/// Structs ///

	struct BridgeData {
		bytes32 transactionId;
		string bridge;
		address integrator;
		address kanaWallet;
		address referrer;
		address sendingAssetId;
		address receiver;
		uint256 minAmount;
		uint256 destinationChainId;
		bool hasSourceSwaps;
		bool hasDestinationCall;
		uint256 integratorFee;
		uint256 kanaFee;
	}

	/// Events ///

	event KanaTransferStarted(IKana.BridgeData bridgeData);

	event KanaTransferCompleted(
		bytes32 indexed transactionId,
		address receivingAssetId,
		address receiver,
		uint256 amount,
		uint256 timestamp
	);

	event KanaTransferRecovered(
		bytes32 indexed transactionId,
		address receivingAssetId,
		address receiver,
		uint256 amount,
		uint256 timestamp
	);
	
}

