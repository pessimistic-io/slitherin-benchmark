// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IFactory {
    function pairFee(address pair) external view returns (uint);
    function getFee(bool) external view returns(uint);
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address);
}
