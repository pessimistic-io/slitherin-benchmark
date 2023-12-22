// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IDegen {
    function mint(address to, uint256 amount) external;

    function burnFrom(address to, uint256 amount) external;
}

