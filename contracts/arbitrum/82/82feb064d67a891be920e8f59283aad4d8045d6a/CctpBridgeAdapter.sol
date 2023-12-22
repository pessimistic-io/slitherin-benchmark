// SPDX-License-Identifier: MIT 
pragma solidity >0.8.0;

import "./IMessageTransmitter.sol";
import "./ITokenMessendger.sol";
import "./IBridgeAdapter.sol";
import "./ICrossLedgerVault.sol";
import "./Worker.sol";
import "./Initializable.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./Clones.sol";


struct TransferData
{
    bytes32 nonce;
    uint256 dstChainId;
    uint256 value;
    address to;
    bool notifyVault;
    uint8 slippage;
}

contract CctpBridgeAdapter is IBridgeAdapter, Initializable
{
	using SafeERC20 for IERC20Metadata;

	ICrossLedgerVault public crossLedgerVault;

	ITokenMessendger public tokenMessendger;

	IMessageTransmitter public messageTransmitter;

	IERC20Metadata public asset;

	address internal workerImplementation;

	uint256 nonce = 0;
	uint256 public dstChainId;
	uint32 public destinationDomain;

	event AssetsSent(
		bytes32 transferId,
		address worker,
		address asset,
		uint256 dstChainId,
		uint256 value,
		address to,
		bytes data
	);

	event AssetsReceived(bytes32 transferId);

	function initialize(
		ICrossLedgerVault _crossLedgerVault,
		uint256 _dstChainId,
		ITokenMessendger _tokenMessendger,
		uint32 _destinationDomain,
		IMessageTransmitter _messageTransmitter
	) public initializer
	{
		crossLedgerVault = _crossLedgerVault;
		workerImplementation = address(new Worker());
		dstChainId = _dstChainId;
		tokenMessendger = _tokenMessendger;
		destinationDomain = _destinationDomain;
		messageTransmitter = _messageTransmitter;

		asset = IERC20Metadata(crossLedgerVault.mainAsset());
	}

	// deploys proxy by given salt
	function _deployWorkerProxy(bytes32 salt) internal returns (Worker) {
		address proxy = Clones.cloneDeterministic(workerImplementation, salt); 
		Worker(proxy).init(tokenMessendger, destinationDomain, messageTransmitter, asset);
		return Worker(proxy);
	}

	// deploys worker on source chain and performs sending from it
	// to - address(0) in case of root vault deposit
	function sendAssets(
		uint256 value,
		address to,
		uint8 slippage
	) external override returns (bytes32 transferId)
	{
		bool notifyVault = (msg.sender == address(crossLedgerVault));
		require((to != address(0)) || (notifyVault), "Can't deposit to vault without notification");
		
		bytes memory data = abi.encode(TransferData({
			nonce: keccak256(abi.encode(nonce++, uint256(block.chainid), address(this))),
			dstChainId: dstChainId,
			value: value,
			to: to,
			notifyVault: notifyVault,
			slippage: slippage})
		);

		transferId = keccak256(data);
		Worker worker = _deployWorkerProxy(transferId);
		asset.safeTransferFrom(msg.sender, address(worker), value);
		
		worker.sendAssets(value);
		emit AssetsSent(
			transferId,
			address(worker),
			address(asset),
			dstChainId,
			value,
			to,
			data
		);
	}

	// deploys worker on destination chain and sends asset to destination
	function pullAssets(bytes memory data, bytes calldata exitData, bytes calldata attestation)
		external
		returns (uint256 pooled)
	{
		bytes32 transferId = keccak256(data);
		TransferData memory transferData = abi.decode(data, (TransferData));

		require(transferData.dstChainId == block.chainid, "that is not the destination chain");

		Worker worker = _deployWorkerProxy(transferId);
		pooled = worker.pullAssets(transferData.value, exitData, attestation);

		require(pooled >= transferData.value, "value is not enough");

		address receiver = transferData.to == address(0) ? address(crossLedgerVault) : transferData.to;
        asset.safeTransfer(receiver, pooled);

		if (transferData.notifyVault) {
            crossLedgerVault.transferCompleted(transferId, pooled, transferData.slippage);
        }

		emit AssetsReceived(transferId);
	}
}

