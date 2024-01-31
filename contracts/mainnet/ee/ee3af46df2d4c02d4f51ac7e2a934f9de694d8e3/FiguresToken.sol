// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./IFiguresToken.sol";
import "./FiguresSingles.sol";
import "./FiguresDoubles.sol";
import "./FiguresRenderLib.sol";
import "./ERC721Creator.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";

import "./Counters.sol";
import "./Strings.sol";

contract FiguresToken is ERC721Creator, IFiguresToken {
    using Counters for Counters.Counter;

    address public CONTROLLER_ADDRESS;

    string private _baseSvg = "";
    uint256 private _scaleFactor = 20;
    string[3] private _backgroundColors = [
        "255,120,211",
        "255,227,0",
        "25,180,255"
    ];

    struct RandomVariables {
        uint8 number;
        uint8[4] bgColor1Index;
        uint8[4] bgColor2Index;
        uint8 figureIndex1_1;
        uint8 figureIndex1_2;
        uint8 figureIndex2_1;
        uint8 figureIndex2_2;
    }

    mapping(uint256 => uint256) private _seeds;
    mapping(uint256 => RandomVariables) private _seedRandom;

    constructor() ERC721Creator("Figures", "FIG") {}

    function setControllerAddress(
        address controllerAddress
    ) external onlyOwner {
        CONTROLLER_ADDRESS = controllerAddress;
    }

    function getControllerAddress() public view returns (address) {
        return CONTROLLER_ADDRESS;
    }

    function withdrawETH(uint256 amount) public onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    /**
     * @dev See {IFiguresToken-initializeSeed}.
     */
    function initializeSeed(uint256[] memory seed) external override {
        require(msg.sender == CONTROLLER_ADDRESS, "Permission denied");
        // generate all the random numbers you need here!
        _seedRandom[seed[0]] = RandomVariables({
            number: uint8(_random(100, seed[0])),
            bgColor1Index: [
                uint8(_random(20, seed[1])),
                uint8(_random(20, seed[2])),
                uint8(_random(20, seed[3])),
                uint8(_random(20, seed[4]))
            ],
            bgColor2Index: [
                uint8(_random(20, seed[5])),
                uint8(_random(20, seed[6])),
                uint8(_random(20, seed[7])),
                uint8(_random(20, seed[8]))
            ],
            // 360 is the max number of options for number '9'
            figureIndex1_1: uint8(_random(360, seed[9])),
            figureIndex1_2: uint8(_random(360, seed[10])),
            figureIndex2_1: uint8(_random(360, seed[11])),
            figureIndex2_2: uint8(_random(360, seed[12]))
        });
    }

    /**
     * @dev See {IFiguresToken-mint}.
     */
    function mint(
        uint256 tokenId,
        uint256 seed,
        address recipient
    ) external override {
        require(msg.sender == CONTROLLER_ADDRESS, "Permission denied");
        // Store render data for this token
        _seeds[tokenId] = seed;

        // Mint token
        _mint(recipient, tokenId);
    }

    /**
     * @dev See {IERC721-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireMinted(tokenId);
        return render(_seeds[tokenId], tokenId);
    }

    function tokenNumber(
        uint256 tokenId
    ) public view returns (uint8) {
        _requireMinted(tokenId);
        return _seedRandom[_seeds[tokenId]].number;
    }

    /**
     * @dev See {IFiguresToken-render}.
     */
    function render(
        uint256 seed,
        uint256 assetId
    ) public view override returns (string memory) {
        uint256 n;
        string memory s;
        string memory attributes;

        RandomVariables memory variables = _seedRandom[seed];

        n = variables.number;
        s = _concat(s, "data:image/svg+xml;utf8,");
        s = _concat(
            s,
            "<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' id='figures' width='"
        );
        s = _concat(s, Strings.toString(10 * _scaleFactor));
        s = _concat(s, "' height='");
        s = _concat(s, Strings.toString(10 * _scaleFactor));
        s = _concat(s, "'>");
        s = _concat(
            s,
            _drawBackground(variables.bgColor1Index, variables.bgColor2Index)
        );

        if (n < 10) {
            bool[][2] memory figArrays = FiguresSingles.chooseStringsSingles(
                uint8(n),
                variables.figureIndex1_1,
                variables.figureIndex1_2
            );
            s = _concat(
                s,
                _drawFigure(
                    false,
                    figArrays
                )
            );

        } else {
            uint8 leftNumber = uint8(n / 10);
            uint8 rightNumber = uint8(n % 10);

            bool[][2] memory figArraysLeft = FiguresDoubles.chooseStringsDoubles(
                leftNumber,
                variables.figureIndex1_1,
                variables.figureIndex1_2
            );

            bool[][2] memory figArraysRight = FiguresDoubles.chooseStringsDoubles(
                rightNumber,
                variables.figureIndex2_1,
                variables.figureIndex2_2
            );

            s = _concat(
                s,
                _drawFigure(
                    false,
                    figArraysLeft
                )
            );
            s = _concat(
                s,
                _drawFigure(
                    true,
                    figArraysRight
                )
            );
        }
        s = _concat(s, "</svg>");

        attributes = _concat('{"name":"Figure #', Strings.toString(assetId));

        attributes = _concat(attributes, '", "description":"Figure representation of ');

        attributes = _concat(attributes, Strings.toString(n));

        attributes = _concat(attributes, '.", "created_by":"Figures", "external_url":"https://figures.art/token/');

        attributes = _concat(attributes, Strings.toString(assetId));

        attributes = _concat(attributes, '", "attributes": [{"trait_type": "Number", "value":"');

        attributes = _concat(attributes, Strings.toString(n));

        attributes = _concat(attributes, '"}], "image":"');

        return
            string(
                abi.encodePacked(
                    'data:application/json;utf8,',
                    attributes,
                    s,
                    '"}'
                )
            );
    }

    function _random(
        uint256 number,
        uint256 count
    ) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.difficulty,
                        msg.sender,
                        count
                    )
                )
            ) % number;
    }

    function _concat(string memory a, string memory b)
        private
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }

    function _drawBackground(
        uint8[4] memory bgColor1Index,
        uint8[4] memory bgColor2Index
    ) internal view returns (string memory) {
        // Draw first layer of bg by laying 4 randomly colored tiled
        string memory s = "";

        for (uint256 i = 0; i < 4; i++) {
            uint bgColor1IndexAvailable = bgColor1Index[i] % 3;
            uint bgColor2IndexAvailable = bgColor2Index[i] % 4;
            s = _concat(s, "<g>");
            s = _concat(
                s,
                (
                    FiguresRenderLib._generateRect(
                        (i % 2) * uint256(5) * _scaleFactor,
                        (i / 2) * uint256(5) * _scaleFactor,
                        uint256(5) * _scaleFactor,
                        uint256(5) * _scaleFactor,
                        _backgroundColors[bgColor1IndexAvailable],
                        ""
                    )
                )
            );
            if (bgColor2IndexAvailable == 3) {
                s = _concat(s, "</g>");
                continue;
            }

            s = _concat(
                s,
                (
                    FiguresRenderLib._generateRect(
                        (i % 2) * uint256(5) * _scaleFactor,
                        (i / 2) * uint256(5) * _scaleFactor,
                        uint256(5) * _scaleFactor,
                        uint256(5) * _scaleFactor,
                        _backgroundColors[bgColor2IndexAvailable],
                        "mix-blend-mode: multiply;"
                    )
                )
            );
            s = _concat(s, "</g>");
        }
        return s;
    }

    function _drawFigure(
        bool rightOffset,
        bool[][2] memory figArrays
    ) internal view returns (string memory) {
        uint256 rightOffsetX = 0;

        if (rightOffset) {
            rightOffsetX = uint256(5) * _scaleFactor;
        }

        string memory s = "";

        // k is top and bottom
        for (uint256 k = 0; k < 2; k++) {
            // i is each pixel
            for (uint256 i = 0; i < figArrays[k].length; ++i) {
                uint8 size = uint8(figArrays[k].length / 5);
                if (figArrays[k][i]) {
                    continue;
                }
                uint256 xOffset = _scaleFactor;
                uint256 yOffset = _scaleFactor;
                uint256 x = (i % size) * xOffset + rightOffsetX;
                uint256 y = 0;

                if (k == 1) {
                    y = (5 * yOffset);
                }
                y += (i / size) * yOffset;

                s = _concat(s, FiguresRenderLib._generatePixelSVG(x, y, _scaleFactor, "255,120,211"));
            }
        }

        return s;
    }
}

