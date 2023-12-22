// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Ownable.sol";
import "./Strings.sol";
import "./ERC721A.sol";
import "./DefaultOperatorFilterer.sol";


contract Skyscraper is ERC721A, Ownable, DefaultOperatorFilterer {

    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    string public baseUri;
    string public unrevealedUri;

    uint256 public constant MAX_SUPPLY = 2500;

    uint256 public maxPerTx = 30;

    uint256 public cost = 0.01 ether;

    bool private paused = true;
    bool public revealed = false;

    modifier notPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor() ERC721A("Skyscraper", "SKY") {

    }

    function mint(uint256 amount) public payable notPaused {
        require(amount > 0, "Non zero");
        require(amount <= maxPerTx, "Max per tx");
        require(_totalMinted() + amount <= MAX_SUPPLY, "Too many");
        require(msg.value >= cost * amount, "Not enough eth");

        _mint(msg.sender, amount);
    }

    function adminMint(uint256 amount) public onlyOwner {
        require(amount <= maxPerTx, "Max per tx");
        require(_totalMinted() + amount <= MAX_SUPPLY, "Too many");

        _mint(msg.sender, amount);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if(!revealed) return unrevealedUri;

        return string(abi.encodePacked(baseUri, Strings.toString(tokenId), ".json"));
    }

    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override payable onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override payable onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override payable onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        payable
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function setCost(uint256 _cost) public onlyOwner {
        cost = _cost;
    }

    function setBaseURI(string memory _baseUri) public onlyOwner {
        baseUri = _baseUri;
    }

    function setUnrevealedURI(string memory _unrevealedUri) public onlyOwner {
        unrevealedUri = _unrevealedUri;
    }

    function setPaused(bool _paused) public onlyOwner {
        paused = _paused;
    }

    function setMaxPerTx(uint256 _maxPerTx) public onlyOwner {
        maxPerTx = _maxPerTx;
    }

    function reveal() public onlyOwner {
        revealed = true;

        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
	}

}

