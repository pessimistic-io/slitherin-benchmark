// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ERC721.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Base64.sol";

contract ArbNFTAstronautClub is ERC721, Ownable, Pausable {
    constructor() ERC721("ArbNFT Astronaut Club", "ARBA") Ownable() {}
    using Strings for uint256;

    uint256 public constant maxSupply = 9000;
    uint256 public numClaimed = 0;
    string private _baseTokenURI;
    
    string[] private color;
    string[] private z;

    uint256 public feeMint;

    bytes32 private ra1 = 'A';
    bytes32 private rb1 = 'B';

    string private co1=', ';
    string private rl1='{"name": "ARBA #';
    string private rl3='"}';
    string private rl4='data:application/json;base64,';

    string private tr1='", "attributes": [{"trait_type": "planet","value": "';
    string private tr2='"},{"trait_type": "charater","value": "';
    string private tr3='"},{"trait_type": "spaceship","value": "';
    string private tr4='"},{"trait_type": "faceColor","value": "';
    string private tr6='"},{"trait_type": "clothesLineColor","value": "';
    string private tr10='"}],"image": "data:image/svg+xml;base64,';

    string private sp1 = '"/>';
    
    struct Arb {
        uint8 faceColor;
        uint8 clothesLineColor;
        string planetName;
        string characterName;
        string spaceshipName;
    }

    struct InfoMintNFT {
        uint256 tokenId;
        uint256 mintDate;
    }

    mapping(address => InfoMintNFT) info;

    //log event
    event Mint(address user, uint256 indexed tokenId, uint256 timestamp);
    event FeeMint(uint256 feeMint);

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
        uint256 seed = random(abi.encodePacked('ARBA',tokenId.toString()));
        Arb memory arb;
        arb.faceColor = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.faceColor)));
        
        arb.clothesLineColor = uint8(seed % colorLength);
        seed = uint256(keccak256(abi.encodePacked(seed, arb.clothesLineColor)));
        
        arb.planetName = genPlanet(150000-tokenId)[1];
        arb.characterName = genCharacter(random(abi.encodePacked(ra1,(150000-tokenId).toString())))[1];
        arb.spaceshipName = genSpaceship(random(abi.encodePacked(rb1,(150000-tokenId).toString())))[1];
        return arb;
    }
    // get string attributes of properties, used in tokenURI call
    function getTraits(Arb memory arb) internal view returns (string memory) {
        string memory o = string(abi.encodePacked(tr1, arb.planetName,tr2, arb.characterName, tr3, arb.spaceshipName));
        o = string(abi.encodePacked(o, tr4, uint256(arb.faceColor).toString()));
        o = string(abi.encodePacked(o, tr6, uint256(arb.clothesLineColor).toString()));
        return string(abi.encodePacked(o,tr10));
    }

    string[2][] private planetAttributes;
    function setPlanetAttribute(bytes memory encodec) public onlyOwner {
        string[2] memory bground = abi.decode(encodec, (string[2]));
        planetAttributes.push(bground);
    }

    function genPlanet(uint256 h) internal view returns(string[2] memory) {
        string[2] memory bg;
        uint8 seed = uint8(h % (planetAttributes.length));
        bg = planetAttributes[seed];
        return bg;
    }

    string bg1 = '<image width="150" height="150" href="';
    string bg2 = '"></image>';

    string[2][] private spaceshipAttributes;
    function setSpaceshipAttributes(bytes memory encodec) public onlyOwner {
        string[2] memory spaceship = abi.decode(encodec, (string[2]));
        spaceshipAttributes.push(spaceship);
    }
    function genSpaceship(uint256 h) internal view returns(string[2] memory) {
        string[2] memory spaceship;
        spaceship = spaceshipAttributes[uint8(h % spaceshipAttributes.length)];
        return spaceship;
    }

    string[2][9] private characterAttributes;
    function setCharacterAttributes(bytes memory encodec) public onlyOwner {
        characterAttributes = abi.decode(encodec, (string[2][9]));
    }
    function genCharacter(uint256 h) internal view returns(string[2] memory) {
        string[2] memory character;
        character = characterAttributes[uint8(h % characterAttributes.length)];
        return character;
    }

    function genImgSVG(uint256 tokenId) public view returns (string memory) {
        Arb memory arb = randomOne(tokenId);
        string memory output = string(abi.encodePacked(z[0], bg1, genPlanet(tokenId)[0], bg2));
        output = string(abi.encodePacked(output, bg1, genSpaceship(random(abi.encodePacked(rb1,tokenId.toString())))[0], bg2));
        output = string(abi.encodePacked(output, z[1], color[arb.clothesLineColor], sp1, z[2], z[3], z[4]));
        output = string(abi.encodePacked(output, z[5], z[6], genCharacter(random(abi.encodePacked(ra1,tokenId.toString())))[0], color[arb.faceColor], sp1, z[7]));
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

    function setFeeMint(uint256 value) public onlyOwner{
        feeMint = value;
        //9000000000000000
        emit FeeMint(feeMint);
    }

    
    function mint() public payable {
        require(!paused(), "Contract is paused");
        require(numClaimed >= 0 && numClaimed < maxSupply, "invalid claim");
        require(msg.value >= feeMint, "you don't enought fee ETH to mint");
        _safeMint(_msgSender(), numClaimed);
        
        payable(owner()).transfer(feeMint);
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

    function totalSupply() public view virtual returns (uint256) {
        return numClaimed;
    }

}
