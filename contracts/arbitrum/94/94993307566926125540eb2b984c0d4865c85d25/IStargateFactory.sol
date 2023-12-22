pragma solidity ^0.8.0;

interface IStargateFactory {
    function getPool(uint256) external view returns (address);
}

