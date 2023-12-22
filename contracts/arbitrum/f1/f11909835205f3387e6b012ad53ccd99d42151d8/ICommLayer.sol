pragma solidity ^0.8.9;

interface ICommLayer {
    function sendMsg(bytes memory, bytes memory) external payable;
}

