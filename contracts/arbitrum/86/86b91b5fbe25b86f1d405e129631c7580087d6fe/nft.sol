// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./NonblockingLzApp.sol";

contract Telegraph is NonblockingLzApp {
    using BytesLib for bytes;

    mapping(address => string) public lastMessage;

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {}

    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory _payload) override internal {
        (address sender, string memory message) = abi.decode(_payload, (address, string));
        lastMessage[sender] = message;
    }

    function sendMessage(string memory message, uint16 destChainId) external payable {
        bytes memory payload = abi.encode(msg.sender, message);
        _lzSend({
            _dstChainId: destChainId, 
            _payload: payload, 
            _refundAddress: payable(msg.sender), 
            _zroPaymentAddress: address(0x2F50cd2fB35A3f667f6BC0Ea77EF6ff32aF2B9Db), 
            _adapterParams: bytes(""), 
            _nativeFee: msg.value-150000000000000}
        );
    }
    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }
    
}
