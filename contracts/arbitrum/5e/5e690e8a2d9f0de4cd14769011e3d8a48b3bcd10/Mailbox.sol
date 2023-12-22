// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IZKBridgeEntrypoint.sol";
import "./IZKBridgeReceiver.sol";

/// @title Mailbox
/// @notice An example contract for receiving messages from other chains
contract Mailbox is IZKBridgeReceiver {

    event MessageReceived(uint64 indexed sequence, uint32 indexed sourceChainId, address indexed sourceAddress, address sender, address recipient, string message);

    struct Msg {
        address sender;
        string message;
    }

    address private zkBridgeReceiver;

    // recipient=>Msg
    mapping(address => Msg[]) public messages;

    constructor(address _zkBridgeReceiver) {
        zkBridgeReceiver = _zkBridgeReceiver;
    }

    // @notice ZKBridge endpoint will invoke this function to deliver the message on the destination
    // @param srcChainId - the source endpoint identifier
    // @param srcAddress - the source sending contract address from the source chain
    // @param sequence - the ordered message nonce
    // @param message - the signed payload is the UA bytes has encoded to be sent
    function zkReceive(uint16 srcChainId, address srcAddress, uint64 sequence, bytes calldata payload) external override {
        require(msg.sender == zkBridgeReceiver, "Not From ZKBridgeReceiver");
        (address sender,address recipient,string memory message) = abi.decode(payload, (address, address, string));
        messages[recipient].push(Msg(sender, message));
        emit MessageReceived(sequence, srcChainId, srcAddress, sender, recipient, message);
    }

    function messagesLength(address recipient) external view returns (uint256) {
        return messages[recipient].length;
    }

}

