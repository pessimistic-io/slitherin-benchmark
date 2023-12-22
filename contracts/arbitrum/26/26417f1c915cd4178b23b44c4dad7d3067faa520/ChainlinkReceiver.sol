// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {CCIPReceiver} from "./CCIPReceiver.sol";
import {Client} from "./Client.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IRainbowRoad} from "./IRainbowRoad.sol";

/**
 * Receives messages from Chainlink CCIP router
 */
contract ChainlinkReceiver is ArcBaseWithRainbowRoad, CCIPReceiver 
{
    mapping(uint64 => mapping(address => bool)) public messageSenders;
    
    event MessageReceived(bytes32 messageId, uint64 sourceChainSelector, address messageSender, string action, address actionRecipient);

    constructor(address _rainbowRoad, address _router) CCIPReceiver(_router) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
    }
    
    function enableMessageSender(uint64 sourceChainSelector, address messageSender) external onlyOwner
    {
        require(!messageSenders[sourceChainSelector][messageSender], 'Message sender for source chain is enabled');
        messageSenders[sourceChainSelector][messageSender] = true;
    }
    
    function disableMessageSender(uint64 sourceChainSelector, address messageSender) external onlyOwner
    {
        require(messageSenders[sourceChainSelector][messageSender], 'Message sender for source chain is disabled');
        messageSenders[sourceChainSelector][messageSender] = false;
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override
    {
        _requireNotPaused();
        
        bytes32 messageId = message.messageId;
        uint64 sourceChainSelector = message.sourceChainSelector;
        address messageSender = abi.decode(message.sender, (address));
        require(messageSenders[sourceChainSelector][messageSender], 'Unsupported source chain/message sender');
        
        (string memory action, address actionRecipient, bytes memory payload) = abi.decode(message.data, (string, address, bytes));

        rainbowRoad.receiveAction(action, actionRecipient, payload);

        emit MessageReceived(messageId, sourceChainSelector, messageSender, action, actionRecipient);
    }

    receive() external payable {}
}

