// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPairFactory {
    function allPairsLength() external view returns (uint);

    function isPair(address pair) external view returns (bool);

    function pairCodeHash() external view returns (bytes32);

    function getPair(
        address tokenA,
        address token,
        bool stable
    ) external view returns (address);

    function createPair(
        address tokenA,
        address tokenB,
        bool stable
    ) external returns (address pair);

    function voter() external view returns (address);

    function allPairs(uint256) external view returns (address);

    function pairFee(address) external view returns (uint256);
}

