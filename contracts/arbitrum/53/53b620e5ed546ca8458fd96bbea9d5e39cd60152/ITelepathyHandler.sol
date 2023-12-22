pragma solidity 0.8.17;

interface ITelepathyHandler {
    function handleTelepathy(uint32 sourceChainId, address sourceSender, bytes memory data) external returns (bytes4);
}

