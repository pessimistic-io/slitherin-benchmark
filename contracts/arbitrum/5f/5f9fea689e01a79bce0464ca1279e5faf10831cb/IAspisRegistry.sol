pragma solidity 0.8.10;

interface IAspisRegistry {

    function register(string memory, address, address, address) external;

    function getDecoder(address) external returns(address);

    function getAspisSupportedTradingTokens() external returns(address[] memory);

    function getAspisSupportedTradingProtocols() external returns(address[] memory);

    function isAspisSupportedTradingToken(address) external returns(bool);

    function isAspisSupportedTradingProtocol(address) external returns(bool);
}

