// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Base64.sol";

contract ArbNFTLuffy is ERC721, Ownable, Pausable {
    constructor() ERC721("ArbNFT Luffy OnePiece", "ArbNFT") Ownable() {}

    using Strings for uint256;

    uint256 public constant maxSupply = 10000;
    uint256 public numClaimed = 0;
    string private _baseTokenURI;
    
    string[] private color;
    string[] private z;

    bytes32 private ra1 = 'A';
    bytes32 private rb1 = 'B';
    bytes32 private rc1 = 'C';
    bytes32 private rd1 = 'D';
    bytes32 private re1 = 'H';

    string private co1=', ';
    string private rl1='{"name": "ArbNFT #';
    string private rl3='"}';
    string private rl4='data:application/json;base64,';

    string private tr1='", "attributes": [{"trait_type": "hatStyle","value": "';
    string private tr2='"},{"trait_type": "accessory","value": "';
    string private tr3='"},{"trait_type": "item","value": "';
    string private tr4='"},{"trait_type": "eyesColor","value": "';
    string private tr5='"},{"trait_type": "clothesColor","value": "';
    string private tr6='"},{"trait_type": "logoClothesColor","value": "';
    string private tr7='"},{"trait_type": "trousersColor","value": "';
    string private tr8='"},{"trait_type": "hatBackgroundColor","value": "';
    string private tr9='"},{"trait_type": "hatLineColor","value": "';
    string private tr10='"}],"image": "data:image/svg+xml;base64,';

    string private sp1 = '"/>';
    
    struct Arb { 
        uint8 hatBg;
        uint8 hatLine;
        uint8 eyes;
        uint8 clothes;
        uint8 logoClothes;
        uint8 trousers;
        uint8 accessory;
        uint8 item;
        string hatName;
        string accessoryName;
        string itemName;
    }

    struct InfoMintNFT {
        uint256 tokenId;
        uint256 mintDate;
    }

    mapping(address => bool) isMinted;
    mapping(address => InfoMintNFT) info;

    //log event
    event Mint(address user, uint256 tokenId, uint256 timestamp);

    function pause() public onlyOwner {
        _pause();
    }

    function unPause() public onlyOwner {
        _unpause();
    }

    function setZFrame(bytes calldata encodec) public onlyOwner {
        z = abi.decode(encodec, (string[]));
    }

    function setColorFrame(bytes calldata encodec) public onlyOwner {
        color = abi.decode(encodec, (string[]));
    }

    function random(bytes memory input) internal pure returns(uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }
    
    function randomOne(uint256 tokenId) internal view returns (Arb memory) {
        tokenId = 150000 - tokenId;
        uint256 colorLength = color.length;
        uint256 seed = random(abi.encodePacked('ArbNFT',tokenId.toString()));
        Arb memory arb;
        arb.hatBg = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.hatBg)));
        
        arb.hatLine = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.hatLine)));
        
        arb.eyes = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.eyes)));
        
        arb.clothes = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.clothes)));
        
        arb.logoClothes = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.logoClothes)));
        
        arb.trousers = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.trousers)));
        
        arb.hatName = genHat(random(abi.encodePacked(ra1,(150000-tokenId).toString())))[2];

        uint256 randomValue = random(abi.encodePacked(rc1,(150000-tokenId).toString()));
        if(randomValue % 9 == 0) {
            arb.accessoryName = genAccessory(randomValue)[1];
            arb.accessory = uint8(seed % colorLength);
            seed = uint256(keccak256(abi.encodePacked(seed, arb.accessory)));
        }
        
        randomValue = random(abi.encodePacked(rd1, (150000-tokenId).toString()));
        if(randomValue % 5 == 0) {
            arb.itemName = genItems(randomValue)[1];
            arb.item = uint8(seed % colorLength);
        }

        return arb;
    }
    // get string attributes of properties, used in tokenURI call
    function getTraits(Arb memory arb) internal view returns (string memory) {
        string memory o = string(abi.encodePacked(tr1, arb.hatName,tr2, arb.accessoryName, tr3, arb.itemName));
        o = string(abi.encodePacked(o, tr4, uint256(arb.eyes).toString(),tr5,uint256(arb.clothes).toString()));
        o = string(abi.encodePacked(o, tr6, uint256(arb.logoClothes).toString(),tr7,uint256(arb.trousers).toString()));
        return string(abi.encodePacked(o, tr8, uint256(arb.hatBg).toString(),tr9,uint256(arb.hatLine).toString(),tr10));
    }
   

    string[] private eyesAttributes;
    function setEyesAttributes(bytes memory encodec) public onlyOwner {
        eyesAttributes = abi.decode(encodec, (string[4]));
    }

    function genEyes(uint256 h) internal view returns(string memory) {
        string memory eye = '';
        eye = eyesAttributes[uint8(h % eyesAttributes.length)];
        return eye;
    }

    string[3][5] private hatsAttributes;
    function setHatsAttributes(bytes memory encodec) public onlyOwner {
        hatsAttributes = abi.decode(encodec, (string[3][5]));
    }
    function genHat(uint256 h) internal view returns(string[3] memory) {
        string[3] memory hat;
        hat = hatsAttributes[uint8(h % hatsAttributes.length)];
        return hat;
    }

    string[2] private accessoryAttributes;
    function setAccessoryAttributes(bytes memory encodec) public onlyOwner {
        accessoryAttributes = abi.decode(encodec, (string[2]));
    }
    function genAccessory(uint256 h) internal view returns(string[2] memory) {
        return accessoryAttributes;
    }

    string[2][2] private itemsAttributes;
    function setItemsAttributes(bytes memory encodec) public onlyOwner {
        itemsAttributes = abi.decode(encodec, (string[2][2]));
    }
    function genItems(uint256 h) internal view returns(string[2] memory) {
        string[2] memory item;
        item = itemsAttributes[uint8(h % itemsAttributes.length)];
        return item;
    }

    function genImgSVG(uint256 tokenId) public view returns (string memory) {
        Arb memory arb = randomOne(tokenId);
        string memory output = string(abi.encodePacked(z[0], z[1], z[2], z[3], z[4], z[5]));
        output = string(abi.encodePacked(output, z[6], z[7], z[8], z[9], z[10], z[11]));
        output = string(abi.encodePacked(output, z[12]));
        output = string(abi.encodePacked(output, genHat(random(abi.encodePacked(ra1,tokenId.toString())))[0], color[arb.hatBg], sp1));
        output = string(abi.encodePacked(output, genHat(random(abi.encodePacked(ra1,tokenId.toString())))[1], color[arb.hatLine], sp1));
        output = string(abi.encodePacked(output, genEyes(random(abi.encodePacked(re1,tokenId.toString()))), color[arb.eyes], sp1));

        uint256 randomValue = random(abi.encodePacked(rc1,tokenId.toString()));
        if(randomValue % 9 == 0) {
            output = string(abi.encodePacked(output, genAccessory(randomValue)[0], color[arb.accessory], sp1));
        }
        output = string(abi.encodePacked(output, z[13], color[arb.clothes], sp1, z[14], color[arb.logoClothes], sp1));

        randomValue = random(abi.encodePacked(rd1,tokenId.toString()));
        if(randomValue % 5 == 0) {
            output = string(abi.encodePacked(output, genItems(randomValue)[0], color[arb.item], sp1));
        }
        output = string(abi.encodePacked(output, z[15], color[arb.trousers], sp1, z[16]));
        return output;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function updateBaseTokenURI(string calldata baseTokenURI_) public onlyOwner {
        _baseTokenURI = baseTokenURI_;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "MyNFT: URI query for nonexistent token");
        string memory baseURI = _baseURI();
        if(bytes(baseURI).length != 0) {
            return string(abi.encodePacked(baseURI, tokenId.toString()));
        }
        else {
            Arb memory arb = randomOne(tokenId);
            return string(abi.encodePacked(rl4,Base64.encode(bytes(string(abi.encodePacked(rl1,tokenId.toString(),getTraits(arb),Base64.encode(bytes(genImgSVG(tokenId))),rl3))))));
        }
    }

    function getInfoMintUser(address user) public view returns(InfoMintNFT memory)
    {
        return info[user];
    }

    function mint() external {
        require(!paused(), "Contract is paused");
        require(numClaimed >= 0 && numClaimed < maxSupply, "invalid claim");
        require(!isMinted[msg.sender], "you minted!");
        _safeMint(_msgSender(), numClaimed);
        isMinted[msg.sender] = true;
        emit Mint(msg.sender, numClaimed, block.timestamp);
        info[msg.sender].tokenId = numClaimed;
        info[msg.sender].mintDate = block.timestamp;
        numClaimed += 1;
    }

    function listNFTOfOwner(address owner) public view returns(uint256[] memory ownerTokens) {
        uint256 tokenCount = balanceOf(owner);

        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 resultIndex = 0;
            uint256 id;
            for (id = 0; id < numClaimed; id++) {
                if (ownerOf(id) == owner) {
                    result[resultIndex] = id;
                    resultIndex++;
                }
            }
            return result;
        }
    }
}
