// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

import "./Strings.sol";
import "./BitMath.sol";
import "./base64.sol";

/// @title NFTSVG
/// @notice Provides a function for generating an SVG associated with a 1EX NFT
library NFTSVG1EX {
    using Strings for uint256;

    struct SVGParams {
        string quoteToken;
        string baseToken;
        address poolAddress;
        string quoteTokenSymbol;
        string baseTokenSymbol;
        string feeTier;
        int24 tickLower;
        int24 tickUpper;
        uint256 tokenId;
        string color0;
        string color1;
        string color2;
        string color3;
        string x1;
        string y1;
        string x2;
        string y2;
        string x3;
        string y3;
    }

    function generateSVG(
        SVGParams memory params
    ) internal pure returns (string memory svg) {
        return
            string(
                abi.encodePacked(
                    generateSVGDefs(params),
                    generateSVGBorderText(
                        params.quoteToken,
                        params.baseToken,
                        params.quoteTokenSymbol,
                        params.baseTokenSymbol
                    ),
                    generateSVGCardMantle(
                        params.quoteTokenSymbol,
                        params.baseTokenSymbol,
                        params.feeTier
                    ),
                    getSVGLogo(),
                    generateSVGPositionDataAndLocationCurve(
                        params.tokenId.toString(),
                        params.tickLower,
                        params.tickUpper
                    ),
                    generateSVGRareSparkle(params.tokenId, params.poolAddress),
                    "</svg>"
                )
            );
    }

    function generateSVGDefs(
        SVGParams memory params
    ) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
                " xmlns:xlink='http://www.w3.org/1999/xlink'>",
                "<defs>",
                '<filter id="f1"><feImage result="p0" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><rect width='290px' height='500px' fill='#",
                            params.color0,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feImage result="p1" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x1,
                            "' cy='",
                            params.y1,
                            "' r='120px' fill='#",
                            params.color1,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feImage result="p2" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x2,
                            "' cy='",
                            params.y2,
                            "' r='120px' fill='#",
                            params.color2,
                            "'/></svg>"
                        )
                    )
                ),
                '" />',
                '<feImage result="p3" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x3,
                            "' cy='",
                            params.y3,
                            "' r='100px' fill='#",
                            params.color3,
                            "'/></svg>"
                        )
                    )
                ),
                '" /><feBlend mode="overlay" in="p0" in2="p1" /><feBlend mode="exclusion" in2="p2" /><feBlend mode="overlay" in2="p3" result="blendOut" /><feGaussianBlur ',
                'in="blendOut" stdDeviation="42" /></filter> <clipPath id="corners"><rect width="290" height="500" rx="42" ry="42" /></clipPath>',
                '<path id="text-path-a" d="M40 12 H250 A28 28 0 0 1 278 40 V460 A28 28 0 0 1 250 488 H40 A28 28 0 0 1 12 460 V40 A28 28 0 0 1 40 12 z" />',
                '<path id="minimap" d="M234 444C234 457.949 242.21 463 253 463" />',
                '<filter id="top-region-blur"><feGaussianBlur in="SourceGraphic" stdDeviation="24" /></filter>',
                '<linearGradient id="grad-up" x1="1" x2="0" y1="1" y2="0"><stop offset="0.0" stop-color="white" stop-opacity="1" />',
                '<stop offset=".9" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<linearGradient id="grad-down" x1="0" x2="1" y1="0" y2="1"><stop offset="0.0" stop-color="white" stop-opacity="1" /><stop offset="0.9" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<mask id="fade-up" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#grad-up)" /></mask>',
                '<mask id="fade-down" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#grad-down)" /></mask>',
                '<mask id="none" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="white" /></mask>',
                '<linearGradient id="grad-symbol"><stop offset="0.7" stop-color="white" stop-opacity="1" /><stop offset=".95" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<mask id="fade-symbol" maskContentUnits="userSpaceOnUse"><rect width="290px" height="200px" fill="url(#grad-symbol)" /></mask>',
                '<linearGradient id="logo_g1" x1="78" x2="45.5" y1="32" y2="3" gradientUnits="userSpaceOnUse"><stop stop-color="#B8B8B8"/><stop offset=".477" stop-color="#EBEBEB"/><stop offset="1" stop-color="#29A3A3"/></linearGradient>',
                '<linearGradient id="logo_g2" x1="20.433" x2="20.433" y1="32" y2=".333" gradientUnits="userSpaceOnUse"><stop offset=".154" stop-color="#29A3A3"/><stop offset=".741" stop-color="#24E0E0"/></linearGradient>',
                '<linearGradient id="logo_g3" x1="0" x2="22" y1="5" y2="5" gradientUnits="userSpaceOnUse"><stop stop-color="#22D3D3"/><stop offset="1" stop-color="#29A3A3"/></linearGradient>',
                '<linearGradient id="logo_g4" x1="72.201" x2="65.5" y1="9.209" y2="2.509" gradientUnits="userSpaceOnUse"><stop stop-color="#EBEBEB"/><stop offset="1" stop-color="#B8B8B8"/></linearGradient>',
                '<linearGradient id="logo_g5" x1="50.049" x2="37" y1="29.5" y2="16.451" gradientUnits="userSpaceOnUse"><stop stop-color="#EBEBEB"/><stop offset="1" stop-color="#B8B8B8"/></linearGradient></defs>',
                '<g clip-path="url(#corners)">',
                '<rect fill="',
                params.color0,
                '" x="0px" y="0px" width="290px" height="500px" />',
                '<rect style="filter: url(#f1)" x="0px" y="0px" width="290px" height="500px" />',
                ' <g style="filter:url(#top-region-blur); transform:scale(1.5); transform-origin:center top;">',
                '<rect fill="none" x="0px" y="0px" width="290px" height="500px" />',
                '<ellipse cx="50%" cy="0px" rx="180px" ry="120px" fill="#000" opacity="0.85" /></g>',
                '<rect x="0" y="0" width="290" height="500" rx="42" ry="42" fill="rgba(0,0,0,0)" stroke="rgba(255,255,255,0.2)" /></g>'
            )
        );
    }

    function generateSVGBorderText(
        string memory quoteToken,
        string memory baseToken,
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol
    ) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<text text-rendering="optimizeSpeed">',
                '<textPath startOffset="-100%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                unicode" • ",
                baseTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" />',
                '</textPath> <textPath startOffset="0%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                unicode" • ",
                baseTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /> </textPath>',
                '<textPath startOffset="50%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                unicode" • ",
                quoteTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s"',
                ' repeatCount="indefinite" /></textPath><textPath startOffset="-50%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                unicode" • ",
                quoteTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>'
            )
        );
    }

    function generateSVGCardMantle(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        string memory feeTier
    ) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<g mask="url(#fade-symbol)"><rect fill="none" x="0px" y="0px" width="290px" height="200px" /> <text y="70px" x="32px" fill="white" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">',
                quoteTokenSymbol,
                "/",
                baseTokenSymbol,
                '</text><text y="115px" x="32px" fill="white" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">',
                feeTier,
                "</text></g>",
                '<rect x="16" y="16" width="258" height="468" rx="26" ry="26" fill="rgba(0,0,0,0)" stroke="rgba(255,255,255,0.2)" />'
            )
        );
    }

    function getSVGLogo() private pure returns (string memory logo) {
        return
            '<g id="1EX_logo" style="transform: translate(56px, 214px) scale(2.2); filter: drop-shadow(0px 0px 4px #303030);"><path style="fill:url(#logo_g1)" d="m43.744 7.756 3.7-7.72 32.758 31.855h-11.61"/><path style="fill:#B8B8B8" d="m47.461.036-3.731 7.77L32.242 7.8 24.522.043"/><path style="fill:url(#logo_g2)" d="M13.332.004 22.041 0v32h-8.714"/><path style="fill:url(#logo_g3)" d="M0 9.708 9.705 0l12.33.004L6.15 15.866"/><path style="fill:url(#logo_g4)" d="M58.996 9.22 68.433.036l11.856.025-15.255 15.241"/><path style="fill:url(#logo_g5)" d="m50.947 16.781 6.121 6.107-9.422 9.025-23.756.026-.03-20.527 18.217.007 4.517 4.625-4.55 4.635-8.684-.007.007 3.561h10.439"/></g>';
    }

    function generateSVGPositionDataAndLocationCurve(
        string memory tokenId,
        int24 tickLower,
        int24 tickUpper
    ) private pure returns (string memory svg) {
        string memory tickLowerStr = tickToString(tickLower);
        string memory tickUpperStr = tickToString(tickUpper);
        uint256 str1length = bytes(tokenId).length + 4;
        uint256 str2length = bytes(tickLowerStr).length + 10;
        uint256 str3length = bytes(tickUpperStr).length + 10;
        (string memory xCoord, string memory yCoord) = rangeLocation(
            tickLower,
            tickUpper
        );
        svg = string(
            abi.encodePacked(
                ' <g style="transform:translate(29px, 384px)">',
                '<rect width="',
                uint256(7 * (str1length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(255,255,255,0.6)">ID: </tspan>',
                tokenId,
                "</text></g>",
                ' <g style="transform:translate(29px, 414px)">',
                '<rect width="',
                uint256(7 * (str2length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(255,255,255,0.6)">Min Tick: </tspan>',
                tickLowerStr,
                "</text></g>",
                ' <g style="transform:translate(29px, 444px)">',
                '<rect width="',
                uint256(7 * (str3length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(255,255,255,0.6)">Max Tick: </tspan>',
                tickUpperStr,
                "</text></g>"
                '<g style="transform:translate(226px, 433px)">',
                '<rect width="36px" height="36px" rx="8px" ry="8px" fill="none" stroke="rgba(255,255,255,0.2)" />',
                '<path stroke-linecap="round" d="M8 9C8.00004 22.9494 16.2099 28 27 28" fill="none" stroke="white" />',
                '<circle style="transform:translate3d(',
                xCoord,
                "px, ",
                yCoord,
                'px, 0px)" cx="0px" cy="0px" r="4px" fill="white"/></g>'
            )
        );
    }

    function tickToString(int24 tick) private pure returns (string memory) {
        string memory sign = "";
        if (tick < 0) {
            tick = tick * -1;
            sign = "-";
        }
        return string(abi.encodePacked(sign, uint256(tick).toString()));
    }

    function rangeLocation(
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (string memory, string memory) {
        int24 midPoint = (tickLower + tickUpper) / 2;
        if (midPoint < -125_000) {
            return ("8", "7");
        } else if (midPoint < -75_000) {
            return ("8", "10.5");
        } else if (midPoint < -25_000) {
            return ("8", "14.25");
        } else if (midPoint < -5_000) {
            return ("10", "18");
        } else if (midPoint < 0) {
            return ("11", "21");
        } else if (midPoint < 5_000) {
            return ("13", "23");
        } else if (midPoint < 25_000) {
            return ("15", "25");
        } else if (midPoint < 75_000) {
            return ("18", "26");
        } else if (midPoint < 125_000) {
            return ("21", "27");
        } else {
            return ("24", "27");
        }
    }

    function generateSVGRareSparkle(
        uint256 tokenId,
        address poolAddress
    ) private pure returns (string memory svg) {
        if (isRare(tokenId, poolAddress)) {
            svg = string(
                abi.encodePacked(
                    '<g style="transform:translate(226px, 392px)"><rect width="36px" height="36px" rx="8px" ry="8px" fill="none" stroke="rgba(255,255,255,0.2)" />',
                    '<g><path style="transform:translate(6px,6px)" d="M12 0L12.6522 9.56587L18 1.6077L13.7819 10.2181L22.3923 6L14.4341 ',
                    "11.3478L24 12L14.4341 12.6522L22.3923 18L13.7819 13.7819L18 22.3923L12.6522 14.4341L12 24L11.3478 14.4341L6 22.39",
                    '23L10.2181 13.7819L1.6077 18L9.56587 12.6522L0 12L9.56587 11.3478L1.6077 6L10.2181 10.2181L6 1.6077L11.3478 9.56587L12 0Z" fill="white" />',
                    '<animateTransform attributeName="transform" type="rotate" from="0 18 18" to="360 18 18" dur="10s" repeatCount="indefinite"/></g></g>'
                )
            );
        } else {
            svg = "";
        }
    }

    function isRare(uint256 tokenId, address poolAddress) internal pure returns (bool) {
        bytes32 h = keccak256(abi.encodePacked(tokenId, poolAddress));
        return
            uint256(h) <
            type(uint256).max / (1 + BitMath.mostSignificantBit(tokenId) * 2);
    }
}

