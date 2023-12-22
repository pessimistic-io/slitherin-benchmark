// SPDX-License-Identifier: GPL-3.0

pragma solidity  ^0.8.9;

import "./Strings.sol";
import { Base64 } from "./base64.sol";

library GenerateSVG {
    using Strings for uint;

    struct NFTItemInfo {
        uint poolId;
        uint roundId;
        uint index;
    }

    function constructTokenURI(NFTItemInfo memory params)
        public
        pure
        returns (string memory)
    {
        string memory image = generateSVGImage(params);

        // prettier-ignore
        return string(
            abi.encodePacked(
                'data:image/svg+xml;base64,',
                image
            )
        );
    }

    function generateSVG(NFTItemInfo memory params)
        internal
        pure
        returns (string memory svg)
    {
        // prettier-ignore
        return string(
            abi.encodePacked(
                '<svg width="1244" height="1244" viewBox="0 0 1244 1244" fill="none" xmlns="http://www.w3.org/2000/svg">',
                '<rect width="1244" height="1244" fill="black"/>',
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M453 530.309L615.851 455L628 481.692L465.148 557L453 530.309Z" fill="#5D53C5"/>',
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M627.158 455L790 530.311L777.842 557L615 481.691L627.158 455Z" fill="#2A65BD"/>',
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M621 675V219L425 555.264L621 675ZM591.944 623.103V326.606L464.503 545.249L591.944 623.103Z" fill="#897DFE"/>',
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M621 675L818 555.264L621 219V675ZM650.215 326.643V623.092L778.287 545.251L650.215 326.643Z" fill="#3083FF"/>',
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M621 880V713.938L425 594L621 880ZM591.944 786.11V730.363L526.146 690.099L591.944 786.11Z" fill="#897DFE"/>',
                '<path fill-rule="evenodd" clip-rule="evenodd" d="M621 880L818 594L621 713.938V880ZM716.357 690.083L650.193 730.366V786.141L716.357 690.083Z" fill="#3083FF"/>',
                '<text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle">',
                'PrizeBox ',
                Strings.toString(params.roundId),
                "-",
                Strings.toString(params.poolId),
                "-",
                Strings.toString(params.index),
                '</text>',
                '</svg>'
            )
        );
    }

    function generateSVGImage(NFTItemInfo memory params)
        private
        pure
        returns (string memory svg)
    {
        return Base64.encode(bytes(generateSVG(params)));
    }
}

