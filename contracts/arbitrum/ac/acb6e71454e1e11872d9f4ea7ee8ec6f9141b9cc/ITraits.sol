// SPDX-License-Identifier: MIT LICENSE
import "./Strings.sol";

pragma solidity ^0.8.0;

interface ITraits {
    struct Trait {
        string name;
        string svg;
    }

    /** ADMIN */
    function uploadTraits(
        uint256 ghostOrBuster,
        uint256 traitType,
        uint256[] calldata traitIds,
        Trait[] calldata traits
    ) external;

    function setPeekABoo(address _peekaboo) external;

    /** RENDER */
    function tryOutTraits(
        uint256 tokenId,
        uint256[2][] memory traitsToTry,
        uint256 width,
        uint256 height
    ) external view returns (string memory);

    function compileAttributesAsIDs(uint256 tokenId)
        external
        view
        returns (string memory);

    function setRarityIndex(
        uint256 ghostOrBuster,
        uint256 traitType,
        uint256[4] calldata traitIndices
    ) external;

    function getRarityIndex(
        uint256 ghostOrBuster,
        uint256 traitType,
        uint256 rarity
    ) external returns (uint256);

    function tokenURI(uint256 tokenId) external view returns (string memory);
}

