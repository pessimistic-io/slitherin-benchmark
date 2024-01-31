// SPDX-License-Identifier: MIT

/*********************************
*                                *
*           o(0 0)o              *
*             (^)                *
*                                *
 *********************************/

pragma solidity ^0.8.17;

import "./base64.sol";
import "./IEchoMonkeysDescriptor.sol";
import "./Strings.sol";

contract EchoMonkeysDescriptorV2 is IEchoMonkeysDescriptor {
    struct Color {
        string value;
        string name;
    }
    struct Trait {
        string content;
        string name;
        Color color;
    }
    using Strings for uint256;

    string private constant SVG_END_TAG = '</svg>';

    function tokenURI(uint256 tokenId, uint256 seed) external pure override returns (string memory) {
        uint256[4] memory colors = [seed % 100000000000000 / 1000000000000, seed % 10000000000 / 100000000, seed % 1000000 / 10000, seed % 100];
        Trait memory head = getHead(seed / 100000000000000, colors[0]);
        Trait memory face = getFace(seed % 1000000000000 / 10000000000, colors[1]);
        Trait memory nose = getNose(seed % 100000000 / 1000000, colors[2]);
        Trait memory body = getBody(seed % 10000 / 100, colors[3]);

        string memory rawSvg = string(
            abi.encodePacked(
                '<svg width="320" height="320" viewBox="0 0 320 320" xmlns="http://www.w3.org/2000/svg">',
                '<rect width="100%" height="100%" fill="#121212"/>',
                '<text x="160" y="130" font-family="Courier,monospace" font-weight="700" font-size="20" text-anchor="middle" letter-spacing="1">',
                head.content,
                face.content,
                nose.content,
                body.content,
                '</text>',
                SVG_END_TAG
            )
        );

        string memory encodedSvg = Base64.encode(bytes(rawSvg));
        string memory description = 'EchoMonkeys';

        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{',
                            '"name":"Echo Monkey #', tokenId.toString(), '",',
                            '"description":"', description, '",',
                            '"image": "', 'data:image/svg+xml;base64,', encodedSvg, '",',
                            '"attributes": [',
                            '{"trait_type": "Head", "value": "', head.name, '"},',
                            '{"trait_type": "Head color", "value": "', head.color.name, '"},',
                            '{"trait_type": "Face", "value": "', face.name, '"},',
                            '{"trait_type": "Face color", "value": "', face.color.name, '"},',
                            '{"trait_type": "Nose", "value": "', nose.name, '"},',
                            '{"trait_type": "Nose color", "value": "', nose.color.name, '"},',
                            '{"trait_type": "Body", "value": "', body.name, '"},',
                            '{"trait_type": "Body color", "value": "', body.color.name, '"}',
                            ']',
                            '}')
                    )
                )
            )
        );
    }

    function getColor(uint256 seed) private pure returns (Color memory) {
        if (seed == 10) {
            return Color("#e60049", "UA Red");
        }
        if (seed == 11) {
            return Color("#82b6b9", "Pewter Blue");
        }
        if (seed == 12) {
            return Color("#b3d4ff", "Pale Blue");
        }
        if (seed == 13) {
            return Color("#00ffff", "Aqua");
        }
        if (seed == 14) {
            return Color("#0bb4ff", "Blue Bolt");
        }
        if (seed == 15) {
            return Color("#1853ff", "Blue RYB");
        }
        if (seed == 16) {
            return Color("#35d435", "Lime Green");
        }
        if (seed == 17) {
            return Color("#61ff75", "Screamin Green");
        }
        if (seed == 18) {
            return Color("#00bfa0", "Caribbean Green");
        }
        if (seed == 19) {
            return Color("#ffa300", "Orange");
        }
        if (seed == 20) {
            return Color("#fd7f6f", "Coral Reef");
        }
        if (seed == 21) {
            return Color("#d0f400", "Volt");
        }
        if (seed == 22) {
            return Color("#9b19f5", "Purple X11");
        }
        if (seed == 23) {
            return Color("#dc0ab4", "Deep Magenta");
        }
        if (seed == 24) {
            return Color("#f46a9b", "Cyclamen");
        }
        if (seed == 25) {
            return Color("#bd7ebe", "African Violet");
        }
        if (seed == 26) {
            return Color("#fdcce5", "Classic Rose");
        }
        if (seed == 27) {
            return Color("#FCE74C", "Gargoyle Gas");
        }
        if (seed == 28) {
            return Color("#eeeeee", "Bright Gray");
        }
        if (seed == 29) {
            return Color("#7f766d", "Sonic Silver");
        }

        return Color('','');
    }

    function getHead(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
        Color memory color = getColor(colorSeed);
        string memory content;
        string memory name;

        if (seed == 10) {
            content = "---";
            name = "Bald";
        }
        if (seed == 11) {
            content = "=+===+=";
            name = "Pigtails";
        }
        if (seed == 12) {
            content = "///";
            name = "Punk";
        }
        if (seed == 13) {
            content = "***";
            name = "Fur";
        }
        if (seed == 14) {
            content = "O";
            name = "Halo";
        }
        if (seed == 15) {
            content = "~~~";
            name = "Curly Hair";
        }
        if (seed == 16) {
            content = "/~\\";
            name = "Party Hat";
        }
        if (seed == 17) {
            content = "^";
            name = "Hat";
        }
        if (seed == 18) {
            content = "|";
            name = "Mohawk Thin";
        }
        if (seed == 19) {
            content = "|||";
            name = "Spiky";
        }

        return Trait(string(abi.encodePacked('<tspan fill="', color.value, '">', content, '</tspan>')), name, color);
    }

    function getFace(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
        Color memory color = getColor(colorSeed);
        string memory content;
        string memory name;

        if (seed == 10) {
            content = "o(0 0)o";
            name = "Eyes Opened";
        }
        if (seed == 11) {
            content = "o(- -)o";
            name = "Eyes Closed";
        }
        if (seed == 12) {
            content = "o(0 -)o";
            name = "Wink";
        }
        if (seed == 13) {
            content = "o(o 0)o";
            name = "Suspicious";
        }
        if (seed == 14) {
            content = "o(o-o)o";
            name = "Glasses";
        }
        if (seed == 15) {
            content = "o(0 #)o";
            name = "Eye Patch";
        }
        if (seed == 16) {
            content = "o($-$)o";
            name = "Money";
        }

        return Trait(string(abi.encodePacked('<tspan dy="20" x="160" letter-spacing="-1" fill="', color.value, '">', content, '</tspan>')), name, color);
    }

    function getNose(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
        Color memory color = getColor(colorSeed);
        string memory content;
        string memory name;

        if (seed == 10) {
            content = "(^)";
            name = "Standard";
        }
        if (seed == 11) {
            content = "(')";
            name = "Long";
        }
        if (seed == 12) {
            content = "(-)";
            name = "Wide";
        }
        if (seed == 13) {
            content = "(.)";
            name = "Small";
        }
        if (seed == 14) {
            content = "(*)";
            name = "Clown";
        }

        return Trait(string(abi.encodePacked('<tspan dy="25" x="160" fill="', color.value, '">', content, '</tspan>')), name, color);
    }

    function getBody(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
        Color memory color = getColor(colorSeed);
        string memory content;
        string memory name;

        if (seed == 10) {
            content = "/     \\";
            name = "Standard";
        }
        if (seed == 11) {
            content = "/ =|= \\";
            name = "Muscular";
        }
        if (seed == 12) {
            content = "/  :~ \\";
            name = "Shirt";
        }
        if (seed == 13) {
            content = "/ \\:/ \\";
            name = "Suit";
        }
        if (seed == 14) {
            content = "/ \\~/ \\";
            name = "Tuxedo";
        }
        if (seed == 15) {
            content = "/ . . \\";
            name = "Nipples";
        }
        if (seed == 16) {
            content = "/  -  \\";
            name = "Tee";
        }
        if (seed == 17) {
            content = "/  v  \\";
            name = "V-Neck Tee";
        }

        return Trait(string(abi.encodePacked('<tspan dy="25" x="160" xml:space="preserve" fill="', color.value, '">', content, '</tspan>')), name, color);
    }
}

