// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721Upgradeable.sol";

interface IOpenBlox is IERC721Upgradeable {
    struct Blox {
        uint256 genes;
        uint256 bornAt;
        uint16 generation;
        uint256 parent0Id;
        uint256 parent1Id;
        uint256 ancestorCode;
        uint8 reproduction;
    }

    function getBlox(uint256 tokenId)
        external
        view
        returns (
            uint256 genes,
            uint256 bornAt,
            uint16 generation,
            uint256 parent0Id,
            uint256 parent1Id,
            uint256 ancestorCode,
            uint8 reproduction
        );

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

    function burnBlox(uint256 tokenId) external;

    function increaseReproduction(uint256 tokenId) external;
}

