// SPDX-License-Identifier: MIT
/*

███████████████████████████████████████████████████████████████████████████████████████
█░░░░░░██░░░░░░░░█░░░░░░░░░░█░░░░░░░░░░░░░░█░░░░░░░░░░░░░░█░░░░░░██░░░░░░░░█░░░░░░░░░░█
█░░▄▀░░██░░▄▀▄▀░░█░░▄▀▄▀▄▀░░█░░▄▀▄▀▄▀▄▀▄▀░░█░░▄▀▄▀▄▀▄▀▄▀░░█░░▄▀░░██░░▄▀▄▀░░█░░▄▀▄▀▄▀░░█
█░░▄▀░░██░░▄▀░░░░█░░░░▄▀░░░░█░░▄▀░░░░░░░░░░█░░▄▀░░░░░░░░░░█░░▄▀░░██░░▄▀░░░░█░░░░▄▀░░░░█
█░░▄▀░░██░░▄▀░░█████░░▄▀░░███░░▄▀░░█████████░░▄▀░░█████████░░▄▀░░██░░▄▀░░█████░░▄▀░░███
█░░▄▀░░░░░░▄▀░░█████░░▄▀░░███░░▄▀░░░░░░░░░░█░░▄▀░░░░░░░░░░█░░▄▀░░░░░░▄▀░░█████░░▄▀░░███
█░░▄▀▄▀▄▀▄▀▄▀░░█████░░▄▀░░███░░▄▀▄▀▄▀▄▀▄▀░░█░░▄▀▄▀▄▀▄▀▄▀░░█░░▄▀▄▀▄▀▄▀▄▀░░█████░░▄▀░░███
█░░▄▀░░░░░░▄▀░░█████░░▄▀░░███░░░░░░░░░░▄▀░░█░░▄▀░░░░░░░░░░█░░▄▀░░░░░░▄▀░░█████░░▄▀░░███
█░░▄▀░░██░░▄▀░░█████░░▄▀░░███████████░░▄▀░░█░░▄▀░░█████████░░▄▀░░██░░▄▀░░█████░░▄▀░░███
█░░▄▀░░██░░▄▀░░░░█░░░░▄▀░░░░█░░░░░░░░░░▄▀░░█░░▄▀░░░░░░░░░░█░░▄▀░░██░░▄▀░░░░█░░░░▄▀░░░░█
█░░▄▀░░██░░▄▀▄▀░░█░░▄▀▄▀▄▀░░█░░▄▀▄▀▄▀▄▀▄▀░░█░░▄▀▄▀▄▀▄▀▄▀░░█░░▄▀░░██░░▄▀▄▀░░█░░▄▀▄▀▄▀░░█
█░░░░░░██░░░░░░░░█░░░░░░░░░░█░░░░░░░░░░░░░░█░░░░░░░░░░░░░░█░░░░░░██░░░░░░░░█░░░░░░░░░░█
███████████████████████████████████████████████████████████████████████████████████████
*/

pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ERC2981.sol";
import "./DefaultOperatorFilterer.sol";
import "./ERC721A.sol";

error InsufficientFund();
error InvalidSaleState();
error NoBotMint();
error SoldOut();
error InvalidProof();
error InvalidMintAmount();
error LimitPerWalletExceeded();
error Failed();
error InvalidTokenID();

contract kiseki is 
    ERC721A, 
    Ownable, 
    ERC2981, 
    DefaultOperatorFilterer {
    uint public constant collectionSize = 1234; 
    string public constant ext = ".json";
    uint public mintPhase = 1;
    uint public revealStage = 1; //burn to reveal
    uint public freePerWallet = 1;
    uint public maxPerWallet = 2;
    bool public saleStart = false;
    uint public price = 0.03 ether;
    string public baseURI = "https://kisekijp.xyz/meta/";
    bytes32 public merkleRoot;

    constructor() ERC721A("Kiseki", "kskNFT") {
        setRoyaltyInfo(500);
        _mint(msg.sender, 1);
    }

    function tokenURI(uint _tokenId) public view override returns (string memory) {
        if(!_exists(_tokenId)) revert InvalidTokenID();
        return string(abi.encodePacked(baseURI,_toString(_tokenId),ext));
    }

    function saleState(bool val) external onlyOwner {
        saleStart = val;
    }

    function withdraw() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        if(!success) revert Failed();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721A, ERC2981) returns (bool) {
        // Supports the following `interfaceId`s:
        // - IERC165: 0x01ffc9a7
        // - IERC721: 0x80ac58cd
        // - IERC721Metadata: 0x5b5e139f
        // - IERC2981: 0x2a55205a
        return
            ERC721A.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId);
    }

    function airdrop(address _to, uint num) external onlyOwner {
        if(!(collectionSize >= _totalMinted() + num)) revert SoldOut();
        _mint(_to, num);
    }

    function verifyAddress(bytes32[] calldata _merkleProof) private 
    view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    function whitelistMint(uint quantity, bytes32[] calldata proof) external payable {
        if(!saleStart) revert InvalidSaleState();
        if(!verifyAddress(proof)) revert InvalidProof();
        if(tx.origin != msg.sender) revert NoBotMint();
        if(!(collectionSize >= _totalMinted() + quantity)) revert SoldOut();
        if(quantity == 0) revert InvalidMintAmount();
        if(_numberMinted(msg.sender) + quantity > maxPerWallet) revert LimitPerWalletExceeded();

        if(mintPhase == 0){
            if(_numberMinted(msg.sender) >= freePerWallet){
                if(msg.value < quantity * price) revert InsufficientFund();
            }else{
                uint counter = _numberMinted(msg.sender) + quantity;
                if(counter > freePerWallet){
                    if(msg.value < (counter - freePerWallet) * price) revert InsufficientFund();
                }   
            }
        }else{
            //paid mint
            if(msg.value < quantity * price) revert InsufficientFund();
        }

        _mint(msg.sender, quantity);
    }

    function _startTokenId() internal view virtual override returns (uint) {
        return 1;
    }

    function setUri(string calldata _uri) public onlyOwner {
        baseURI = _uri;
    }

    function setPrice(uint num) public onlyOwner {
        price = num;
    }

    function setReveal(uint num) public onlyOwner {
        revealStage = num;
    }

    function setMaxPerWallet(uint num) public onlyOwner {
        maxPerWallet = num;
    }

    function setRoyaltyInfo(uint96 perct) public onlyOwner {
        _setDefaultRoyalty(msg.sender, perct);
    }

    function setMerkleRoot(bytes32 merkleRootHash) external onlyOwner
    {
        merkleRoot = merkleRootHash;
    }

    function transferFrom(address from, address to, uint256 tokenId)
        public
        payable
        override
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }


    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        payable
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        payable
        override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}
