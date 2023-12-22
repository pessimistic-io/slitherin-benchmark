//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./ERC721Enumerable.sol";
import "./Strings.sol";
import "./AggregatorV3Interface.sol";
import "./base64.sol";

contract SpeedBuilds is ERC721Enumerable {
    using Strings for uint256;
    using Strings for uint160;
    using Strings for uint16;

    struct HouseProperties {
        string wallColor;
        string windowColor;
        string doorColor;
        string roofColor;
    }

    /* ========== STATE VARIABLES ========== */

    /* == constants and immutables == */
    uint16 private constant MAX_SUPPLY = 1000;
    uint16 private _tokenIds;


    address payable constant buildGuild =
        payable(0x031B6ae3597db9E046E2d44685563EdB2a4b60C2);
    address immutable i_owner;


    uint256 public constant mintFee = 0.001 ether;
    AggregatorV3Interface public immutable i_priceFeed;
    uint256 public lastPrice = 0;
    uint256 tokenCounter;


    mapping(uint16 => string[6]) public tokenIdToColor;
    mapping(uint16 => uint256) public tokenIdToRandomNumber;
    mapping(uint16 => bool) public isDay;

    modifier onlyOwner() {
        require(msg.sender == i_owner, "Sender is not owner");
        _;
    }

    /* ========== Functions ========== */
    constructor(address _priceFeed) ERC721("Speed Builds", "SBD") {
        i_priceFeed = AggregatorV3Interface(_priceFeed);
        i_owner = msg.sender;
    }

    receive() external payable {
        mintItem();
    }

    // fallback
    fallback() external payable {
        mintItem();
    }

    function mintItem() public payable returns (uint256) {
        require(_tokenIds < MAX_SUPPLY, "Minting Ended");
        require(msg.value >= mintFee, "Price is 0.001 ETH");

        uint16 id = _tokenIds;

        _tokenIds = _tokenIds + 1;
        tokenCounter = tokenCounter + 1;

        _mint(msg.sender, id);

        (
            ,
            /*uint80 roundID*/
            int256 price,
            ,
            ,
            /* uint startedAt */
            /*uint timeStamp*/
            uint80 answeredInRound
        ) = i_priceFeed.latestRoundData();

        if (uint256(price) >= lastPrice) {
            isDay[id] = true;
            lastPrice = uint256(price);
        } else {
            // by defalut its false
            // isDay[id] = false;
            lastPrice = uint256(price);
        }

        isDay[0] = false;

        string[6] memory COLORS = [
            "sandybrown",
            "orchid",
            "chocolate",
            "lightgray",
            "lightsteelblue",
            "dimgrey"
        ];

        uint256 pseudoRandomNumber = uint256(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    address(this),
                    block.chainid,
                    id,
                    block.timestamp,
                    block.difficulty,
                    price
                )
            )
        );

        // reorder the colors after every mint
        for (uint256 i = 0; i < 6; i++) {
            uint256 randomIndex = i +
                ((pseudoRandomNumber + answeredInRound) % (6 - i));
            string memory color = COLORS[randomIndex];
            COLORS[randomIndex] = COLORS[i];
            COLORS[i] = color;
        }

        tokenIdToColor[id] = COLORS;
        tokenIdToRandomNumber[id] = pseudoRandomNumber;
        (bool success, ) = buildGuild.call{value: msg.value}("");
        require(success, "Failed sending funds to BuildGuild");

        return id;
    }

    function withdraw() public payable onlyOwner {
        (bool callSuccess, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(callSuccess, "Call failed");
    }

    function getPropertiesById(uint16 id)
        public
        view
        returns (HouseProperties memory properties)
    {
        // 6 is length of COLORS array
        uint256 pseudoRandomNumber = tokenIdToRandomNumber[id];
        uint8 wallIndex = uint8(pseudoRandomNumber % 6);
        properties.wallColor = tokenIdToColor[id][wallIndex];

        uint8 roofIndex = uint8((pseudoRandomNumber + 1) % 6);
        properties.roofColor = tokenIdToColor[id][roofIndex];

        properties.windowColor = tokenIdToColor[id][4];

        uint8 doorIndex = uint8((pseudoRandomNumber + 4) % 6);

        if (doorIndex != 4) {
            properties.doorColor = tokenIdToColor[id][doorIndex];
        } else {
            doorIndex = uint8((pseudoRandomNumber + 5) % 7);
            properties.doorColor = tokenIdToColor[id][doorIndex];
        }

        return properties;
    }

    function renderedTokenById(uint16 id) public view returns (string memory) {
        HouseProperties memory properties = getPropertiesById(id);
        bool day = isDay[id];

        string memory render;

        if (day) {
            render = string.concat(
                " <linearGradient id="
                '"id0"'
                " gradientUnits="
                '"userSpaceOnUse"'
                " x1="
                '"127.5"'
                " y1="
                '"106.15"'
                " x2="
                '"127.5"'
                " y2="
                '"183.851"'
                ">",
                " <stop offset="
                '"0"'
                " style="
                '"stop-opacity:1; stop-color:#00B5DC"'
                "/>",
                " <stop offset="
                '"1"'
                " style="
                '"stop-opacity:1; stop-color:#FEFEFE"'
                "/>",
                "  </linearGradient>",
                //Background
                " <polygon fill="
                '"url(#id0)"'
                " points="
                '"253,15 253,275 2,275 2,15"'
                "/>",
                // Walls
                "  <path fill='",
                properties.wallColor,
                "' d="
                '"M16 233l13 0 0 -61 52 0 0 61 7 0 0 -74 79 0 0 74 7 0 0 -61 52 0 0 61 13 0 0 42 -92 0 0 -15c0,-4 -9,-12 -19,-12l0 0c-11,0 -20,7 -20,12l0 15 -92 0 0 -42zm176 -7l0 -15c0,-4 4,-7 8,-7l0 0c4,0 8,3 8,7l0 15 -16 0zm-54 -20l0 -14c0,-3 3,-6 7,-6l0 0c4,0 8,3 8,6l0 14 -15 0zm-36 0l0 -14c0,-3 4,-6 8,-6l0 0c4,0 7,3 7,6l0 14 -15 0zm-55 20l0 -15c0,-4 4,-7 8,-7l0 0c4,0 8,3 8,7l0 15 -16 0z"'
                "/>",
                //Door
                " <path fill='",
                properties.doorColor,
                "' d="
                '"M110 275l0 -14c0,-4 8,-11 18,-11l0 0c9,0 18,7 18,11l0 14 -36 0z"'
                "/>",
                //Window
                " <path fill='",
                properties.windowColor,
                "' d="
                '"M193 225l0 -14c0,-3 3,-6 7,-6l0 0c4,0 7,3 7,6l0 14 -14 0zm-145 0l0 -14c0,-3 3,-6 7,-6l0 0c4,0 7,3 7,6l0 14 -14 0zm55 -21l0 -11c0,-2 3,-5 6,-5l0 0c4,0 7,3 7,5l0 11 -13 0zm36 0l0 -11c0,-2 3,-5 7,-5l0 0c3,0 6,3 6,5l0 11 -13 0z"'
                "/>",
                //Roof
                "<path fill='",
                properties.roofColor,
                "' d="
                '"M231 170l-62 0 31 -43 31 43zm-145 0l-62 0 31 -43 31 43zm87 -12l-91 0 46 -51 45 51z"'
                "/>",
                //Sun
                " <path fill="
                '"#DCDC00"'
                " d="
                '"M206 40c-4,0 -8,2 -11,5 -3,3 -4,8 -4,12 1,8 8,15 18,14 8,0 15,-8 14,-17 -1,-8 -8,-15 -17,-14zm10 -3c1,0 0,0 1,0 1,-1 1,-6 1,-7 0,0 0,0 0,0l-1 1c0,0 0,0 -1,1l-2 3c0,0 0,0 0,1 0,0 0,0 0,0 0,0 -1,0 -1,1 0,2 3,3 3,0zm5 34c0,0 0,0 0,0 0,0 0,0 0,0 0,1 4,4 5,4l0 0 1 0c0,-1 -2,-3 -2,-3l-2 -3c0,0 0,0 0,0 -1,-2 -5,0 -2,2zm-29 -2c-1,0 -1,1 -2,1 0,1 -2,4 -2,5l0 0 0 0c1,0 5,-3 6,-4 0,0 0,0 -1,0 0,0 0,0 0,0 1,0 2,-1 1,-2 -1,-1 -2,-1 -2,0zm-4 -32c0,1 2,3 3,4 0,1 0,1 0,1 1,0 0,0 1,0 0,0 1,1 2,1 1,-1 1,-2 -1,-3 1,0 1,0 0,-1 -1,-1 -4,-3 -5,-3 0,0 0,0 0,0 0,1 0,0 0,0 -1,1 0,0 0,1zm38 9c0,1 0,1 0,1 -3,0 -2,2 0,2 0,0 1,0 1,0 2,0 5,-3 5,-3l0 -1c-1,0 -6,0 -6,1zm-5 -6c-1,1 -2,2 -1,3 1,0 2,0 2,0 0,-1 0,-1 1,-1 0,-1 -1,0 0,0 0,0 0,0 1,-1 1,-1 3,-3 3,-5 -1,0 -1,0 -1,1 0,-1 0,-1 0,-1 -1,0 -3,2 -4,3 -1,0 -1,0 -1,0 0,1 0,1 0,1zm-35 17c0,0 0,0 0,0 0,0 0,0 0,0 4,1 4,-3 0,-3l0 0c0,0 0,0 0,0 0,0 0,0 0,0 -1,0 -5,1 -6,1 0,0 0,0 0,0l0 1c0,0 0,0 1,0 1,1 4,1 5,1zm12 -20l0 0c0,0 0,0 0,0 0,3 3,2 3,0 0,-1 0,-1 0,-1 0,-1 -4,-6 -4,-6 0,0 0,0 0,0 0,0 0,0 0,0 -1,0 -1,1 -1,2 0,1 1,4 2,5zm30 17c-3,0 -4,4 0,3 0,0 0,0 0,0 0,0 0,0 0,0 1,0 5,0 6,-1 0,0 1,0 1,-1 0,0 0,0 -1,0 -1,0 -5,-1 -6,-1 0,0 0,0 0,0zm-46 -9c0,0 0,0 0,1 0,0 0,0 0,0 1,0 4,3 5,3 0,0 1,0 2,0 1,0 3,-2 -1,-2 0,0 0,0 1,-1 -1,-1 -6,-2 -7,-1zm35 29c-1,0 -1,0 -1,1 0,-1 0,-3 -1,-3 -1,0 -2,1 -2,2 1,2 3,5 4,6 0,1 0,1 1,1 0,0 0,-1 0,-2 0,-2 -1,-3 -1,-5zm-19 1c0,-1 0,-1 0,-1 -1,1 -2,4 -2,5 0,1 0,2 1,2 0,0 0,0 0,0 0,0 4,-5 4,-5l0 -2c0,-1 -1,-2 -1,-2 -2,0 -2,2 -2,3zm8 2c0,0 0,0 0,-1 -1,2 0,6 1,7 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0 0,0l0 0c1,-1 2,-5 2,-7 -1,1 0,1 -1,1 1,-2 1,-3 -1,-3 -1,0 -1,1 -1,3zm20 -12c0,0 0,0 0,0 0,1 5,2 6,1 0,0 1,0 0,0 0,0 1,0 1,0 -1,-1 -5,-3 -6,-4 -2,-1 -4,1 -3,2 1,1 2,0 2,1zm-44 1c0,0 0,0 0,0l0 0c0,0 0,0 0,0 1,1 6,0 7,-1 -1,0 -1,0 -1,-1 1,0 1,1 2,0 1,-1 0,-2 -1,-2 -2,0 -3,1 -5,2 0,0 -1,1 -2,2zm25 -38c-1,1 -2,5 -1,7 0,0 0,0 0,-1 0,2 0,3 1,3 2,0 2,-1 1,-2 1,-1 0,0 1,0 0,-2 -1,-6 -2,-7l0 0z"'
                "/>"
            );
        } else if (!day) {
            if (id == 0) {
                render = string.concat(
                    //Head
                    " <linearGradient id="
                    '"id0"'
                    " gradientUnits="
                    '"userSpaceOnUse"'
                    " x1="
                    '"127.5"'
                    " y1="
                    '"106.15"'
                    " x2="
                    '"127.5"'
                    " y2="
                    '"183.851"'
                    ">",
                    " <stop offset="
                    '"0"'
                    " style="
                    '"stop-opacity:1; stop-color:#2B2C5A"'
                    "/>",
                    " <stop offset="
                    '"1"'
                    " style="
                    '"stop-opacity:1; stop-color:#FEFEFE"'
                    "/>",
                    "</linearGradient>",
                    //Background
                    "<polygon fill="
                    '"url(#id0)"'
                    " points="
                    '"253,15 253,275 2,275 2,15"'
                    "/>",
                    //Walls
                    " <path fill="
                    '"black"'
                    " d="
                    '"M16 233l13 0 0 -61 52 0 0 61 7 0 0 -74 79 0 0 74 7 0 0 -61 52 0 0 61 13 0 0 42 -92 0 0 -15c0,-4 -9,-12 -19,-12l0 0c-11,0 -20,7 -20,12l0 15 -92 0 0 -42zm176 -7l0 -15c0,-4 4,-7 8,-7l0 0c4,0 8,3 8,7l0 15 -16 0zm-54 -20l0 -14c0,-3 3,-6 7,-6l0 0c4,0 8,3 8,6l0 14 -15 0zm-36 0l0 -14c0,-3 4,-6 8,-6l0 0c4,0 7,3 7,6l0 14 -15 0zm-55 20l0 -15c0,-4 4,-7 8,-7l0 0c4,0 8,3 8,7l0 15 -16 0z"'
                    "/>",
                    //door
                    "<path fill="
                    '"black"'
                    " d="
                    '"M110 275l0 -14c0,-4 8,-11 18,-11l0 0c9,0 18,7 18,11l0 14 -36 0z"'
                    "/>",
                    //window
                    "<path fill="
                    '"black"'
                    " d="
                    '"M193 225l0 -14c0,-3 3,-6 7,-6l0 0c4,0 7,3 7,6l0 14 -14 0zm-145 0l0 -14c0,-3 3,-6 7,-6l0 0c4,0 7,3 7,6l0 14 -14 0zm55 -21l0 -11c0,-2 3,-5 6,-5l0 0c4,0 7,3 7,5l0 11 -13 0zm36 0l0 -11c0,-2 3,-5 7,-5l0 0c3,0 6,3 6,5l0 11 -13 0z"'
                    "/>",
                    // Roof
                    " <path fill="
                    '"black"'
                    " d="
                    '"M231 170l-62 0 31 -43 31 43zm-145 0l-62 0 31 -43 31 43zm87 -12l-91 0 46 -51 45 51z"'
                    "/>",
                    //Moon
                    " <path fill="
                    '"#FEFEFE"'
                    "  d="
                    '"M231 56c-5,1 -8,4 -15,2 -12,-3 -15,-18 -8,-25 2,-2 3,-2 5,-4 -6,0 -12,4 -15,9 -7,11 1,27 17,27 5,0 10,-3 13,-6 1,0 2,-2 3,-3zm-40 7l1 1c0,0 0,0 1,1l1 -1c0,-1 0,-1 1,-1 -1,0 -1,-1 -2,-2l0 0c-1,1 -1,1 -2,2zm-4 -17c1,0 1,0 2,1 0,0 0,0 0,1 1,-2 1,-2 3,-3 -2,0 -2,0 -3,-2 0,1 0,1 -1,2 0,0 0,0 0,0l-1 1zm21 24c1,1 1,1 2,2l0 0c1,-1 1,-1 1,-1 0,-1 1,-1 1,-1 -2,-1 -1,-1 -2,-2 -1,1 -1,1 -2,2zm13 -18c1,0 1,1 2,1 1,-1 1,-1 3,-2 -2,0 -2,0 -3,-2 -1,2 0,1 -2,2l0 1zm-9 -16c2,0 4,2 4,3 1,-2 0,-1 3,-3 -2,0 -2,-1 -3,-3 0,2 -1,3 -4,3z"'
                    "/>"
                );
            }

            if (id > 0) {
                render = string.concat(
                    " <linearGradient id="
                    '"id0"'
                    " gradientUnits="
                    '"userSpaceOnUse"'
                    " x1="
                    '"127.5"'
                    " y1="
                    '"106.15"'
                    " x2="
                    '"127.5"'
                    " y2="
                    '"183.851"'
                    ">",
                    " <stop offset="
                    '"0"'
                    " style="
                    '"stop-opacity:1; stop-color:#2B2C5A"'
                    "/>",
                    " <stop offset="
                    '"1"'
                    " style="
                    '"stop-opacity:1; stop-color:#FEFEFE"'
                    "/>",
                    "</linearGradient>",
                    //Background
                    "<polygon fill="
                    '"url(#id0)"'
                    " points="
                    '"253,15 253,275 2,275 2,15"'
                    "/>",
                    //Walls
                    " <path fill='",
                    properties.wallColor,
                    "' d="
                    '"M16 233l13 0 0 -61 52 0 0 61 7 0 0 -74 79 0 0 74 7 0 0 -61 52 0 0 61 13 0 0 42 -92 0 0 -15c0,-4 -9,-12 -19,-12l0 0c-11,0 -20,7 -20,12l0 15 -92 0 0 -42zm176 -7l0 -15c0,-4 4,-7 8,-7l0 0c4,0 8,3 8,7l0 15 -16 0zm-54 -20l0 -14c0,-3 3,-6 7,-6l0 0c4,0 8,3 8,6l0 14 -15 0zm-36 0l0 -14c0,-3 4,-6 8,-6l0 0c4,0 7,3 7,6l0 14 -15 0zm-55 20l0 -15c0,-4 4,-7 8,-7l0 0c4,0 8,3 8,7l0 15 -16 0z"'
                    "/>",
                    //door
                    "<path fill='",
                    properties.doorColor,
                    "' d="
                    '"M110 275l0 -14c0,-4 8,-11 18,-11l0 0c9,0 18,7 18,11l0 14 -36 0z"'
                    "/>",
                    //window
                    "<path fill='",
                    properties.windowColor,
                    "' d="
                    '"M193 225l0 -14c0,-3 3,-6 7,-6l0 0c4,0 7,3 7,6l0 14 -14 0zm-145 0l0 -14c0,-3 3,-6 7,-6l0 0c4,0 7,3 7,6l0 14 -14 0zm55 -21l0 -11c0,-2 3,-5 6,-5l0 0c4,0 7,3 7,5l0 11 -13 0zm36 0l0 -11c0,-2 3,-5 7,-5l0 0c3,0 6,3 6,5l0 11 -13 0z"'
                    "/>",
                    // Roof
                    " <path fill='",
                    properties.roofColor,
                    "' d="
                    '"M231 170l-62 0 31 -43 31 43zm-145 0l-62 0 31 -43 31 43zm87 -12l-91 0 46 -51 45 51z"'
                    "/>",
                    //Moon
                    " <path fill="
                    '"#FEFEFE"'
                    "  d="
                    '"M231 56c-5,1 -8,4 -15,2 -12,-3 -15,-18 -8,-25 2,-2 3,-2 5,-4 -6,0 -12,4 -15,9 -7,11 1,27 17,27 5,0 10,-3 13,-6 1,0 2,-2 3,-3zm-40 7l1 1c0,0 0,0 1,1l1 -1c0,-1 0,-1 1,-1 -1,0 -1,-1 -2,-2l0 0c-1,1 -1,1 -2,2zm-4 -17c1,0 1,0 2,1 0,0 0,0 0,1 1,-2 1,-2 3,-3 -2,0 -2,0 -3,-2 0,1 0,1 -1,2 0,0 0,0 0,0l-1 1zm21 24c1,1 1,1 2,2l0 0c1,-1 1,-1 1,-1 0,-1 1,-1 1,-1 -2,-1 -1,-1 -2,-2 -1,1 -1,1 -2,2zm13 -18c1,0 1,1 2,1 1,-1 1,-1 3,-2 -2,0 -2,0 -3,-2 -1,2 0,1 -2,2l0 1zm-9 -16c2,0 4,2 4,3 1,-2 0,-1 3,-3 -2,0 -2,-1 -3,-3 0,2 -1,3 -4,3z"'
                    "/>"
                );
            }
        }

        return render;
    }

    function tokenSVG(uint16 id) public view returns (string memory) {
        string memory svg = string.concat(
            "<svg xmlns="
            '"http://www.w3.org/2000/svg"'
            " xml:space="
            '"preserve"'
            " width="
            '"255px"'
            " height="
            '"290px"'
            " version="
            '"1.1"'
            " style="
            '"shape-rendering:geometricPrecision; text-rendering:geometricPrecision; image-rendering:optimizeQuality; fill-rule:evenodd; clip-rule:evenodd"'
            " viewBox="
            '"0 0 255 290"'
            " xmlns:xlink="
            '"http://www.w3.org/1999/xlink"'
            ">",
            renderedTokenById(id),
            "</svg>"
        );
        return svg;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_exists(id), "Token does not exist");

        HouseProperties memory properties = getPropertiesById(uint16(id));

        if (isDay[uint16(id)]) {
            return
                string.concat(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            string.concat(
                                '{"name":"',
                                string.concat("Build #", id.toString()),
                                '","description":"',
                                string.concat("Its Sunny Outside "),
                                '","attributes":[{"trait_type":"Roof","value":"',
                                properties.roofColor,
                                '"},{"trait_type":"Window","value":"',
                                properties.windowColor,
                                '"},{"trait_type":"Wall","value":"',
                                properties.wallColor,
                                '"},{"trait_type":"Door","value":"',
                                properties.doorColor,
                                '"},{"trait_type":"Day","value":"Yes',
                                '"}],"owner":"',
                                (uint160(ownerOf(id))).toHexString(20),
                                '","image": "',
                                "data:image/svg+xml;base64,",
                                Base64.encode(bytes(tokenSVG(uint16(id)))),
                                '"}'
                            )
                        )
                    )
                );
        } else {
            if (id == 0) {
                return
                    string.concat(
                        "data:application/json;base64,",
                        Base64.encode(
                            bytes(
                                string.concat(
                                    '{"name":"',
                                    string.concat("Build - Genesis"),
                                    '","description":"',
                                    string.concat("Its Night Time "),
                                    '","attributes":[{"trait_type":"Roof","value":"black"},{"trait_type":"Window","value":"black"},{"trait_type":"Wall","value":"black"},{"trait_type":"Door","value":"black"},{"trait_type":"Day","value":"No',
                                    '"}],"owner":"',
                                    (uint160(ownerOf(id))).toHexString(20),
                                    '","image": "',
                                    "data:image/svg+xml;base64,",
                                    Base64.encode(bytes(tokenSVG(uint16(id)))),
                                    '"}'
                                )
                            )
                        )
                    );
            } else {
                return
                    string.concat(
                        "data:application/json;base64,",
                        Base64.encode(
                            bytes(
                                string.concat(
                                    '{"name":"',
                                    string.concat("Build#", id.toString()),
                                    '","description":"',
                                    string.concat("Its Night Time"),
                                    '","attributes":[{"trait_type":"Roof","value":"',
                                    properties.roofColor,
                                    '"},{"trait_type":"Window","value":"',
                                    properties.windowColor,
                                    '"},{"trait_type":"Wall","value":"',
                                    properties.wallColor,
                                    '"},{"trait_type":"Door","value":"',
                                    properties.doorColor,
                                    '"},{"trait_type":"Day","value":"No',
                                    '"}]',
                                    ',"image": "',
                                    "data:image/svg+xml;base64,",
                                    Base64.encode(bytes(tokenSVG(uint16(id)))),
                                    '"}'
                                )
                            )
                        )
                    );
            }
        }
    }

    function getMintFee() public pure returns (uint256) {
        return mintFee;
    }

     function getTotalSupply() public view returns (uint256) {
        return tokenCounter;
    }
}

