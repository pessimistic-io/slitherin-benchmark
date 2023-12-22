// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import "./extensions_IERC20Metadata.sol";

interface IWETH is IERC20Metadata {
    function deposit() external payable;

    function withdraw(uint wad) external;
}

