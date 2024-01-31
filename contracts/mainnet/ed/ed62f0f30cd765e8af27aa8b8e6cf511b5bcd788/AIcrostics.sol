// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721Psi.sol";
import "./ERC721PsiBurnable.sol";
import {Ownable} from "./Ownable.sol";
import {OperatorFilterer} from "./OperatorFilterer.sol";

contract AIcrostics is ERC721Psi, ERC721PsiBurnable, OperatorFilterer, Ownable {
    uint256 public MINT_PRICE = 0.003 ether;
    uint256 public MAX_SUPPLY = 9999;
    uint256 public MAX_MINT_PER_WALLET = 5;

    mapping(address => uint256) private _tokensMinted;
    mapping(uint256 => uint256[]) private _tokenHalves;

    bool public operatorFilteringEnabled;

    bool _mintEnabled = false;
    bool _mergeEnabled = false;
    bool _uriIsSealed = false;

    constructor() ERC721Psi() {
        _registerForOperatorFiltering();
        operatorFilteringEnabled = true;
        _setDefaultRoyalty(msg.sender, 500);
        _safeMint(msg.sender, 10);
    }

    function mint(uint256 _amount) external payable {
        uint256 tokensMinted = _tokensMinted[msg.sender];
        uint256 price = (MINT_PRICE * _amount) -
            (tokensMinted < 1 ? 0.003 ether : 0);
        require(_mintEnabled == true, "AIcrostics: Mint disabled.");
        require(
            tokensMinted + _amount <= MAX_MINT_PER_WALLET,
            "AIcrostics: Minting more than allowed per wallet"
        );
        require(
            (_currentIndex - 1) + _amount <= MAX_SUPPLY,
            "AIcrostics: Max supply exceeded"
        );
        require(price <= msg.value, "AIcrostics: Not enough ETH sent");

        _safeMint(msg.sender, _amount);
        _tokensMinted[msg.sender] += _amount;
    }

    function merge(uint256 tokenId1, uint256 tokendId2) external {
        require(_mintEnabled == false, "AIcrostics: Mint still ongoing.");
        require(_mergeEnabled == true, "AIcrostics: Merge not enabled.");
        require(tokenId1 < _secondEdStartTokenId && tokendId2 < _secondEdStartTokenId, "AIcrostics: Trying to merge an 8-line poem.");
        require(
            ownerOf(tokenId1) == msg.sender,
            "AIcrostics: You do not own the first token"
        );

        require(
            ownerOf(tokendId2) == msg.sender,
            "AIcrostics: You do not own the second token"
        );
        _burn(tokenId1);
        _burn(tokendId2);
        _safeMint(msg.sender, 1);
        _tokenHalves[_nextTokenId()] = [tokenId1, tokendId2];
    }

    function enableMint() public onlyOwner {
        _mintEnabled = true;
    }

    function disableMint() public onlyOwner {
        _mintEnabled = false;
    }

    function enableMerge() public onlyOwner {
        _mergeEnabled = true;
    }

    function disableMerge() public onlyOwner {
        _mergeEnabled = false;
    }

    function setSecondEdStartTokenId() public onlyOwner {
        _secondEdStartTokenId = _nextTokenId();
    }

    function setFirstEdBaseURI(string memory baseURI) public onlyOwner {
        require(_uriIsSealed == false, "Base URI can no longer be changed.");
        _firstEdBaseURI = baseURI;
    }

    function setSecondEdBaseURI(string memory baseURI) public onlyOwner {
        require(_uriIsSealed == false, "Base URI can no longer be changed.");
        _secondEdBaseURI = baseURI;
    }

    function sealUri() public onlyOwner {
        _uriIsSealed = true;
    }

    function updateCollectionMetadata() public onlyOwner {
        emit BatchMetadataUpdate(1, totalSupply());
    }

    function withdraw() public onlyOwner {
        require(address(this).balance > 0, "Balance is zero.");
        payable(owner()).transfer(address(this).balance);
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function tokensMintedByAddress(address minter)
        public
        view
        returns (uint256)
    {
        return _tokensMinted[minter];
    }

    function tokenHalves(uint256 tokenId)
        public
        view
        returns (uint256[] memory)
    {
        return _tokenHalves[tokenId];
    }

    function uriIsSealed() public view returns (bool) {
        return _uriIsSealed;
    }

    function totalSupply()
        public
        view
        override(ERC721Psi, ERC721PsiBurnable)
        returns (uint256)
    {
        return super.totalSupply();
    }

    function _exists(uint256 tokenId)
        internal
        view
        override(ERC721Psi, ERC721PsiBurnable)
        returns (bool)
    {
        return super._exists(tokenId);
    }

    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function setOperatorFilteringEnabled(bool value) public onlyOwner {
        operatorFilteringEnabled = value;
    }

    function _operatorFilteringEnabled() internal view override returns (bool) {
        return operatorFilteringEnabled;
    }

    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
}

