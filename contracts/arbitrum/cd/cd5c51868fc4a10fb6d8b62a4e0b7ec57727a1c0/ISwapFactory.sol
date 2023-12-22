// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ISwapFactory {
    function allPairsLength() external view returns (uint);
    function isPair(address pair) external view returns (bool);
    function pairCodeHash() external pure returns (bytes32);
    function getPair(address tokenA, address token, bool stable) external view returns (address);
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);
    function fee(bool stable) external view returns (uint);
    function feeCollector() external view returns (address);
    function setFeeTier(bool stable, uint fee) external;
    function admin() external view returns (address);
    function setAdmin(address _admin) external;
}
