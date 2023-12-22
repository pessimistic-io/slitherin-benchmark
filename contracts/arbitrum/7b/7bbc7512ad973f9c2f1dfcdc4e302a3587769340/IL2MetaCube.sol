// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IL2MetaCube {

    function mintForLevel(address to_, uint8 level_, uint256 levelStartTokenId_) external returns (uint256);

    function batchBurn(uint256[] calldata tokenIdArr) external;

}

