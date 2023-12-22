// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Counters.sol";
import {MerkleProof} from "./MerkleProof.sol";

contract DopexNFT is ERC721, ERC721Enumerable, Ownable {

    using Counters for Counters.Counter;
    using Strings for uint256;

    Counters.Counter private _tokenIdCounter;

    // variables which need to be set
    uint256 public mintRate = 0.05 ether;
    uint256 public MAX_SUPPLY = 2190;
    uint256 public MAX_MINT = 10;
    uint256 public OWNER_PRE_MINT = 3;

    uint256 public whitelistMintTime = 1644685200;
    uint256 public mintTime = 1644692400;

    string public baseURI;
    uint256[] public mintIDremaining;
    mapping(address => uint256[]) public ownerMints;
    uint private randNonce = 0;

    bool changeBaseURI = true;
    bool onwerAllowedMint = true;
    bool public mintOn = true;

    mapping(address => uint256) public whitelistedStatus;
    bytes32 public merkleRoot;

    constructor() ERC721("Dopex NFT", "DopexNFT") {
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            mintIDremaining.push(i+1);}
        }

    function OnwerMint() public onlyOwner {
        require(onwerAllowedMint, 'Owner already minted');
        require(OWNER_PRE_MINT + _tokenIdCounter.current() <= MAX_SUPPLY, "Can not mint more than total maximum supply");
        for (uint256 i = 0; i < OWNER_PRE_MINT; i++) {
            uint256 randomID = random(mintIDremaining.length);
            uint256 randomMintID = mintIDremaining[randomID];
            _safeMint(msg.sender, randomMintID);
            removeID(randomID);
            _tokenIdCounter.increment();
            ownerMints[msg.sender].push(randomMintID);
            }
        onwerAllowedMint = false;
    }

    function setMerkleRoot(bytes32 _merkleRoot) onlyOwner public {
        merkleRoot = _merkleRoot;
        }

    function withdraw() public onlyOwner {
        require(address(this).balance > 0);
        payable(owner()).transfer(address(this).balance);
    }

    function changeMint(bool _mintStatus) public onlyOwner {
        mintOn = _mintStatus;
    }

    function disableChangeBaseURI() public onlyOwner {
        changeBaseURI = false;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        require(changeBaseURI);
        baseURI = _newBaseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 _tokenURI) public view virtual override returns (string memory){
        require(_exists(_tokenURI),"ERC721Metadata: URI query for nonexistent token");

        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI.toString();
        }

        return string(abi.encodePacked(base, "/", _tokenURI.toString()));
    }

    function getOwnerMints(address _ownerAddress) public view returns (uint256[] memory){
        return ownerMints[_ownerAddress];
    }

    function random(uint256 n) private returns (uint256) {
        randNonce ++;
        uint256 randomnumber = uint256(keccak256(
            abi.encodePacked(_tokenIdCounter.current(), randNonce, msg.sender, block.difficulty, block.timestamp))) % n;
        return randomnumber;
    }

    function removeID(uint256 _index) private {
        require(_index < mintIDremaining.length);
        mintIDremaining[_index] = mintIDremaining[mintIDremaining.length - 1];
        mintIDremaining.pop();
    }

    function whitelistSafeMint(
        uint256 index, 
        address beneficiary, 
        bytes32[] calldata merkleProof) public payable {

        require(mintOn);
        require(msg.sender == tx.origin, "Blocks contracts");
        require(block.timestamp >= whitelistMintTime, "Whitelisting mint has not started");
        require(block.timestamp < mintTime, "Whitelisting period has finished");
        require(whitelistedStatus[beneficiary] == 0, "already minted during whitelist period");
        require(beneficiary == msg.sender, "beneficiary not message sender");

        require(1 + _tokenIdCounter.current() <= MAX_SUPPLY, "Can not mint more than total maximum supply");
        require(msg.value >= mintRate, "Not enough eth sent");

        // Verify the merkle proof.
        uint256 amt = 1;
        bytes32 node = keccak256(abi.encodePacked(index, beneficiary, amt));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "address not whitelisted");

        whitelistedStatus[beneficiary] = 1;

        uint256 randomID = random(mintIDremaining.length);
        uint256 randomMintID = mintIDremaining[randomID];
        removeID(randomID);
        _tokenIdCounter.increment();
        _safeMint(msg.sender, randomMintID);
        ownerMints[msg.sender].push(randomMintID);
    }


    function safeMint(uint256 _mintNumber) public payable {
        require(msg.sender == tx.origin, "Block contracts");
        require(mintOn);
        require(block.timestamp >= mintTime, "Mint has not yet started");
        require(_mintNumber > 0, "Need to mint positive number of tokens");
        require(_mintNumber <= MAX_MINT, "Attempting to mint more than mint limit");
        require(_mintNumber + _tokenIdCounter.current() <= MAX_SUPPLY, "Can not mint more than total maximum supply");
        require(msg.value >= mintRate * _mintNumber, "Not enough eth sent");

        for (uint256 i = 0; i < _mintNumber; i++) {
            uint256 randomID = random(mintIDremaining.length);
            uint256 randomMintID = mintIDremaining[randomID];
            removeID(randomID);
            _tokenIdCounter.increment();
            _safeMint(msg.sender, randomMintID);
            ownerMints[msg.sender].push(randomMintID);
            }
        }


    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool){
        return super.supportsInterface(interfaceId);
    }

}

