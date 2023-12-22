// SPDX-License-Identifier: GPL-3.0

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./IERC721Receiver.sol";
import "./IERC721Metadata.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Counters.sol";
import {Strings} from "./Strings.sol";

import "./Base64.sol";

pragma solidity ^0.8.0;

contract CastleDAOBallot is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;
    event Mint(address indexed owner, uint256 indexed tokenId, uint256 price);
    using Counters for Counters.Counter;
    Counters.Counter _tokenIds;

    // Colors and items
    string[] public palette = [
        "#000000",
        "#291A72",
        "#240553",
        "#2F4091",
        "#1F0C2C",
        "#142029",
        "#F48925",
        "#F7AC38",
        "#FFEF57",
        "#F0F4F7",
        "#A8ABAD",
        "#7D7F80",
        "#58788D",
        "#FFFFFF",
        "#A20000",
        "#006045",
        "#004538",
        "#C4398B",
        "#DC5D86",
        "#F48D8A",
        "#822F22",
        "#7495A8",
        "#651415",
        "#810000",
        "#7A0475",
        "#28465A",
        "#3D5C74",
        "#50B04A",
        "#007B46",
        "#CDDDE5",
        "#47094D"
    ];

    string[] public backgroundNames = [
        "base-blue",
        "base-green",
        "base-light",
        "base-purple",
        "base-red",
        "base-yellow"
    ];

    bytes[] public backgrounds = [
        bytes(
            hex"0000100003000a060300020001060a1a01060200020001060a1a01060200020001060a1a01060200020001060a1a01060200020001060a1b01060200020001060a1b01060200020001060a1b01060200020001060a1b01060200020001060a1b01060200020001060a1a01060200020001060a1a01060200020001060a1a0106020003000a060300"
        ),
        bytes(
            hex"0000100003000a06030002000106011c011d011c011d011c011d011c011d011c011d0106020002000106011d011c011d011c011d011c011d011c011d011c0106020002000106011c011d011c011d011c011d011c011d011c011d0106020002000106011d011c011d011c011d011c011d011c011d011c0106020002000106011c011d011c011d011c011d011c011d011c01100106020002000106011d011c011d011c011d011c011d011c0110011d0106020002000106011c011d011c011d011c011d011c0110011d01100106020002000106011d011c011d011c011d011c0110011d0110011d0106020002000106011c011d011c011d011c0110011d0110011d01100106020002000106011d011c011d011c0110011d0110011d0110011d0106020002000106011c011d011c0110011d0110011d0110011d01100106020002000106011d011c0110011d0110011d0110011d0110011d0106020003000a060300"
        ),
        bytes(
            hex"0000100003000a060300020001060a1601060200020001060a1601060200020001060a1601060200020001060a1601060200020001060a1e01060200020001060a1e01060200020001060a1e01060200020001060a1e01060200020001060a1e01060200020001060a1601060200020001060a1601060200020001060a160106020003000a060300"
        ),
        bytes(
            hex"0000100003000a060300020001060a1f01060200020001060a1f01060200020001060a1f01060200020001060a1f01060200020001060a1901060200020001060a1901060200020001060a1901060200020001060a1901060200020001060a1901060200020001060a1f01060200020001060a1f01060200020001060a1f0106020003000a060300"
        ),
        bytes(
            hex"0000100003000a060300020001060a1801060200020001060a1801060200020001060a1801060200020001060a1801060200020001060a0f01060200020001060a0f01060200020001060a0f01060200020001060a0f01060200020001060a0f01060200020001060a1801060200020001060a1801060200020001060a180106020003000a060300"
        ),
        bytes(
            hex"0000100003000a060300020001060a0701060200020001060a0701060200020001060a0701060200020001060a0701060200020001060a0801060200020001060a0801060200020001060a0801060200020001060a0801060200020001060a0801060200020001060a0701060200020001060a0701060200020001060a070106020003000a060300"
        )
    ];

    string[] public logoNames = [
        "blueberry",
        "castle",
        "circle",
        "cross",
        "egg",
        "footy",
        "pepe",
        "pig",
        "sword",
        "treasure"
    ];

    bytes[] public logos = [
        bytes(
            hex"000010001000100006000102010302040600040001040103020401030104020204000400020402030204020204000300070402020105030003000202040403020105030003000302020403020205030004000702010504000400050203050400060004050600100010001000"
        ),
        bytes(
            hex"0000100010001000040002060100020601000206040004000106010701060207010601070106040004000206040702060400040001060108010602080106010801060400040001060108010602080106010801060400040001060208020602080106040004000106020802060208010604000400010601070106020701060107010604000400020604070206040004000806040010001000"
        ),
        bytes(
            hex"00001000100010001000040001090600010904000500010904060109050005000106010902000109010605000500010601000209010001060500050001060100020901000106050005000106010902000109010605000500010904060109050004000109060001090400100010001000"
        ),
        bytes(
            hex"00001000100010001000060001060200010606000600010602000106060005000206020002060500070002060700070002060700050002060200020605000600010602000106060006000106020001060600100010001000"
        ),
        bytes(
            hex"00001000100010000700010a010b07000600030a010b06000500040a010b010c05000500050a010b05000400060a010b010c04000400060a010b010c04000400060a010b010c04000500040a010b010c05000600010a020b010c0600100010001000"
        ),
        bytes(
            hex"000010001000100010000400010d010e010d010e010d010e010d010e04000400010a030f010a030f04000400020f0106030f0106010f04000400010a030f010a030f04000400010d010e010d010a010d010a010d010e040006000406060005000106010e0106010a020605000400010a0100010a0106010a01060100010a04000400010a010f010a0106010a01060100010a04000600010a0106010a010606001000"
        ),
        bytes(
            hex"0000100010001000060001100200011006000400021102100211060004000106010a02100106010a06000400061006000400030f0310060005000604050004000110010004040100011004000600040406000600041006000600011002000110060010001000"
        ),
        bytes(
            hex"000010001000100005000212020002120500050006130500040001130614011304000400011301140115021401150114011304000400011302140213021401130400040001130214021302140113040004000113061401130400040001130614011304000500061305000500021502000215050010001000"
        ),
        bytes(
            hex"00001000100010000a00011605000a000116050009000116010d050009000116010d050008000116020d05000400010602000116020d0600050001060116020d0700050001150106010d0800040001150217010608000400021702000106070010001000"
        ),
        bytes(
            hex"0000100010001000060004180600040002180400021804000400080f040003000118080f01180300030001180300020f030001180300030001180300020f030001180300040001180200020f020001180400040002180100020f010002180400060004180600100010001000"
        )
    ];

    string[] public decorationNames = [
        "fancy",
        "green-marks",
        "none",
        "red-marks",
        "yellow-marks"
    ];

    bytes[] public decorations = [
        bytes(
            hex"00000108010f0100010f0119010f0119020f0119010f0119010f0100010f0108010f010801190a0001190108010f0100010f0c00010f0100010f01190c000119010f0100010f0c00010f0100010f01190c000119010f010f01190c000119010f02190c00021902190c000219010f01190c000119010f010f01190c000119010f0100010f0c00010f0100010f01190c000119010f0100010f0c00010f0100010f010801190a0001190108010f0108010f0100010f0119010f0119020f0119010f0119010f0100010f"
        ),
        bytes(
            hex"0000100002000410040004100200020001100a0001100200020001100a000110020010001000100010001000100010001000020001100a0001100200020001100a000110020002000410040004100200"
        ),
        bytes(
            hex"0000100010001000100010001000100010001000100010001000100010001000"
        ),
        bytes(
            hex"000010000200040f0400040f02000200010f0a00010f02000200010f0a00010f0200100010001000100010001000100010000200010f0a00010f02000200010f0a00010f02000200040f0400040f0200"
        ),
        bytes(
            hex"00001000020001080100020804000208010001080200100010001000100010001000100010001000100010001000020001080100020804000208010001080200"
        )
    ];

    // Seeds
    struct BallotSeed {
        uint32 background;
        uint32 logo;
        uint32 decoration;
    }

    mapping(uint256 => BallotSeed) public seeds;

    // Mint info
    bool public isLive = true;

    mapping(address => bool) public whitelisted;

    function addToWhitelistMultiple(address[] memory _accounts)
        public
        onlyOwner
    {
        uint256 size = _accounts.length;

        for (uint256 i = 0; i < size; i++) {
            address account = _accounts[i];
            whitelisted[account] = true;
        }
    }

    constructor() ERC721("CastleDAOBallot", "CASTLEBALLOT") {}

    function toggleLive() external onlyOwner {
        isLive = !isLive;
    }

    function _internalMint(
        address _address,
        uint32 _decoration,
        uint32 _background,
        uint32 _logo
    ) internal returns (uint256) {
        require(isLive == true, "Minting is not live");
        // minting logic
        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();

        // Check that the parts are correct and exist
        require(
            _decoration < decorations.length && _decoration >= 0,
            "Invalid data"
        );
        require(_logo < logos.length && _logo >= 0, "Invalid data");
        require(
            _background < backgrounds.length && _background >= 0,
            "Invalid data"
        );
        // Store the seed
        seeds[tokenId] = BallotSeed({
            background: _background,
            decoration: _decoration,
            logo: _logo
        });

        _safeMint(_address, tokenId);
        emit Mint(_address, tokenId, msg.value);
        return tokenId;
    }

    function mint(
        uint32 _decoration,
        uint32 _background,
        uint32 _logo
    ) public payable nonReentrant {
        require(whitelisted[msg.sender], "Not allowed to mint");
        _internalMint(_msgSender(), _decoration, _background, _logo);
        whitelisted[msg.sender] = false;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "URI query for nonexistent token");

        string memory data = _render(tokenId, seeds[tokenId]);
        return data;
    }

    // owner functions
    function ownerWithdraw() external onlyOwner nonReentrant {
        payable(owner()).transfer(address(this).balance);
    }

    function _render(uint256 tokenId, BallotSeed memory seed)
        internal
        view
        returns (string memory)
    {
        string memory image = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges" width="256" height="256">'
                '<rect width="100%" height="100%" fill="transparent" />',
                _renderRects(backgrounds[seed.background]),
                _renderRects(logos[seed.logo]),
                _renderRects(decorations[seed.decoration]),
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
                                '", "name": "CastleDAO Ballot #',
                                tokenId.toString(),
                                '", "decoration":"',
                                decorationNames[seed.decoration],
                                '", "background":"',
                                backgroundNames[seed.background],
                                '", "logo":"',
                                logoNames[seed.logo],
                                '", "description": "A memory for helping CastleDAO in the urnes. 16/04/2022"}'
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
        string[17] memory lookup = [
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
            "16"
        ];

        string memory rects;
        uint256 drawIndex = 0;

        for (uint256 i = 0; i < data.length; i = i + 2) {
            uint8 runLength = uint8(data[i]); // we assume runLength of any non-transparent segment cannot exceed image width (16px)

            uint8 colorIndex = uint8(data[i + 1]);

            if (colorIndex != 0 && colorIndex != 1) {
                // transparent
                uint8 x = uint8(drawIndex % 16);
                uint8 y = uint8(drawIndex / 16);
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
}

