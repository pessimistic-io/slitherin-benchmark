// commit 4a1e464ba0e7d0bc60b79fcbe742d43c6c344f2a
pragma solidity ^0.8.0;

interface IStargateFactory {
    function getPool(uint256) external view returns (address);
}

