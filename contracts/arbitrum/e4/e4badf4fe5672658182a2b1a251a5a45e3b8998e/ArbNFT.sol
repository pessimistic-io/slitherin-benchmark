// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Base64.sol";

contract ArbNFT is ERC721, Ownable, Pausable {
    constructor() ERC721("ArbitrumNFT", "ARBNFT") Ownable() {}

    using Strings for uint256;

    uint256 public constant maxSupply = 10000;
    uint256 public numClaimed = 0;
    string private _baseTokenURI;
    
    string[] private color;
    string[] private z;

    string private re1 = 'H';

    string private co1=', ';
    string private rl1='{"name": "ARBNFT #';
    string private rl3='"}';
    string private rl4='data:application/json;base64,';

    string private tr1='", "attributes": [{"trait_type": "hatBackgroundColor","value": "';
    string private tr2='"},{"trait_type": "hatLineColor","value": "';
    string private tr3='"},{"trait_type": "eyesColor","value": "';
    string private tr4='"},{"trait_type": "clothesColor","value": "';
    string private tr5='"},{"trait_type": "logoClothesColor","value": "';
    string private tr6='"},{"trait_type": "trousersColor","value": "';
    string private tr7='"}],"image": "data:image/svg+xml;base64,';

    string private bgEyes='"/><path fill-rule="evenodd" clip-rule="evenodd" d="M13 11H14H15V12V13H14H13V12V11ZM17 13V12V11H18H19V12V13H18H17Z" fill="white"/>';
    string private cEyes = '<path fill-rule="evenodd" clip-rule="evenodd" d="';
    string private eEyes = '" style="fill:#';

    struct Arb { 
        uint8 hatBg;
        uint8 hatLine;
        uint8 eyes;
        uint8 clothes;
        uint8 logoClothes;
        uint8 trousers;
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

    function random(string memory input) internal pure returns(uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }
    
    function randomOne(uint256 tokenId) internal view returns (Arb memory) {
        tokenId = 150000 - tokenId;
        uint256 seed = random(string(abi.encodePacked('ArbNFT',tokenId.toString())));
        Arb memory arb;
        arb.hatBg = uint8(seed % color.length);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.hatBg)));
        
        arb.hatLine = uint8(seed % color.length);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.hatLine)));
        
        arb.eyes = uint8(seed % color.length);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.eyes)));
        
        arb.clothes = uint8(seed % color.length);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.clothes)));
        
        arb.logoClothes = uint8(seed % color.length);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.logoClothes)));
        
        arb.trousers = uint8(seed % color.length);
        
        return arb;
    }
    // get string attributes of properties, used in tokenURI call
    function getTraits(Arb memory arb) internal view returns (string memory) {
        string memory o = string(abi.encodePacked(tr1,uint256(arb.hatBg).toString(),tr2,uint256(arb.hatLine).toString()));
        o = string(abi.encodePacked( o, tr3, uint256(arb.eyes).toString(),tr4,uint256(arb.clothes).toString()));
        return string(abi.encodePacked(o,tr5,uint256(arb.logoClothes).toString(),tr6,uint256(arb.trousers).toString(),tr7));
    }

    function getAttributes(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "MyNFT: URI query for nonexistent token");
        Arb memory arb = randomOne(tokenId);
        string memory o=string(abi.encodePacked(uint256(arb.hatBg).toString(),co1,uint256(arb.hatLine).toString()));
        o = string(abi.encodePacked(o,co1,uint256(arb.eyes).toString(),co1,uint256(arb.clothes).toString()));
        return string(abi.encodePacked(o,co1,uint256(arb.logoClothes).toString(),co1,uint256(arb.trousers).toString()));
    }

    function genEyes(uint256 h) internal view returns(string memory) {
        string memory eye = '';
        if(h%4 == 0) {
            eye = string(abi.encodePacked(eye, bgEyes, cEyes, "M14 11H13V12H14V11ZM18 11H17V12H18V11Z", eEyes));
        }
        else if(h%4 == 1) {
            eye = string(abi.encodePacked(eye, bgEyes, cEyes, "M15 11H14V12H15V11ZM19 11H18V12H19V11Z", eEyes));
        }
        else if(h%4 == 2) {
            eye = string(abi.encodePacked(eye, bgEyes, cEyes, "M15 12H14V13H15V12ZM19 12H18V13H19V12Z", eEyes));
        }
        else {
            eye = string(abi.encodePacked(eye, bgEyes, cEyes, "M14 12H13V13H14V12ZM18 12H17V13H18V12Z", eEyes));
        }
        return eye;
    }

    function genImgSVG(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "MyNFT: URI query for nonexistent token");
        Arb memory arb = randomOne(tokenId);
        string memory output = string(abi.encodePacked(z[0], z[1], z[2], z[3], z[4], z[5]));
        output = string(abi.encodePacked(output, z[6], z[7], z[8], z[9], z[10], z[11]));
        output = string(abi.encodePacked(output, z[12], z[13], color[arb.hatBg]));
        output = string(abi.encodePacked(output, z[14], color[arb.hatLine], genEyes(random(string(abi.encodePacked(re1,tokenId.toString())))), color[arb.eyes]));
        output = string(abi.encodePacked(output, z[15], color[arb.clothes], z[16], color[arb.logoClothes]));
        output = string(abi.encodePacked(output, z[17], color[arb.trousers], z[18]));
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
        //require(block.timestamp >= 1681459200, "Please wait to 08:00 UTC, 14 April 2023 to mint NFTs");
        require(numClaimed >= 0 && numClaimed < maxSupply, "invalid claim");
        //require(!isMinted[msg.sender], "you minted!");
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
