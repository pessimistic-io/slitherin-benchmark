// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.2;

interface ISwapRouter {
    function factory() external pure returns (address);
    function WETH9() external pure returns (address);
}
