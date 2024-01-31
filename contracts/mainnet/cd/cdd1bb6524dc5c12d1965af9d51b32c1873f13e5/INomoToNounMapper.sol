// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.6;

interface INomoToNounMapper {
    function getNounId(
        uint256 tokenId
    ) external view returns (uint256);
}

