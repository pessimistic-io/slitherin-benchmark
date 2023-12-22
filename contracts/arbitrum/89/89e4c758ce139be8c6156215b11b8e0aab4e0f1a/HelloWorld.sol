// File: helloworld.sol


pragma solidity ^0.8.17;
contract HelloWorld {
    function get()public pure returns (string memory){
        return 'Hello Contracts';
    }
}