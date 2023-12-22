// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {ILayerZeroReceiver} from "./ILayerZeroReceiver.sol";
import {ILayerZeroEndpoint} from "./ILayerZeroEndpoint.sol";
import {IRainbowRoad} from "./IRainbowRoad.sol";

/**
 * Receives messages from LayerZero endpoint
 */
contract LayerZeroReceiver is ArcBaseWithRainbowRoad, ILayerZeroReceiver 
{
    ILayerZeroEndpoint public endpoint;
    mapping(uint16 => mapping(bytes => bool)) public messageSenders;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;
    
    event MessageReceived(uint64 sourceChainSelector, bytes sourceAddress, uint64 nonce, string action, address actionRecipient);
    event MessageFailed(uint16 sourceChainSelector, bytes sourceAddress, uint64 nonce, bytes payload);
    event RetryMessageSuccess(uint16 sourceChainSelector, bytes sourceAddress, uint64 nonce, bytes32 payloadHash);
    event RetryMessageAdded(uint16 sourceChainSelector, bytes sourceAddress, uint64 nonce, bytes payload);
    event RetryMessageRemoved(uint16 sourceChainSelector, bytes sourceAddress, uint64 nonce, bytes payload);
    
    constructor(address _rainbowRoad, address _endpoint) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        require(_endpoint != address(0), 'LayerZero endpoint cannot be zero address');
        endpoint = ILayerZeroEndpoint(_endpoint);
    }
    
    function setEndpoint(address _endpoint) external onlyOwner
    {
        require(_endpoint != address(0), 'LayerZero endpoint cannot be zero address');
        endpoint = ILayerZeroEndpoint(_endpoint);
    }
    
    function enableMessageSender(uint16 sourceChainSelector, address remoteAddress, address localAddress) external onlyOwner
    {
        require(remoteAddress != address(0), 'Remote address cannot be zero address');
        require(localAddress != address(0), 'Local address cannot be zero address');
        bytes memory trustedRemote = abi.encodePacked(remoteAddress, localAddress);
        
        require(!messageSenders[sourceChainSelector][trustedRemote], 'Message sender for source chain is enabled');
        messageSenders[sourceChainSelector][trustedRemote] = true;
        trustedRemoteLookup[sourceChainSelector] = trustedRemote;
    }
    
    function disableMessageSender(uint16 sourceChainSelector, address remoteAddress, address localAddress) external onlyOwner
    {
        require(remoteAddress != address(0), 'Remote address cannot be zero address');
        require(localAddress != address(0), 'Local address cannot be zero address');
        bytes memory trustedRemote = abi.encodePacked(remoteAddress, localAddress);
        
        require(messageSenders[sourceChainSelector][trustedRemote], 'Message sender for source chain is disabled');
        messageSenders[sourceChainSelector][trustedRemote] = false;
        delete trustedRemoteLookup[sourceChainSelector];
    }
  
    function lzReceive(uint16 sourceChainSelector, bytes calldata sourceAddress, uint64 nonce, bytes calldata message) public virtual override whenNotPaused
    {   
        require(msg.sender == address(endpoint), "Invalid endpoint caller");

        bytes memory trustedRemote = trustedRemoteLookup[sourceChainSelector];
        
        require(
            sourceAddress.length == trustedRemote.length && trustedRemote.length > 0 && keccak256(sourceAddress) == keccak256(trustedRemote) && messageSenders[sourceChainSelector][sourceAddress],
            "Unsupported source chain/message sender"
        );

        try this.handleReceive(sourceChainSelector, sourceAddress, nonce, message) {
            
        } catch {
            failedMessages[sourceChainSelector][sourceAddress][nonce] = keccak256(message);
            emit MessageFailed(sourceChainSelector, sourceAddress, nonce, message);
        }
    }
    
    function handleReceive(uint16 sourceChainSelector, bytes calldata sourceAddress, uint64 nonce, bytes calldata message) public 
    {
        require(msg.sender == address(this), "Invalid caller");
        
        (string memory action, address actionRecipient, bytes memory payload) = abi.decode(message, (string, address, bytes));

        rainbowRoad.receiveAction(action, actionRecipient, payload);
        
        emit MessageReceived(sourceChainSelector, sourceAddress, nonce, action, actionRecipient);
    }
    
    function retryMessage(uint16 sourceChainSelector, bytes calldata sourceAddress, uint64 nonce, bytes calldata message) public virtual 
    {
        // assert there is message to retry
        bytes32 payloadHash = failedMessages[sourceChainSelector][sourceAddress][nonce];
        require(payloadHash != bytes32(0), "Message not found");
        require(keccak256(message) == payloadHash, "Invalid payload");
        
        // clear the stored message
        delete failedMessages[sourceChainSelector][sourceAddress][nonce];
        
        // execute the message. revert if it fails again
        this.handleReceive(sourceChainSelector, sourceAddress, nonce, message);
        emit RetryMessageSuccess(sourceChainSelector, sourceAddress, nonce, payloadHash);
    }
    
    function addRetryMessage(uint16 sourceChainSelector, bytes calldata sourceAddress, uint64 nonce, bytes calldata message) public virtual onlyOwner
    {
        failedMessages[sourceChainSelector][sourceAddress][nonce] = keccak256(message);
        emit RetryMessageAdded(sourceChainSelector, sourceAddress, nonce, message);
    }
    
    function removeRetryMessage(uint16 sourceChainSelector, bytes calldata sourceAddress, uint64 nonce, bytes calldata message) public virtual onlyOwner
    {
        delete failedMessages[sourceChainSelector][sourceAddress][nonce];
        emit RetryMessageRemoved(sourceChainSelector, sourceAddress, nonce, message);
    }

    receive() external payable {}
}

