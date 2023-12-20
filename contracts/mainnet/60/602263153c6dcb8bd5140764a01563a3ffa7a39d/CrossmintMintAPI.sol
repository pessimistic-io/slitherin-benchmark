// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

abstract contract CrossmintMintAPI {
    function getVersion() public view virtual returns (string memory);

    function getTreasury() public view virtual returns (address);

    function owner() public view virtual returns (address);
}

