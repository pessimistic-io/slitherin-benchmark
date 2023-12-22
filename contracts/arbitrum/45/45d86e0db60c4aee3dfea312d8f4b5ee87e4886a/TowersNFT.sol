//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./console.sol";
import "./ERC721.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./TowerTypes.sol";
import { Base64 } from "./Base64.sol";

contract TowersNFT is ERC721, Ownable, ReentrancyGuard {
    mapping(uint256 => uint256) public idToNumStories;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint256 public constant MAX_TOWERS = 3000;
    uint256 private constant MAX_PER_ADDRESS = 3;

    address public magicAddress = address(0);//address(0x539bdE0d7Dbd336b79148AA742883198BBF60342);
    uint256 public minimumMagicAmount = 5000000000000000000;    //in wei
    uint256 public publicSaleStartTimestamp;
    uint256 public mintPrice = 0.0 ether;

    mapping(address => uint256) public mintedCounts;

    constructor() ERC721("City Clash Towers", "City Clash Towers is a collection of 3000 single-floor tower NFTs. Holders can merge two NFTs to create a single tower with the height of the two combined (max 100 floors). To merge, holders select one tower to grow, and one to burn on our site. Tower holders will get an advantage later, in City Clash, by burning their tower in order to increase the value of one of their cities. The value increase will be proportional to the number of floors of the burned tower. TL;DR: You are going to want to grow your tower!") {
        // console.log("Deploying BlahNFT");
    }

    modifier whenPublicSaleActive() {
        require(isPublicSaleOpen(), "Public sale not open");
        _;
    }

    function mintPublicSale(uint256 _count) external payable nonReentrant whenPublicSaleActive returns (uint256, uint256) {
        require(_count > 0 && _count <= MAX_PER_ADDRESS, "Invalid Tower count");
        require(_tokenIds.current() + _count <= MAX_TOWERS, "All Towers have been minted");
        require(_count * mintPrice == msg.value, "Incorrect amount of ether sent");
        if(magicAddress != address(0)) {
            uint256 magicBalance = IERC20(magicAddress).balanceOf(address(msg.sender));
            require(magicBalance >= minimumMagicAmount, "You need 5 magic to mint");
        }

        uint256 userMintedAmount = mintedCounts[msg.sender] + _count;
        require(userMintedAmount <= MAX_PER_ADDRESS, "Max count per address exceeded");

        uint256 firstMintedId = _tokenIds.current() + 1;

        for (uint256 i = 0; i < _count; i++) {
            _tokenIds.increment();
            mint(_tokenIds.current());
        }
        mintedCounts[msg.sender] = userMintedAmount;

        return (firstMintedId, _count);
    }

    function mint(uint256 _tokenId) internal {
        idToNumStories[_tokenId] = 1;
        _safeMint(msg.sender, _tokenId);
    }

    function getRemainingMints(address _addr) public view returns (uint256) {
        return MAX_PER_ADDRESS - mintedCounts[_addr];
    }

    function isPublicSaleOpen() public view returns (bool) {
        return block.timestamp >= publicSaleStartTimestamp && publicSaleStartTimestamp != 0;
    }

    function setPublicSaleTimestamp(uint256 _timestamp) external onlyOwner {
        publicSaleStartTimestamp = _timestamp;
    }

    function setMintPrice(uint256 _price) external onlyOwner {
        mintPrice = _price;
    }

    function tokensMinted() public view returns (uint256) {
        return _tokenIds.current();
    }

    function getTokenIds() public view returns (uint256) {
        return _tokenIds.current();
    }

    function setMagicAddress(address _magicAddress) external onlyOwner {
        magicAddress = _magicAddress;
    }

    function setMinimumMagicAmount(uint256 _minimumAmount) external onlyOwner {
        minimumMagicAmount = _minimumAmount;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
        uint256 numStories = idToNumStories[_tokenId];
        (, string memory groundColor) = getGroundColor(_tokenId);
        (, string memory treeColor) = getTreeColor(_tokenId);
        (, string memory windowColor) = getWindowColor(_tokenId);
        (, string memory towerColor) = getTowerColor(_tokenId);
        string memory attributes = string(
            abi.encodePacked(
                '{"trait_type": "# of Stories",',
                '"value": ', uintToByteString(numStories, 3),
                '},{"trait_type": "Tower Color",',
                '"value": "', towerColor,
                '"}, {"trait_type": "Tree Side",',
                '"value": "', getTreeSide(_tokenId),
                '"}, '
            )
        );
        attributes = string(
            abi.encodePacked(
                attributes,
                '{"trait_type": "Cloud Side",',
                '"value": "', getCloudSide(_tokenId),
                '"}, {"trait_type": "Tree Color",',
                '"value": "', treeColor,
                '"}, {"trait_type": "Window Color",',
                '"value": "', windowColor,
                '"}, {"trait_type": "Ground Color",',
                '"value": "', groundColor,
                '"}'
            )
        );

        string memory imageString = getImage(numStories, _tokenId);
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{',
                            '"name": "Tower #', uintToByteString(_tokenId, 4),
                            '", "tokenId": ', uintToByteString(_tokenId, 4),
                            ', "image": "data:image/svg+xml;base64,',  Base64.encode(bytes(imageString)),
                            '", "description": "Build your towers to the sky!",',
                            '"attributes": [',
                                attributes,
                            ']',
                        '}'
                    )
                )
            )
        );

        string memory finalTokenUri = string(abi.encodePacked("data:application/json;base64,", json));
        console.log("\n--------------------");
        console.log(finalTokenUri);
        console.log("--------------------\n");
        return finalTokenUri;
    }

    function getImage(uint _numStories, uint _tokenId) private view returns (string memory) {
        TowerTypes.TowerParams memory tp;
        tp.roofHeight = 25;
        tp.numWindows = 2;
        tp.isAntennasIncluded = false;
        if(_numStories > 50) {
            tp.numWindows = 8;
            tp.roofHeight = 45;
        } else if(_numStories > 25) {
            tp.numWindows = 7;
            tp.roofHeight = 75;
            tp.isAntennasIncluded = true;
        } else if(_numStories > 10) {
            tp.numWindows = 6;
            tp.roofHeight = 95;
            tp.isAntennasIncluded = true;
        } else if(_numStories > 8) {
            tp.numWindows = 5;
            tp.roofHeight = 85;
            tp.isAntennasIncluded = true;
        } else if(_numStories > 6) {
            tp.numWindows = 4;
            tp.roofHeight = 65;
        } else if(_numStories > 3) {
            tp.numWindows = 3;
            tp.roofHeight = 45;
        }

        tp.maxHeight = 14 * 110 + 100;
        tp.heightInPixels = min(_numStories * 110 + 100, tp.maxHeight);
        
        tp.whiteBackgroundHeight = tp.heightInPixels - 100;
        tp.windowLength = 50;
        if(tp.heightInPixels == tp.maxHeight) {
            uint amountPerWindow = (tp.whiteBackgroundHeight) / _numStories;
            tp.windowLength = amountPerWindow * 10 / 23;
            console.log(tp.windowLength);
        }

        uint stripLength = (18 * tp.windowLength / 10) - tp.windowLength;
        tp.fullWindowWidth = (stripLength * tp.numWindows) + (tp.windowLength * tp.numWindows) - stripLength;
        tp.towerWidth = tp.fullWindowWidth + (tp.windowLength * (14 / uint(10)));

        tp.buildingStartingX = 1000 - uint(tp.towerWidth / 2);
        tp.windowStartingX = ((tp.towerWidth - tp.fullWindowWidth) / 2) + tp.buildingStartingX;
        
        (tp.colorForToken,) = getTowerColor(_tokenId);
        tp.windows = getWindows(_numStories, tp);
        
        tp.antennas = '';
        if(tp.isAntennasIncluded) {
            tp.antennas = string(abi.encodePacked(getAntennaOne(tp), getAntennaTwo(tp)));
        }
        
        return string(
            abi.encodePacked(
                getSvg1(tp, _tokenId),
                getSvg2(tp),
                getSvg3(tp, _tokenId),
                getSvg4(tp, _numStories),
                getSvg5(tp, _numStories),
                getSvg6(tp, _tokenId),
                getSvg7(tp, _tokenId),
                getSvg8(tp, _tokenId),
                getSvg9(tp, _tokenId)
            )
        );
    }

    function getWindows(uint _numStories, TowerTypes.TowerParams memory _tp) private pure returns (string  memory str) {
        string memory windows = "";
       
        //for vertical
        for(uint k = 0; k < _numStories; k++) {
            uint height = _tp.whiteBackgroundHeight / _numStories - _tp.windowLength;// + 1;
            uint y = 2000 - _tp.heightInPixels + _tp.windowLength + ((_tp.windowLength + height) * k);
            windows = string(
                abi.encodePacked(
                    windows,
                    '<rect x="', uintToByteString(_tp.windowStartingX - 1, 4),
                    '" y="', uintToByteString(y, 4),
                    '" width="', uintToByteString(_tp.fullWindowWidth + 2, 4),
                    '" height="', uintToByteString(height, 4),
                    '" fill="', _tp.colorForToken,
                    '"/>'
                )
            );
        }

        //for horizontal
        uint windowStartingY = 2000 - _tp.heightInPixels - 1;
        for(uint i = 0; i < _tp.numWindows - 1; i++) {
            uint stripLength = (18 * _tp.windowLength / 10) - _tp.windowLength;
            uint x = _tp.windowStartingX + _tp.windowLength * (i + 1) + stripLength * i;
            windows = string(
                abi.encodePacked(
                    windows,
                    '<rect x="', uintToByteString(x, 4),
                    '" y="', uintToByteString(windowStartingY, 4),
                    '" width="', uintToByteString(stripLength, 4),
                    '" height="', uintToByteString(_tp.whiteBackgroundHeight + 2, 4),
                    '" fill="', _tp.colorForToken,
                    '"/>'
                )
            );
        }
        return windows;
    }

    function getAntennaOne(TowerTypes.TowerParams memory _tp) private pure returns (string memory str) {
        uint heightOne = _tp.windowLength * 5;
        return string(
            abi.encodePacked('<rect x="', uintToByteString(_tp.buildingStartingX + _tp.fullWindowWidth - 10, 4),
                '" y="', uintToByteString(2000 + (_tp.fullWindowWidth / 15) - _tp.heightInPixels - heightOne - 20 - _tp.roofHeight, 4),
                '" width="', uintToByteString(_tp.windowLength / 4, 4),
                '" height="', uintToByteString(heightOne, 4),
                '" fill="', _tp.colorForToken,
                '"/>'
            )
        );
    }

    function getAntennaTwo(TowerTypes.TowerParams memory _tp) private pure returns (string memory str) {
        uint heightTwo = _tp.windowLength * 3;
        return string(
            abi.encodePacked(
                '<rect x="', uintToByteString(_tp.buildingStartingX + _tp.fullWindowWidth + _tp.windowLength - 18,  4),
                '" y="', uintToByteString(2000 + (_tp.fullWindowWidth / 20) - _tp.heightInPixels - heightTwo - 20 - _tp.roofHeight, 4),
                '" width="', uintToByteString(_tp.windowLength / 4, 4),
                '" height="', uintToByteString(heightTwo, 4),
                '" fill="', _tp.colorForToken,
                '"/>'
            )
        );
    }

    function getSvg1(TowerTypes.TowerParams memory _tp, uint _tokenId) private pure returns (string memory str) {
        (string memory groundColor,) = getGroundColor(_tokenId);
        return string(
            abi.encodePacked(
                '<svg width="2000" height="2000" viewBox="0 0 2000 2000" fill="none" xmlns="http://www.w3.org/2000/svg">',
                    '<rect width="2000" height="2000" fill="#D0F9FC"/>',
                    '<rect y="1925" width="2000" height="2000" fill="',
                    groundColor,
                    '"/>',
                    '<rect x="', uintToByteString(_tp.buildingStartingX, 4)
            )
        );
    }

    function getSvg2(TowerTypes.TowerParams memory _tp) private pure returns (string memory str) {
        return string(
            abi.encodePacked(
                    '" y="', uintToByteString(2000 - _tp.heightInPixels - 50, 4),
                    '" width="', uintToByteString(_tp.towerWidth, 4),
                    '" height="',uintToByteString( _tp.heightInPixels, 4),
                    '" fill="', _tp.colorForToken,
                    '"/>'
            )
        );
    }

    function getSvg3(TowerTypes.TowerParams memory _tp, uint _tokenId) private pure returns (string memory str) {
        (string memory windowColor,) = getWindowColor(_tokenId);
        return string(
            abi.encodePacked(
                    '<rect x="', uintToByteString(_tp.windowStartingX, 4),
                    '" y="', uintToByteString(2000 - _tp.heightInPixels, 4),
                    '" width="', uintToByteString(_tp.fullWindowWidth, 4),
                    '" height="', uintToByteString(_tp.whiteBackgroundHeight - 1, 4),
                    '" fill="', windowColor,
                    '"/>'
            )
        );          
    }

    function getSvg4(TowerTypes.TowerParams memory _tp, uint _numStories) private pure returns (string memory str) {
        uint height = _tp.whiteBackgroundHeight / _numStories - _tp.windowLength;
        uint y = 2000 - _tp.heightInPixels + ((_tp.windowLength + height) * _numStories - 1);
        uint rectHeight = 2000 - _tp.heightInPixels + _tp.whiteBackgroundHeight + 1 - y;
        return string(
            abi.encodePacked(
                    '<rect x="', uintToByteString(_tp.windowStartingX - 2, 4),
                    '" y="', uintToByteString(y - 1, 4),
                    '" width="', uintToByteString(_tp.fullWindowWidth + 4, 4),
                    '" height="', uintToByteString(rectHeight + 2, 4),
                    '" fill="', _tp.colorForToken,
                    '"/>'
            )
        );          
    }

    function getSvg5(TowerTypes.TowerParams memory _tp, uint _numStories) private pure returns (string memory str) {
        uint heightLen = 4;
        if(_numStories > 7) {
            heightLen = 3;
        }
        return string(
            abi.encodePacked(
                    '<path d="M', uintToByteString(_tp.buildingStartingX + _tp.towerWidth, 4),
                    ' ', uintToByteString(2000 - _tp.heightInPixels - _tp.roofHeight - 50, heightLen),
                    'L', uintToByteString(_tp.buildingStartingX, heightLen),
                    ' ', uintToByteString(2000 - _tp.heightInPixels + 1 - 50, heightLen)    //needs to be 4 in certain circ
            )
        );
    }

    function getSvg6(TowerTypes.TowerParams memory _tp, uint _tokenId) private pure returns (string memory str) {
        string memory treeSide = getTreeSide(_tokenId);
        uint x = _tp.buildingStartingX - (_tp.windowLength * 6 + _tp.windowLength / uint(4));
        if(keccak256(abi.encodePacked(treeSide)) == keccak256(abi.encodePacked("Right"))) {
            x = _tp.buildingStartingX + _tp.towerWidth + (_tp.windowLength * 6 + _tp.windowLength / uint(4));
        }
        return string(
            abi.encodePacked(
                '.5H', uintToByteString(_tp.buildingStartingX + _tp.towerWidth, 4),
                'V353Z" fill="', _tp.colorForToken,
                '"/>'
                '<rect x="', uintToByteString(x, 4),
                '" y="', uintToByteString(2000 - 3 * _tp.windowLength - 50, 4),
                '" width="', uintToByteString(_tp.windowLength,  4) //was times uint(9) / uint(10)
            )
        );
    }

    function getSvg7(TowerTypes.TowerParams memory _tp, uint _tokenId) private pure returns (string memory str) {
        string memory treeSide = getTreeSide(_tokenId);
        uint x = _tp.buildingStartingX - (_tp.windowLength * 6) + (uint(13) / uint(10) * _tp.windowLength / 3);
        if(keccak256(abi.encodePacked(treeSide)) == keccak256(abi.encodePacked("Right"))) {
            x = _tp.buildingStartingX + _tp.towerWidth + (_tp.windowLength * 7) - (_tp.windowLength / 7);
        }
        (string memory treeColor,) = getTreeColor(_tokenId);
        return string(
            abi.encodePacked(
                '" height="', uintToByteString(3 * _tp.windowLength, 4),
                '" fill="#460509" fill-opacity="0.92"/>',
                '<circle cx="', uintToByteString(x, 4),
                '" cy="', uintToByteString(2000 - (2 * _tp.windowLength + uint(25) / uint(10) * _tp.windowLength) - 50, 4),
                '" r="', uintToByteString(2 * _tp.windowLength, 4),
                '" fill="', treeColor,
                '"/>'
            )
        );
    }
    
    function getSvg8(TowerTypes.TowerParams memory _tp, uint _tokenId) private pure returns (string memory str) {
        uint startingX = 350;
        string memory cloudSide = getCloudSide(_tokenId);
        if(keccak256(abi.encodePacked(cloudSide)) == keccak256(abi.encodePacked("Right"))) {
            startingX = 1450;
        }
        return string(
            abi.encodePacked(
                 '<ellipse cx="', uintToByteString(startingX + 16 / uint(10) * _tp.windowLength * 2 - 10, 4),
                '" cy="150" rx="', uintToByteString(3 * _tp.windowLength, 4),
                '" ry="', uintToByteString(2 * _tp.windowLength, 4),
                '" fill="#FDFAFA"/>',
                '<ellipse cx="', uintToByteString(startingX, 4),
                '" cy="', uintToByteString(157 + 13 / uint(10) * _tp.windowLength * 2 - 14 / uint(10) * _tp.windowLength, 4),
                '" rx="', uintToByteString(3 * _tp.windowLength, 4),
                '" ry="', uintToByteString(2 * _tp.windowLength, 4),
                '" fill="#FDFAFA"/>'  
            )
        );
    }

    function getSvg9(TowerTypes.TowerParams memory _tp, uint _tokenId) private pure returns (string memory str) {
        uint startingX = 350;
        string memory cloudSide = getCloudSide(_tokenId);
        if(keccak256(abi.encodePacked(cloudSide)) == keccak256(abi.encodePacked("Right"))) {
            startingX = 1450;
        }
        return string(
            abi.encodePacked(
                '<ellipse cx="', uintToByteString(startingX + 2 * _tp.windowLength * 2 - 10, 4),
                '" cy="', uintToByteString(157 + 13 / uint(10) * _tp.windowLength * 2 - 14 / uint(10) * _tp.windowLength, 4),
                '" rx="', uintToByteString(4 * _tp.windowLength, 4),
                '" ry="', uintToByteString(2 * _tp.windowLength,  4),
                '" fill="#FDFAFA"/>',
                _tp.antennas,
                _tp.windows,
                '</svg>'
            )
        );
    }

    function getTowerColor(uint _tokenId) private pure returns (string memory str, string memory name) {
        uint num = uint(keccak256(abi.encodePacked(_tokenId)));
        uint colorNum = uint8(num % 20);  //mod by the number of colors
        if(colorNum == 0) {
            return ("#FE8670", "Lite Red");
        } else if(colorNum == 1) {
            return ("#A0DAA2", "Green Trance");
        } else if(colorNum == 2) {
            return ("#2C8CC7", "Steel Blue");
        } else if(colorNum == 3) {
            return ("#70161E", "Arterial Blood Red");
        } else if(colorNum == 4) {
            return ("#E7A0D4", "Spring Blossoms"); 
        } else if(colorNum == 5) {
            return ("#4B4237", "Brown Bear");
        } else if(colorNum == 6) {
            return ("Goldenrod", "#D5A021"); 
        } else if(colorNum == 7) {
            return ("#662E9B", "Rebecca Purple"); 
        } else if(colorNum == 8) {
            return ("#1D201F", "Jet Set"); 
        } else if(colorNum == 9) {
            return ("#DC2626", "Whero Red");
        } else if(colorNum == 10) {
            return ("#A663CC", "Rich Lavender");
        } else if(colorNum == 11) {
            return ("#301A4B", "Russian Violet");
        } else if(colorNum == 12) {
            return ("#25B4B4", "Caicos Turquoise");
        } else if(colorNum == 13) {
            return ("#672A4E", "Ebizome Purple");
        } else if(colorNum == 14) {
            return ("#26532B", "Pine");
        } else if(colorNum == 15) {
            return ("#D2A9EA", "Bright Ube"); 
        } else if(colorNum == 16) {
            return ("#8F250C", "Uluru Red");
        } else if(colorNum == 17) {
            return ("#820263", "Xereus Purple");
        } else if(colorNum == 18) {
            return ("#F6D241", "Basket of Gold"); 
        } else if(colorNum == 19) {
            return ("#F97316", "Orange");
        }
    }

    function getWindowColor(uint _tokenId) private pure returns (string memory str, string memory name) {
        uint num = uint(keccak256(abi.encodePacked(_tokenId)));
        uint colorNum = uint8(num % 4);  //mod by the number of colors
        if(colorNum == 0) {
            return ("#fff", "White");
        } else if(colorNum == 1) {
            return ("#E5E5E5", "Gray");
        } else if(colorNum == 2) {
            return ("#fff", "White");
        } else if(colorNum == 3) {
            return ("#DCF6FE", "Blue");
        }
    }

    function getGroundColor(uint _tokenId) private pure returns (string memory str, string memory name) {
        uint num = uint(keccak256(abi.encodePacked(_tokenId)));
        uint colorNum = uint8(num % 6);  //mod by the number of colors
        if(colorNum == 0) {
            return ("#B7B7A4", "Clay");
        } else if(colorNum == 1) {
            return ("#BCB8A1", "Sand");
        } else if(colorNum == 2) {
            return ("#E5E5E5", "Snow");
        } else if(colorNum == 3) {
            return ("#84A59D", "Grass");
        } else if(colorNum == 4) {
            return ("#8D99AE", "Cement");
        } else if(colorNum == 5) {
            return ("#577590", "Asphalt");
        }
    }

     function getTreeColor(uint _tokenId) private pure returns (string memory str, string memory name) {
        uint num = uint(keccak256(abi.encodePacked(_tokenId)));
        uint colorNum = uint8(num % 3);  //mod by the number of colors
        if(colorNum == 0) {
            return ("#267B24", "Deciduous");
        } else if(colorNum == 1) {
            return ("#1D4A3F", "Evergreen");
        } else if(colorNum == 2) {
            return ("#81B29A", "Palm");
        }
    }

    function getTreeSide(uint _tokenId) private pure returns (string memory side) {
        uint num = uint(keccak256(abi.encodePacked(_tokenId)));
        uint treeSide = uint8(num % 3);
        if(treeSide == 0) {
            return "Right";
        } else {
            return "Left";
        }
    }

    function getCloudSide(uint _tokenId) private pure returns (string memory side) {
        uint num = uint(keccak256(abi.encodePacked(_tokenId)));
        uint cloudSide = uint8(num % 2);
        if(cloudSide == 0) {
            return "Right";
        } else {
            return "Left";
        }
    }

    function min(uint _num1,  uint _num2) internal pure returns (uint minNum) {
        if(_num1 < _num2) {
            return _num1;
        } else {
            return _num2;
        }
    }

    /*
    Convert uint to byte string, padding number string with spaces at end.
    Useful to ensure result's length is a multiple of 3, and therefore base64 encoding won't
    result in '=' padding chars.
    */
    function uintToByteString(uint _a, uint _fixedLen) internal pure returns (bytes memory _uintAsString) {
        uint j = _a;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(_fixedLen);
        j = _fixedLen;
        if (_a == 0) {
            bstr[0] = "0";
            len = 1;
        }
        while (j > len) {
            j = j - 1;
            bstr[j] = bytes1(' ');
        }
        uint k = len;
        while (_a != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_a - _a / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _a /= 10;
        }
        return bstr;
    }
}
