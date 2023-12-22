// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";
import "./IERC721A.sol";
import "./Counters.sol";
import "./ERC721.sol";
import "./IERC721.sol";
import "./Strings.sol";

contract AiAkita is ERC721, Ownable{
    
    enum Types{PLAYER, CHEMIST, HEALER, SILVER, PRO, MASTER, GUARDS, MINISTERS, KINGS}
    
    uint256 MAX_SUPPLY = 12131;
    
    uint256 public totalSupply;
    using Counters for Counters.Counter;
    Counters.Counter internal _tokenIdCounter;
    uint256 controllSeed;

    IERC721 public aiAkitaDog;
    IERC721 public aiAkitaFreeMint;

    mapping(uint256 => Types) public nftType;
    uint256[] typeLimits = [1931, 1800, 1700, 1600, 1500, 1400, 1000, 700, 500];
    uint256[] typeCounts;
    string public baseURI;
    
    constructor(string memory name, string memory symbol, address aiAkitaDog_, address aiAkitaFreeMint_) ERC721(name, symbol){
        aiAkitaDog = IERC721(aiAkitaDog_);
        aiAkitaFreeMint = IERC721(aiAkitaFreeMint_);
        typeCounts = new uint256[](typeLimits.length);
        controllSeed = 0;
        totalSupply = 0;
    }

    function claimFreeNFTs(uint256[] memory AiAkitaDogTokenIds, uint256[] memory AiAkitaFreeMintTokenIds) public {
        require(totalSupply + 1 <= MAX_SUPPLY, "Exceeded the max supply!");
        if(AiAkitaDogTokenIds.length > 0){
        require(aiAkitaDog.balanceOf(msg.sender) >= AiAkitaDogTokenIds.length, "User does not have enough tokens!");
            for(uint i=0; i < AiAkitaDogTokenIds.length; i++){
                
                require(aiAkitaDog.ownerOf(AiAkitaDogTokenIds[i]) == msg.sender, "User is not the owner of this NFT!");
                aiAkitaDog.safeTransferFrom(msg.sender, address(0x000000000000000000000000000000000000dEaD), AiAkitaDogTokenIds[i]);
                
                uint256 randomType = _getRandomType();
                _tokenIdCounter.increment();
                _mint(msg.sender, _tokenIdCounter.current());
                nftType[_tokenIdCounter.current()] = Types(randomType);
                totalSupply++;
                typeCounts[randomType]++;
                
            }
        }
        if(AiAkitaFreeMintTokenIds.length > 0) {
            require(aiAkitaFreeMint.balanceOf(msg.sender) >= AiAkitaFreeMintTokenIds.length, "User does not have enough tokens!");
            for(uint i=0; i < AiAkitaFreeMintTokenIds.length; i++){
                require(totalSupply + 1 <= MAX_SUPPLY, "Exceeded the max supply!");
                require(aiAkitaFreeMint.ownerOf(AiAkitaFreeMintTokenIds[i]) == msg.sender, "User is not the owner of this NFT!");
                aiAkitaFreeMint.safeTransferFrom(msg.sender, address(0x000000000000000000000000000000000000dEaD), AiAkitaFreeMintTokenIds[i]);
                
                uint256 randomType = _getRandomType();
                _tokenIdCounter.increment();
                _mint(msg.sender, _tokenIdCounter.current());
                nftType[_tokenIdCounter.current()] = Types(randomType);
                totalSupply++;
                typeCounts[randomType]++;
            }
    }
    }

    function _getRandomType() private returns(uint256) {

        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, controllSeed))) % typeLimits.length;
        uint256 startIndex = random;

        while(typeCounts[random] >= typeLimits[random]){
            random = (random + 1) % typeLimits.length;

            if(random==startIndex){
                revert("All types have reached thier limits!");
            }
        }
        controllSeed++;
        return random;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns(string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        string memory baseURI_ = _baseURI(); 
        string memory tokenType = Strings.toString(uint256(nftType[tokenId]));

        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI_, "/", tokenType, ".json")) : "";
    }

    function _baseURI() internal view virtual override returns (string memory){
        return baseURI;
    }

    function setBaseTokenURI(string memory baseURI_) public onlyOwner{
        baseURI = baseURI_;
    }

    function setTokenAddresses(address aiAkitaDog_, address aiAkitaFreeMint_) public onlyOwner{
        aiAkitaDog = IERC721(aiAkitaDog_);
        aiAkitaFreeMint = IERC721(aiAkitaFreeMint_);
    }
    
}
