// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721.sol";

interface IOpenBloxL2 is IERC721 {
    function mintBlox(
        uint256 tokenId,
        address receiver,
        uint256 genes,
        uint256 bornAt,
        uint16 generation,
        uint256 parent0Id,
        uint256 parent1Id,
        uint256 ancestorCode,
        uint8 reproduction
    ) external;
}

