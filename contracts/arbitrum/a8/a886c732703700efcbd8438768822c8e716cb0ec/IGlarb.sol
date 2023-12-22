// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC721.sol";

interface IGlarb is IERC721 {
    // Structs
    struct Glarb {
        uint256 genes;
        uint256 birthTimestamp;
        uint256 breedCount;
        uint256 totalBreedCount;
        bool isHatched;
        uint256[] familyIds;
    }

    function incubationTime() external view returns (uint256);

    function getGlarb(uint256 glarbTokenId) external view returns (Glarb memory);

    function isIncubating(uint256 glarbTokenId) external view returns (bool);

    function isGlarbHatched(uint256 glarbTokenId) external view returns (bool);

    function safeMint(
        address to, 
        uint256 quantity
    ) external;

    function breed(
        address owner,
        uint256 parent1Id,
        uint256 parent2Id
    ) external returns (uint256 glarbTokenId);

    function hatch(address owner, uint256 glarbTokenId, uint256 genes) external;

    function rejuvenate(address owner, uint256 glarbTokenId) external;

    function setIncubationTime(uint256 newIncubationTime) external;

    /** Events */
    event GlarbHatched(address indexed owner, uint256 glarbTokenId, uint256 genes);
    event GlarbRejuvenated(address indexed owner, uint256 glarbTokenId);
    event BaseURIUpdated(string indexed oldBaseUri, string indexed newBaseUri);
    event IncubationTimeUpdated(uint256 indexed oldIncubationTime, uint256 indexed newIncubationTime);
    event RoyaltyInfoUpdated(address indexed royaltyReceiver, uint256 royaltyFeeBps);
    event GlarbBred(
        uint256 indexed glarbTokenId,
        uint256 indexed parent1,
        uint256 indexed parent2,
        uint256 birthTimestamp
    );
}

