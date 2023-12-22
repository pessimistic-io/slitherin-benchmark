pragma solidity 0.8.17;

interface IRegistry {
    function getAllMarkets() external view returns (address[] memory);
}

