// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.5;

interface IZaynZapV2TakaDAO {
    function zapInEth(address vault, uint256 termID) external payable;

    function zapOutETH(address vault, uint256 _shares, uint256 termID) external returns (uint);
}

