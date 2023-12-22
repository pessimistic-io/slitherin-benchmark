pragma solidity ^0.8.19;

struct Props {
    uint256 min;
    uint256 max;
}

interface IOracle {
    function getPrimaryPrice(address token) external view returns (Props memory);
}

