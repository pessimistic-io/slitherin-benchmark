// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Strings.sol";
import "./Ownable.sol";
import "./ERC2981.sol";
import "./ERC721URIStorage.sol";
import "./Counters.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";
import "./NFTProxy.sol";
import "./MerkleProof.sol";
import "./console.sol";

contract Arbkeys is ERC721URIStorage, ERC2981, Ownable, ReentrancyGuard, Pausable, NFTProxy, DefaultOperatorFilterer {
    using Strings for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    string private _baseUri = "";
    string private _baseExtension = ".json";
    uint16 private _freeMintMaxBalance = 1;
    uint16 private _preMintMaxBalance = 10;
    uint16 private _totalSupply = 4_444;
    uint16 private _newAssignedId = 0;
    uint40 private _freeSaleTime = 1_681_488_000;
    uint40 private _preSaleTime = 1_681_574_400; // Date.UTC(2022, 2, 15, 0, 0, 0) / 1000 | 2022.3.15 UTC
    uint40 private _publicSaleTime = 1_681_660_800; // Date.UTC(2022, 2, 31, 0, 0, 0) / 1000 | 2022.3.31 UTC
    uint64 private _preCost = 0.008 ether; // uint64 (0 ~ 18,446,744,073,709,551,615)
    uint64 private _pubCost = 0.012 ether; // uint64 (0 ~ 18,446,744,073,709,551,615)
    bytes32 private _freeMerkleRoot;
    bytes32 private _preMerkleRoot;
    mapping(address => uint16) private _freeMintBalances;
    mapping(address => uint16) private _preMintBalances;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory baseUri_
    ) ERC721(name_, symbol_) {
        require(bytes(baseUri_).length > 0, "NftMint: cannot empty string");
        _baseUri = baseUri_;
        _setDefaultRoyalty(msg.sender, 500);
    }

    function supportsInterface(bytes4 interfaceId)
    public view virtual override(ERC721, ERC2981)
    returns (bool) {
      return super.supportsInterface(interfaceId);
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function burnNFT(uint256 tokenId)
        public onlyOwner {
        _burn(tokenId);
    }

    function mint(uint8 mintAmount_, address recipient) internal {
        for (uint8 i = 1; i <= mintAmount_; i ++) {
            _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();
            _safeMint(recipient, newItemId);
        }
        require(_tokenIds.current() <= _totalSupply, "NftMint: Total NFTs are sold out");
    }

    function teamMint(uint8 mintAmount_) external onlyOwner nonReentrant payable {
        mint(mintAmount_, _msgSender());
    }

    function freeMint(uint8 mintAmount_, bytes32[] calldata proof_) external nonReentrant payable {
        require(block.timestamp < _preSaleTime && block.timestamp >= _freeSaleTime, "NftMint: not ready to free mint");
        require(MerkleProof.verify(proof_, _freeMerkleRoot, MerkleProof._leaf(_msgSender())), "NftMint: address is not on whitelist");
        mint(mintAmount_, _msgSender());
        _freeMintBalances[_msgSender()] += mintAmount_;
        require(_freeMintBalances[_msgSender()] <= _freeMintMaxBalance, string(abi.encodePacked("NftMint: Cannot own more than ", _freeMintMaxBalance, " NFTs")));
    }

    function preMint(uint8 mintAmount_, bytes32[] calldata proof_) external nonReentrant payable {
        require(block.timestamp < _publicSaleTime && block.timestamp >= _preSaleTime, "NftMint: not ready to pre mint");
        require(msg.value == _preCost * mintAmount_, "NftMint: payment is not enough");
        require(MerkleProof.verify(proof_, _preMerkleRoot, MerkleProof._leaf(_msgSender())), "NftMint: address is not on whitelist");
        mint(mintAmount_, msg.sender);
        _preMintBalances[_msgSender()] += mintAmount_;
        require(_preMintBalances[_msgSender()] <= _preMintMaxBalance, string(abi.encodePacked("NftMint: Cannot own more than ", _preMintMaxBalance, " NFTs")));
    }

    function publicMint(uint8 mintAmount_) external nonReentrant payable {
        require(block.timestamp >= _publicSaleTime, "NftMint: not ready to public mint");
        require(msg.value == _pubCost * mintAmount_, "NftMint: payment is not enough");
        mint(mintAmount_, _msgSender());
    }

    function freeMintMaxBalance() external view returns (uint16) {
        return _freeMintMaxBalance;
    }

    function preMintMaxBalance() external view returns (uint16) {
        return _preMintMaxBalance;
    }

    function totalSupply() external view returns (uint16) {
        return _totalSupply;
    }

    function currentSupply() external view returns (uint256) {
        return _tokenIds.current();
    }

    function newAssignedId() external view returns (uint16) {
        require(_newAssignedId != 0, "NftMint: not set the provenance id");
        return _newAssignedId;
    }

    function freeSaleTime() external view returns (uint40) {
        return _freeSaleTime;
    }

    function preSaleTime() external view returns (uint40) {
        return _preSaleTime;
    }

    function publicSaleTime() external view returns (uint40) {
        return _publicSaleTime;
    }

    function cost() external view returns (uint64, uint64) {
        return (_preCost, _pubCost);
    }

    function freeMintBalances(address addr) external view returns (uint16) {
        return _freeMintBalances[addr];
    }

    function preMintBalances(address addr) external view returns (uint16) {
        return _preMintBalances[addr];
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        uint256 assignedTokenId = (tokenId + uint256(_newAssignedId) -1) % _totalSupply + 1;

        return bytes(_baseUri).length > 0 ? string(abi.encodePacked(_baseUri, assignedTokenId.toString(), _baseExtension)) : "";
    }

    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public onlyApprovedMarketplace onlyAllowedOperator(from) virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public onlyApprovedMarketplace onlyAllowedOperator(from) virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function getBaseUri() external onlyOwner view returns (string memory) {
        return _baseUri;
    }

    function setBaseUri(string memory baseUri_) external onlyOwner {
        require(bytes(baseUri_).length > 0, "NftMint: cannot empty string");
        _baseUri = baseUri_;
    }

    function getBaseExtension() external onlyOwner view returns (string memory) {
        return _baseExtension;
    }
    
    function setBaseExtension(string memory baseExtension_) external onlyOwner {
        require(bytes(baseExtension_).length > 0, "NftMint: cannot empty string");
        _baseExtension = baseExtension_;
    }

    function setFreeSaleTime(uint40 freeSaleTime_) external onlyOwner {
        _freeSaleTime = freeSaleTime_;
    }

    function setPreSaleTime(uint40 preSaleTime_) external onlyOwner {
        _preSaleTime = preSaleTime_;
    }

    function setPublicSaleTime(uint40 publicSaleTime_) external onlyOwner {
        _publicSaleTime = publicSaleTime_;
    }

    function setCost(uint64 preCost_, uint64 pubCost_) external onlyOwner {
        _preCost = preCost_;
        _pubCost = pubCost_;
    }

    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    function setNewAssignedId() external onlyOwner {
        require(_newAssignedId == 0, "NftMint: provenance id is already set");
        _newAssignedId = uint16(uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp, _msgSender()))) % _totalSupply);
    }

    function setFreeMintMaxBalance(uint8 freeMintMaxBalance_) external onlyOwner {
        require(freeMintMaxBalance_ > 0, "NftMint: cannot set as zero");
        _freeMintMaxBalance = freeMintMaxBalance_;
    }

    function setPreMintMaxBalance(uint8 preMintMaxBalance_) external onlyOwner {
        require(preMintMaxBalance_ > 0, "NftMint: cannot set as zero");
        _preMintMaxBalance = preMintMaxBalance_;
    }

    function getFreeMerkleRoot() external view onlyOwner returns (bytes32) {
        return _freeMerkleRoot;
    }
    function setFreeMerkleRoot(bytes32 freeMerkleRoot_) external onlyOwner {
        _freeMerkleRoot = freeMerkleRoot_;
    }
    function getPreMerkleRoot() external view onlyOwner returns (bytes32) {
        return _preMerkleRoot;
    }
    function setPreMerkleRoot(bytes32 preMerkleRoot_) external onlyOwner {
        _preMerkleRoot = preMerkleRoot_;
    }

    function balance() external view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    function withdraw() external onlyOwner {
        require(payable(_msgSender()).send(address(this).balance));
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        require(!paused(), "ERC721Pausable: token transfer while paused");
    }
}
