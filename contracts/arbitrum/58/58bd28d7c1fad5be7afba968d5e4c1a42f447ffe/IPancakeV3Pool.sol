// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

interface IPancakeV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}
