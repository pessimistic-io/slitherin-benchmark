// SPDX-License-Identifier: GPL-3.0

import {Ownable} from "./Ownable.sol";
import {Strings} from "./Strings.sol";

import {IFootySeeder} from "./IFootySeeder.sol";
import {IFootyDescriptor} from "./IFootyDescriptor.sol";

import "./Base64.sol";

pragma solidity ^0.8.0;

contract FootyDescriptor is IFootyDescriptor, Ownable {
    using Strings for uint256;
    using Strings for uint32;

    string[] public palette;

    string[] public backgrounds;

    bytes[] public kits;

    bytes[] public commonHeads;

    bytes[] public rareHeads;

    bytes[] public legendaryHeads;

    bytes[] public glasses;

    function colorCount() external view override returns (uint256) {
        return palette.length;
    }

    function backgroundCount() external view override returns (uint256) {
        return backgrounds.length;
    }

    function kitCount() external view override returns (uint256) {
        return kits.length;
    }

    function commonHeadCount() external view override returns (uint256) {
        return commonHeads.length;
    }

    function rareHeadCount() external view override returns (uint256) {
        return rareHeads.length;
    }

    function legendaryHeadCount() external view override returns (uint256) {
        return legendaryHeads.length;
    }

    function glassesCount() external view override returns (uint256) {
        return glasses.length;
    }

    function headCount() external view override returns (uint256) {
        return commonHeads.length + rareHeads.length + legendaryHeads.length;
    }

    function getCommonHead(uint256 index)
        external
        pure
        override
        returns (uint256)
    {
        return index;
    }

    function getRareHead(uint256 index)
        external
        view
        override
        returns (uint256)
    {
        return index + this.commonHeadCount();
    }

    function getLegendaryHead(uint256 index)
        external
        view
        override
        returns (uint256)
    {
        return index + this.commonHeadCount() + this.rareHeadCount();
    }

    // colors
    function addManyColorsToPalette(string[] calldata manyColors)
        external
        override
        onlyOwner
    {
        require(
            palette.length + manyColors.length <= 256,
            "Palettes can only hold 256 colors"
        );
        for (uint256 i = 0; i < manyColors.length; i++) {
            _addColorToPalette(manyColors[i]);
        }
    }

    function _addColorToPalette(string calldata _color) internal {
        palette.push(_color);
    }

    // backgrounds
    function addManyBackgrounds(string[] calldata manyBackgrounds)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < manyBackgrounds.length; i++) {
            _addBackground(manyBackgrounds[i]);
        }
    }

    function _addBackground(string calldata _background) internal {
        backgrounds.push(_background);
    }

    // kits
    function addManyKits(bytes[] calldata manyKits)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < manyKits.length; i++) {
            _addKit(manyKits[i]);
        }
    }

    function _addKit(bytes calldata _kit) internal {
        kits.push(_kit);
    }

    function swapKitAtIndex(uint32 index, bytes calldata _kit)
        external
        onlyOwner
    {
        kits[index] = _kit;
    }

    // heads
    function addManyCommonHeads(bytes[] calldata manyHeads)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < manyHeads.length; i++) {
            _addCommonHead(manyHeads[i]);
        }
    }

    function _addCommonHead(bytes calldata _head) internal {
        commonHeads.push(_head);
    }

    function swapCommonHeadAtIndex(uint32 index, bytes calldata _head)
        external
        onlyOwner
    {
        commonHeads[index] = _head;
    }

    function addManyRareHeads(bytes[] calldata manyHeads)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < manyHeads.length; i++) {
            _addRareHead(manyHeads[i]);
        }
    }

    function _addRareHead(bytes calldata _head) internal {
        rareHeads.push(_head);
    }

    function swapRareHeadAtIndex(uint32 index, bytes calldata _head)
        external
        onlyOwner
    {
        rareHeads[index] = _head;
    }

    function addManyLegendaryHeads(bytes[] calldata manyHeads)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < manyHeads.length; i++) {
            _addLegendaryHead(manyHeads[i]);
        }
    }

    function _addLegendaryHead(bytes calldata _head) internal {
        legendaryHeads.push(_head);
    }

    function swapLegendaryHeadAtIndex(uint32 index, bytes calldata _head)
        external
        onlyOwner
    {
        legendaryHeads[index] = _head;
    }

    function heads(uint256 index)
        external
        view
        override
        returns (bytes memory)
    {
        if (index < commonHeads.length) {
            return commonHeads[index];
        }

        if (index < rareHeads.length + commonHeads.length) {
            return rareHeads[index - commonHeads.length];
        }

        return legendaryHeads[index - commonHeads.length - rareHeads.length];
    }

    // glasses
    function addManyGlasses(bytes[] calldata manyGlasses)
        external
        override
        onlyOwner
    {
        for (uint256 i = 0; i < manyGlasses.length; i++) {
            _addGlasses(manyGlasses[i]);
        }
    }

    function _addGlasses(bytes calldata _glasses) internal {
        glasses.push(_glasses);
    }

    function _render(uint256 tokenId, IFootySeeder.FootySeed memory seed)
        internal
        view
        returns (string memory)
    {
        string memory image = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" shape-rendering="crispEdges" width="256" height="256">'
                '<rect width="100%" height="100%" fill="',
                backgrounds[seed.background],
                '" />',
                _renderRects(this.heads(seed.head)),
                _renderRects(kits[seed.kit]),
                _renderRects(glasses[seed.glasses]),
                "</svg>"
            )
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"image": "data:image/svg+xml;base64,',
                                Base64.encode(bytes(image)),
                                '", "name": "Footy Noun #',
                                tokenId.toString(),
                                '", "number":"',
                                seed.number.toString(),
                                '", "kit":"',
                                seed.kit.toString(),
                                '", "head":"',
                                seed.head.toString(),
                                '", "glasses":"',
                                seed.glasses.toString(),
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function _renderRects(bytes memory data)
        private
        view
        returns (string memory)
    {
        string[32] memory lookup = [
            "0",
            "1",
            "2",
            "3",
            "4",
            "5",
            "6",
            "7",
            "8",
            "9",
            "10",
            "11",
            "12",
            "13",
            "14",
            "15",
            "16",
            "17",
            "18",
            "19",
            "20",
            "21",
            "22",
            "23",
            "24",
            "25",
            "26",
            "27",
            "28",
            "29",
            "30",
            "31"
        ];

        string memory rects;
        uint256 drawIndex = 0;
        for (uint256 i = 0; i < data.length; i = i + 2) {
            uint8 runLength = uint8(data[i]); // we assume runLength of any non-transparent segment cannot exceed image width (32px)
            uint8 colorIndex = uint8(data[i + 1]);
            if (colorIndex != 0 && colorIndex != 1) {
                // transparent
                uint8 x = uint8(drawIndex % 32);
                uint8 y = uint8(drawIndex / 32);
                string memory color = "#000000";
                if (colorIndex > 1) {
                    color = palette[colorIndex - 1];
                }
                rects = string(
                    abi.encodePacked(
                        rects,
                        '<rect width="',
                        lookup[runLength],
                        '" height="1" x="',
                        lookup[x],
                        '" y="',
                        lookup[y],
                        '" fill="',
                        color,
                        '" />'
                    )
                );
            }
            drawIndex += runLength;
        }

        return rects;
    }

    function tokenURI(uint256 tokenId, IFootySeeder.FootySeed memory seed)
        public
        view
        override
        returns (string memory)
    {
        string memory data = _render(tokenId, seed);
        return data;
    }

    function renderFooty(uint256 tokenId, IFootySeeder.FootySeed memory seed)
        public
        view
        override
        returns (string memory)
    {
        string memory data = _render(tokenId, seed);
        return data;
    }
}

