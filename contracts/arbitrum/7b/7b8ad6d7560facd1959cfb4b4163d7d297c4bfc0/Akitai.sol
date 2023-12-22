// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";

contract AkitaAI is ERC721, ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint maxSupply = 35000;
    address payable feeTaker;
    string baseURI;

    mapping(uint => mapping(address => uint)) public mints;

    event FeeTakerChanged(address _old, address _new);

    error MaxSupplyReached();
    error MaxMintReached();
    error MissingMintFee();
    error ZeroAddress();

    constructor(string memory uri, address payable _feeTaker) ERC721("AkitaAI", "AKTai") {
        baseURI = uri;
        feeTaker = _feeTaker;
    }

    function _baseURI() internal view override returns(string memory) {
        return baseURI;
    }

    function changeFeeTaker(address payable _feeTaker) public onlyOwner {
        if(_feeTaker == address(0)){
            revert ZeroAddress();
        }
        emit FeeTakerChanged(feeTaker, _feeTaker);
        feeTaker = _feeTaker;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory uri = _baseURI();
        return bytes(uri).length > 0 ? string(abi.encodePacked(uri, tokenId.toString(), ".json")) : "";
    }

    function safeMint(address to) public payable {
        (uint tier, uint maxTierMint, uint mintFee) = _getDetails();
        uint currentSupply = totalSupply();

        if(currentSupply >= maxSupply){
            revert MaxSupplyReached();
        } 

        if(mints[tier][to] >= maxTierMint){
            revert MaxMintReached();
        }else{
            mints[tier][to] += 1;
            if(msg.value < mintFee){
                revert MissingMintFee();
            }

            if(mintFee > 0){
                feeTaker.call{value: address(this).balance}("");
            }
        }

        _safeMint(to, currentSupply);
    }

    function safeMint() public payable {
        safeMint(msg.sender);
    }

    // returns tier, mint Amount, and mint price
    function _getDetails() internal view  returns(uint tier, uint maxTierMint, uint mintFee){
        uint currentSupply = totalSupply();
        if(currentSupply < 2000){
            return (1, 2, 0);
        }else if(currentSupply < 20000) {
            return (2, 4, 0.001 ether);
        }else {
            return (3, 6, 0.002 ether);
        }
    }


    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

