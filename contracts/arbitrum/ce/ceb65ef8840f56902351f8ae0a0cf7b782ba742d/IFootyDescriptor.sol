// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import {IFootySeeder} from "./IFootySeeder.sol";

interface IFootyDescriptor {
    function heads(uint256 index) external view returns (bytes memory);

    function colorCount() external view returns (uint256);

    function backgroundCount() external view returns (uint256);

    function kitCount() external view returns (uint256);

    function commonHeadCount() external view returns (uint256);

    function rareHeadCount() external view returns (uint256);

    function legendaryHeadCount() external view returns (uint256);

    function headCount() external view returns (uint256);

    function getCommonHead(uint256 index) external view returns (uint256);

    function getRareHead(uint256 index) external view returns (uint256);

    function getLegendaryHead(uint256 index) external view returns (uint256);

    function glassesCount() external view returns (uint256);

    function addManyColorsToPalette(string[] calldata manyColors) external;

    function addManyBackgrounds(string[] calldata manyBackgrounds) external;

    function addManyKits(bytes[] calldata manyKits) external;

    function addManyCommonHeads(bytes[] calldata manyHeads) external;

    function addManyRareHeads(bytes[] calldata manyHeads) external;

    function addManyLegendaryHeads(bytes[] calldata manyHeads) external;

    function addManyGlasses(bytes[] calldata manyGlasses) external;

    function tokenURI(uint256 tokenId, IFootySeeder.FootySeed memory seed)
        external
        view
        returns (string memory);

    function renderFooty(uint256 tokenId, IFootySeeder.FootySeed memory seed)
        external
        view
        returns (string memory);
}

