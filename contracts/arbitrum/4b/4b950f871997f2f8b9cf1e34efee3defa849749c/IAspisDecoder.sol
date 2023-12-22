pragma solidity 0.8.10;

interface IAspisDecoder {
    function decodeExchangeInput(bytes calldata inputData) external returns(address, address, uint256, uint256, address);
}
