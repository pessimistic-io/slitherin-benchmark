// SPDX-License-Identifier: MIT 
pragma solidity >0.8.0;

import "./IMessageTransmitter.sol";
import "./ITokenMessendger.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

contract Worker is Ownable
{
	using SafeERC20 for IERC20Metadata;

	IMessageTransmitter private messageTransmitter;
	ITokenMessendger private tokenMessendger;
	bool private isInitialized;
	uint32 private destinationDomain;
	IERC20Metadata private asset;

	constructor() Ownable(_msgSender()) {}

	function init(ITokenMessendger _tokenMessendger,
		uint32 _destinationDomain,
		IMessageTransmitter _messageTransmitter,
		IERC20Metadata _asset)
		external
	{
		require(!isInitialized, "already initialized");
		_transferOwnership(_msgSender());
		isInitialized = true;
		tokenMessendger = _tokenMessendger;
		destinationDomain = _destinationDomain;
		messageTransmitter = _messageTransmitter;
		asset = _asset;
	}

	function sendAssets(uint256 amount) external onlyOwner returns(uint64)
	{
		asset.safeIncreaseAllowance(address(tokenMessendger), type(uint256).max);
		
		return tokenMessendger.depositForBurn(amount, destinationDomain, bytes32(abi.encode(address(this))), address(asset));
	}

	function pullAssets(uint256 minAmount, bytes calldata exitData, bytes calldata attestation)
		external
		onlyOwner
		returns (uint256 received)
	{
		received = asset.balanceOf(address(this));
		if (received < minAmount)
			messageTransmitter.receiveMessage(exitData, attestation);
		
		received = asset.balanceOf(address(this));
		asset.safeTransfer(owner(), received);
	}
}
