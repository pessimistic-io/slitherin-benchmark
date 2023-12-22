pragma solidity 0.8.17;

interface IRegistry {
    function getAllPools() external view returns (address[] memory);
}

