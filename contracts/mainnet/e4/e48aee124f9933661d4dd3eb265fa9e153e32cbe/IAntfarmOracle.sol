// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

interface IAntfarmOracle {
    function pair() external view returns (address);

    function token1() external view returns (address);

    function consult(address, uint256) external view returns (uint256);

    function update(uint256, uint32) external;
}

