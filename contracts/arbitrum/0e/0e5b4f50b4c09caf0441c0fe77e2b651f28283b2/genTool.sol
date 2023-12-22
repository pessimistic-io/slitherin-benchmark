// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Strings.sol";
import "./Base64.sol";

contract GenTool {


    function generateMetadata(uint256 tokenId, string memory svg) external pure returns (string memory) {
        bytes memory svgBytes = bytes(svg);
        string memory base64Svg = Base64.encode(svgBytes);
        string memory tokenIdString = Strings.toString(tokenId);

        string memory json = string(abi.encodePacked(
            "{\"name\":\"Domeland\",",
            "\"image\":\"data:image/svg+xml;base64,", base64Svg, "\",",
            "\"attributes\":[",
                "{\"trait_type\":\"DC#\",\"value\":\"", tokenIdString, "\"},",
                "{\"trait_type\":\"UNIT#\",\"value\":\"0\"},",
                "{\"trait_type\":\"JUMP-PATH\",\"value\":\"Observable Universe ... Pisces, Cetus Supercluster Complex ... Laniakea Supercluster ... Virgo Supercluster ... Local Group of Galaxies ... Milky Way ... Solar System ... Earth\"},",
                "{\"trait_type\":\"VOL\",\"value\":\"9X9X9\"},",
                "{\"trait_type\":\"SRC\",\"value\":\"https://ipfs.io/ipfs/bafybeiaehykyal3qcwh6skhrpvdulwe4j6zhdzwiuxl3zwv5vgejkgaany/", tokenIdString, ".json\"}",
            "]}"
        ));

        return json;
    }


    function generateMetadata(uint256 tokenId, string memory svg, string memory animationUrl, string memory animationExt) external pure returns (string memory) {
        bytes memory svgBytes = bytes(svg);
        string memory base64Svg = Base64.encode(svgBytes);
        string memory tokenIdString = Strings.toString(tokenId);

        string memory fullAnimationUrl;
        if (bytes(animationExt).length > 0) {
            // 拼接 animationUrl, tokenIdString 和 animationExt
             fullAnimationUrl = string(abi.encodePacked(animationUrl, "/", tokenIdString, ".", animationExt));
        } else {
            fullAnimationUrl = string(animationUrl);
        }


        string memory json = string(abi.encodePacked(
            "{\"name\":\"Domeland\",",
            "\"image\":\"data:image/svg+xml;base64,", base64Svg, "\",",
            "\"animation_url\":\"", fullAnimationUrl, "\",", // 使用 fullAnimationUrl
            "\"attributes\":[",
                "{\"trait_type\":\"DC#\",\"value\":\"", tokenIdString, "\"},",
                "{\"trait_type\":\"UNIT#\",\"value\":\"0\"},",
                "{\"trait_type\":\"JUMP-PATH\",\"value\":\"Observable Universe ... Pisces, Cetus Supercluster Complex ... Laniakea Supercluster ... Virgo Supercluster ... Local Group of Galaxies ... Milky Way ... Solar System ... Earth\"},",
                "{\"trait_type\":\"VOL\",\"value\":\"9X9X9\"},",
                "{\"trait_type\":\"SRC\",\"value\":\"https://ipfs.io/ipfs/bafybeiaehykyal3qcwh6skhrpvdulwe4j6zhdzwiuxl3zwv5vgejkgaany/",  tokenIdString, ".json\"},",
                "{\"trait_type\":\"Animation\",\"value\":\"", fullAnimationUrl, "\"}",
            "]}"
        ));

        return json;
    }


    function generateSVG(uint256 tokenId) external pure returns (string memory) {

            uint256 hue1 = (tokenId * 997) % 310; // 生成一个基于tokenId的0到309之间的整数
            uint256 hue2 = (hue1 + 45) % 310; // 计算渐变的第二个颜色值，偏移45度
            uint256 saturation = 80; // 饱和度
            uint256 lightness1 = 60; // 第一个颜色的亮度
            uint256 lightness2 = 90; // 第二个颜色的亮度


            string memory svgTemplate = string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 480">',
                '<style>',
                    '.tokens { font: bold 24px sans-serif; }',
                    '.fee { font: normal 12px sans-serif; }',
                    '.tick { font: normal 8px sans-serif; }',
                '</style>',
                '<defs>',
                '<linearGradient id="grad" x1="0" y1="0" x2="1" y2="1">',
                '<stop offset="0%" stop-color="hsl(', Strings.toString(hue1), ', ', Strings.toString(saturation), '%, ', Strings.toString(lightness1), '%)"/>',
                '<stop offset="100%" stop-color="hsl(', Strings.toString(hue2), ', ', Strings.toString(saturation), '%, ', Strings.toString(lightness2), '%)"/>',
                '</linearGradient>',
                '</defs>',
                '<rect width="300" height="480" fill="url(#grad)" />',
                // 其他图形元素
                //  '<rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(0,0%,0%)" stroke="#000" />',
                '<rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(0,0%,0%)" stroke="#000" id="map" />',
                '<text x="39" y="90" class="tokens" fill="#fff" id="name"> DOMELAND </text>',
                '<text x="39" y="110" dy="15" class="tokens" fill="#fff" id="DC#">DC #', Strings.toString(tokenId), '</text>',
                '<text x="39" y="130" dy="15" class="fee" fill="#fff" id="UNIT#">UNIT #0 </text>',
                '<text x="39" y="185" class="tick" fill="#fff" id="JUMP-PATH">',
                '<tspan x="39" dy="1.2em">Curve-Path : Observable Universe -  </tspan>',
                '<tspan x="39" dy="1.2em">Pisces, Cetus Supercluster Complex - </tspan>',
                '<tspan x="39" dy="1.2em">Laniakea Supercluster - Virgo Supercluster - </tspan>',
                '<tspan x="39" dy="1.2em">Local Group of Galaxies - Milky Way - </tspan>',
                '<tspan x="39" dy="1.2em">Solar System  - Earth </tspan>',
                '</text>',
                '<text x="39" y="250" dy="30" class="tick" fill="#fff" id="VOL">Volume : 9*9*9</text>',
                '<text x="39" y="280" dy="30" class="tick" fill="#fff" id="USAGE">Usage : copilot capsule</text>',
                '<text x="240" y="60" dy="1.2em" class="tick" fill="#fff" id="SRC" writing-mode="tb-rl" glyph-orientation-vertical="0">',
            'SRC : https://ipfs.io/ipfs/bafybeiaehykyal3qcwh6skhrpvdulwe4j6zhdzwiuxl3zwv5vgejkgaany/', Strings.toString(tokenId), ".json", '</text>',
                // Add logoSVG
                '<g transform="translate(39,435) scale(0.06,-0.06)" fill="rgba(255, 255, 255, 0.5)" stroke="none" id="top" ><path d="M490 1245 c-171 -47 -332 -178 -404 -327 -88 -183 -87 -372 3 -553 37 -74 121 -185 141 -185 5 0 10 15 12 33 3 29 9 34 58 53 79 31 100 37 100 26 0 -5 -23 -19 -52 -31 l-52 -22 29 -17 c17 -10 93 -51 170 -92 l140 -73 90 47 c49 25 126 66 169 90 l80 44 -52 22 c-29 12 -52 26 -52 31 0 8 75 -12 130 -35 l33 -13 -194 -104 c-206 -111 -219 -127 -73 -94 112 25 224 85 304 164 321 318 197 867 -230 1018 -94 33 -263 42 -350 18z m-6 -142 c14 -56 23 -109 19 -119 -4 -12 -3 -15 5 -10 8 5 10 -3 7 -26 -4 -24 -3 -27 3 -14 8 19 9 19 14 -2 5 -16 0 -23 -21 -31 -21 -8 -22 -10 -6 -10 11 0 38 5 59 13 40 14 46 22 71 106 6 22 5 23 -6 9 -20 -24 -95 -34 -103 -14 -4 12 7 21 41 36 25 11 55 21 66 23 16 2 26 18 40 60 11 32 23 54 27 49 8 -9 45 -181 55 -253 3 -25 8 -54 11 -66 4 -14 -1 -24 -18 -32 -49 -23 5 -11 79 19 93 37 118 56 101 76 -8 10 -30 13 -77 11 l-65 -3 -18 48 c-10 26 -16 47 -15 47 2 0 63 -24 137 -54 l134 -54 -64 -29 c-36 -17 -121 -56 -189 -88 -69 -32 -130 -58 -135 -58 -8 0 -10 -86 -8 -274 l3 -273 -188 96 c-103 53 -194 101 -201 107 -9 7 -13 31 -12 71 4 107 0 163 -10 141 -5 -12 -9 -14 -9 -6 -1 8 -13 30 -28 49 -15 20 -23 37 -17 39 35 12 37 20 20 68 -8 26 -24 54 -33 61 -16 12 -11 13 35 14 l54 0 -4 36 c-3 42 9 54 82 80 46 17 47 18 70 88 31 96 61 178 65 174 2 -2 15 -49 29 -105z m528 -441 c32 -11 72 -31 90 -44 30 -21 31 -23 12 -26 -12 -2 -50 -28 -85 -59 -70 -61 -129 -92 -173 -93 -27 0 -28 1 -14 22 8 12 27 25 43 30 15 4 41 20 58 35 17 15 27 23 24 16 -5 -8 -1 -8 17 0 15 7 20 14 13 19 -6 3 5 8 24 11 19 2 6 4 -31 5 -54 1 -74 -4 -120 -28 -78 -42 -90 -40 -90 14 0 53 14 96 38 114 23 18 120 10 194 -16z m-87 -132 c-10 -11 -23 -20 -29 -20 -6 0 0 9 14 20 32 25 38 25 15 0z"/><path d="M320 870 c19 -11 40 -19 45 -19 6 0 -6 8 -25 19 -19 11 -39 19 -45 19 -5 0 6 -8 25 -19z"/><path d="M450 810 c19 -11 40 -19 45 -19 6 0 -6 8 -25 19 -19 11 -39 19 -45 19 -5 0 6 -8 25 -19z"/><path d="M290 759 c-12 -8 -10 -9 8 -4 71 20 91 -123 24 -176 -21 -16 -23 -20 -8 -18 58 11 82 135 35 185 -25 26 -36 29 -59 13z"/><path d="M570 755 c14 -8 30 -14 35 -14 6 0 -1 6 -15 14 -14 8 -29 14 -35 14 -5 0 1 -6 15 -14z"/><path d="M525 660 c-17 -7 -14 -9 12 -9 68 -2 85 -121 27 -183 -25 -26 -26 -29 -7 -19 66 34 71 167 8 206 -12 8 -28 10 -40 5z"/></g>',
            '</svg>'
            ));

            return svgTemplate;
        }

}
