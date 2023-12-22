// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./ERC165.sol";

import "./WormholeStructs.sol";
import "./IWormhole.sol";
import "./ICATERC20.sol";
import "./Governance.sol";
import "./Structs.sol";

contract CATERC20 is Context, ERC20, CATERC20Governance, CATERC20Events, ERC165 {
	using SafeERC20 for IERC20;
	
	constructor(string memory name, string memory symbol, uint8 decimal) ERC20(name, symbol) {
		setEvmChainId(block.chainid);
		setDecimals(decimal);
	}
	
	function initialize(
		uint16 chainId,
		address wormhole,
		uint8 finality,
		uint256 maxSupply
	) public onlyOwner {
		require(isInitialized() == false, "Already Initialized");
		
		setChainId(chainId);
		setWormhole(wormhole);
		setFinality(finality);
		setMaxSupply(maxSupply);
		setMintedSupply(0);
		setIsInitialized();
	}
	
	function decimals() public view virtual override returns (uint8) {
		return getDecimals();
	}
	
	function supportsInterface(
		bytes4 interfaceId
	) public view virtual override(ERC165) returns (bool) {
		return interfaceId == type(ICATERC20).interfaceId || super.supportsInterface(interfaceId);
	}
	
	/**
	 * @dev To bridge tokens to other chains.
     */
	function bridgeOut(
		uint256 amount,
		uint16 recipientChain,
		bytes32 recipient,
		uint32 nonce
	) external payable returns (uint64 sequence) {
		require(isInitialized() == true, "Not Initialized");
		require(evmChainId() == block.chainid, "unsupported fork");
		
		uint256 fee = wormhole().messageFee();
		require(msg.value >= fee, "Not enough fee provided to publish message");
		uint16 tokenChain = wormhole().chainId();
		bytes32 tokenAddress = bytes32(uint256(uint160(address(this))));
		
		_burn(_msgSender(), amount);
		
		CATERC20Structs.CrossChainPayload memory transfer = CATERC20Structs.CrossChainPayload({
			amount: amount,
			tokenAddress: tokenAddress,
			tokenChain: tokenChain,
			toAddress: recipient,
			toChain: recipientChain,
			tokenDecimals: getDecimals()
		});
		
		sequence = wormhole().publishMessage{value: msg.value}(
			nonce,
			encodeTransfer(transfer),
			finality()
		);
		
		emit bridgeOutEvent(
			amount,
			tokenChain,
			recipientChain,
			addressToBytes(_msgSender()),
			recipient
		);
	} // end of function
	
	function bridgeIn(bytes memory encodedVm) external returns (bytes memory) {
		require(isInitialized() == true, "Not Initialized");
		require(evmChainId() == block.chainid, "unsupported fork");
		
		(IWormhole.VM memory vm, bool valid, string memory reason) = wormhole().parseAndVerifyVM(
			encodedVm
		);
		require(valid, reason);
		require(
			bytesToAddress(vm.emitterAddress) == address(this) ||
			tokenContracts(vm.emitterChainId) == vm.emitterAddress,
			"Invalid Emitter"
		);
		
		CATERC20Structs.CrossChainPayload memory transfer = decodeTransfer(vm.payload);
		address transferRecipient = bytesToAddress(transfer.toAddress);
		
		require(!isTransferCompleted(vm.hash), "transfer already completed");
		setTransferCompleted(vm.hash);
		
		require(transfer.toChain == wormhole().chainId(), "invalid target chain");
		
		uint256 nativeAmount = normalizeAmount(
			transfer.amount,
			transfer.tokenDecimals,
			getDecimals()
		);
		
		_mint(transferRecipient, nativeAmount);
		
		emit bridgeInEvent(nativeAmount, transfer.tokenChain, transfer.toChain, transfer.toAddress);
		
		return vm.payload;
	}
	
	function mint(address recipient, uint256 amount) public onlyOwner {
		require(mintedSupply() + amount <= maxSupply(), "MAX SUPPLY REACHED");
		setMintedSupply(mintedSupply() + amount);
		_mint(recipient, amount);
	}
}

