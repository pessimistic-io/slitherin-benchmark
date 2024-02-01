// SPDX-License-Identifier: MIT
// Copyright (c) 2022 Keisuke OHNO

/*

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

pragma solidity >=0.7.0 <0.9.0;

import { Base64 } from "./base64.sol";
import "./ERC721A.sol";
import "./AccessControl.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";




//tokenURI interface
interface iTokenURI {
    function tokenURI(uint256 _tokenId) external view returns (string memory);
}

contract NinjaHalloweenMintPass is Ownable, AccessControl , ERC721A{

    constructor(
    ) ERC721A("NinjaHalloweenMintPass", "NHMP") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(AIRDROP_ROLE      , msg.sender);
        setBaseURI("ipfs://QmUKhH8JaTMHX5CY2YJC1zgvV41WXuYCxDGpYbAN54MMP6/");
        setMerkleRoot(0x79a6c9af27b8b12c70c82960ed644c169ee530abd320df72bf014c1dc9ae36ff);
        _safeMint(0xdEcf4B112d4120B6998e5020a6B4819E490F7db6, 1);//atode kesu
    }


    //
    //withdraw section
    //

    address public constant withdrawAddress = 0xdEcf4B112d4120B6998e5020a6B4819E490F7db6;

    function withdraw() public onlyOwner {
        (bool os, ) = payable(withdrawAddress).call{value: address(this).balance}('');
        require(os);
    }


    //
    //mint section
    //

    uint256 public cost = 0;
    uint256 public maxSupply = 10000;
    uint256 public maxMintAmountPerTransaction = 10;
    uint256 public publicSaleMaxMintAmountPerAddress = 10;
    bool public paused = true;
    bool public onlyWhitelisted = true;
    bool public mintCount = true;
    mapping(address => uint256) public whitelistMintedAmount;
    mapping(address => uint256) public publicSaleMintedAmount;
    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract.");
        _;
    }
 
    //mint with merkle tree
    bytes32 public merkleRoot;
    function mint(uint256 _mintAmount , uint256 _maxMintAmount , bytes32[] calldata _merkleProof) public payable callerIsUser{
        require(!paused, "the contract is paused");
        require(0 < _mintAmount, "need to mint at least 1 NFT");
        require(_mintAmount <= maxMintAmountPerTransaction, "max mint amount per session exceeded");
        require(totalSupply() + _mintAmount <= maxSupply, "max NFT limit exceeded");
        require(cost * _mintAmount <= msg.value, "insufficient funds");
        if(onlyWhitelisted == true) {
            bytes32 leaf = keccak256( abi.encodePacked(msg.sender, _maxMintAmount) );
            require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), "user is not whitelisted");
            if(mintCount == true){
                require(_mintAmount <= _maxMintAmount - whitelistMintedAmount[msg.sender] , "max NFT per address exceeded");
                whitelistMintedAmount[msg.sender] += _mintAmount;
            }
        }else{
            if(mintCount == true){
                require(_mintAmount <= publicSaleMaxMintAmountPerAddress - publicSaleMintedAmount[msg.sender] , "max NFT per address exceeded");
                publicSaleMintedAmount[msg.sender] += _mintAmount;
            }
        }
        _safeMint(msg.sender, _mintAmount);
    }

    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner {
        merkleRoot = _merkleRoot;
    }



    function airdropMint(address[] calldata _airdropAddresses , uint256[] memory _UserMintAmount) public {
        require(hasRole(AIRDROP_ROLE, msg.sender), "Caller is not a air dropper");
        uint256 _mintAmount = 0;
        for (uint256 i = 0; i < _UserMintAmount.length; i++) {
            _mintAmount += _UserMintAmount[i];
        }
        require(0 < _mintAmount , "need to mint at least 1 NFT");
        require(totalSupply() + _mintAmount <= maxSupply, "max NFT limit exceeded");
        for (uint256 i = 0; i < _UserMintAmount.length; i++) {
            _safeMint(_airdropAddresses[i], _UserMintAmount[i] );
        }
    }

    function setMaxSupply(uint256 _maxSupply) public onlyOwner() {
        maxSupply = _maxSupply;
    }

    function setPublicSaleMaxMintAmountPerAddress(uint256 _publicSaleMaxMintAmountPerAddress) public onlyOwner() {
        publicSaleMaxMintAmountPerAddress = _publicSaleMaxMintAmountPerAddress;
    }

    function setCost(uint256 _newCost) public onlyOwner {
        cost = _newCost;
    }

    function setOnlyWhitelisted(bool _state) public onlyOwner {
        onlyWhitelisted = _state;
    }

    function setMaxMintAmountPerTransaction(uint256 _maxMintAmountPerTransaction) public onlyOwner {
        maxMintAmountPerTransaction = _maxMintAmountPerTransaction;
    }
  
    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    function setMintCount(bool _state) public onlyOwner {
        mintCount = _state;
    }
 


    //
    //URI section
    //

    string public baseURI;
    string public baseExtension = ".json";

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;        
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
        baseExtension = _newBaseExtension;
    }



    //
    //interface metadata
    //

    iTokenURI public interfaceOfTokenURI;
    bool public useInterfaceMetadata = false;

    function setInterfaceOfTokenURI(address _address) public onlyOwner() {
        interfaceOfTokenURI = iTokenURI(_address);
    }

    function setUseInterfaceMetadata(bool _useInterfaceMetadata) public onlyOwner() {
        useInterfaceMetadata = _useInterfaceMetadata;
    }


    //
    //single metadata
    //

    bool public useSingleMetadata = false;
    string public imageURI;
    string public metadataTitle;
    string public metadataDescription;
    string public metadataAttributes;

    //single image metadata
    function setUseSingleMetadata(bool _useSingleMetadata) public onlyOwner() {
        useSingleMetadata = _useSingleMetadata;
    }
    function setMetadataTitle(string memory _metadataTitle) public onlyOwner {
        metadataTitle = _metadataTitle;
    }
    function setMetadataDescription(string memory _metadataDescription) public onlyOwner {
        metadataDescription = _metadataDescription;
    }
    function setMetadataAttributes(string memory _metadataAttributes) public onlyOwner {
        metadataAttributes = _metadataAttributes;
    }
    function setImageURI(string memory _newImageURI) public onlyOwner {
        imageURI = _newImageURI;
    }

    //
    //token URI
    //

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (useInterfaceMetadata == true) {
            return interfaceOfTokenURI.tokenURI(tokenId);
        }
        if(useSingleMetadata == true){
            return string( abi.encodePacked( 'data:application/json;base64,' , Base64.encode(
                abi.encodePacked(
                    '{'
                        '"name":"' , metadataTitle ,'",' ,
                        '"description":"' , metadataDescription ,  '",' ,
                        '"image": "' , imageURI , '",' ,
                        '"attributes":[{"trait_type":"type","value":"' , metadataAttributes , '"}]',
                    '}'
                )
            ) ) );
        }
        return string(abi.encodePacked(ERC721A.tokenURI(1), baseExtension));
    }



    //
    //viewer section
    //

    function tokensOfOwner(address owner) public view returns (uint256[] memory) {
        unchecked {
            uint256 tokenIdsIdx;
            address currOwnershipAddr;
            uint256 tokenIdsLength = balanceOf(owner);
            uint256[] memory tokenIds = new uint256[](tokenIdsLength);
            TokenOwnership memory ownership;
            for (uint256 i = _startTokenId(); tokenIdsIdx != tokenIdsLength; ++i) {
                ownership = _ownershipAt(i);
                if (ownership.burned) {
                    continue;
                }
                if (ownership.addr != address(0)) {
                    currOwnershipAddr = ownership.addr;
                }
                if (currOwnershipAddr == owner) {
                    tokenIds[tokenIdsIdx++] = i;
                }
            }
            return tokenIds;
        }
    }







    //
    //sbt section
    //

    bool public isSBT = false;

    function setIsSBT(bool _state) public onlyOwner {
        isSBT = _state;
    }

    function _beforeTokenTransfers( address from, address to, uint256 startTokenId, uint256 quantity) internal virtual override{
        require( isSBT == false || from == address(0) || to == address(0x000000000000000000000000000000000000dEaD), "transfer is prohibited");
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
    }

    function setApprovalForAll(address operator, bool approved) public virtual override {
        require( isSBT == false , "setApprovalForAll is prohibited");
        super.setApprovalForAll(operator, approved);
    }

    function approve(address to, uint256 tokenId) public payable virtual override {
        require( isSBT == false , "approve is prohibited");
        super.approve(to, tokenId);
    }


    //
    //override
    //

    function supportsInterface(bytes4 interfaceId) public view override(ERC721A , AccessControl) returns (bool) {
        return 
            ERC721A.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }


}
