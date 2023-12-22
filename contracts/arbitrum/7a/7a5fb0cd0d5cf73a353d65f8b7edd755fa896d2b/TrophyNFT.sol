// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC721.sol";
import "./Ownable.sol";
import "./ECDSA.sol";
import "./MessageHashUtils.sol";
import "./Strings.sol";
import "./RecoverMessage.sol";

contract TrophyNFT is ERC721, Ownable {
    event NFTMinted(address indexed newOwner, string categoryId, uint256 tokenId, string tokenURI);

    struct NFTCategory {
        string categoryId;
        uint256 maxSupply;
        uint256 mintedSupply;
        string metadataURI;
    }

    struct NFTVoucher {
        string categoryId;
        bytes signature;
    }


    RecoverMessage private recoverMessage;
    mapping(string => NFTCategory) public categories;
    string[] private categoryIds;
    mapping(uint256 => string) private tokenIdToCategoryId;
    uint256 private nextTokenId = 1;
    address private signer; // Address used to sign vouchers

    constructor(address initialOwner, string memory _name, string memory _symbol, address _signer)
    Ownable(initialOwner) ERC721(_name, _symbol) {
        signer = _signer;
        recoverMessage = new RecoverMessage();
    }

    function createCategory(string memory id, uint256 maxSupply, string memory metadataURI) public onlyOwner {
        require(bytes(categories[id].categoryId).length == 0, "Category already exists");

        categories[id] = NFTCategory(id, maxSupply, 0, metadataURI);
        categoryIds.push(id);
    }

    function claimNFT(NFTVoucher calldata voucher) public {
        _verify(voucher);

        NFTCategory storage category = categories[voucher.categoryId];
        require(category.mintedSupply < category.maxSupply, "Max supply reached for this category");

        category.mintedSupply++;
        uint256 newTokenId = nextTokenId++;
        _safeMint(msg.sender, newTokenId);
        tokenIdToCategoryId[newTokenId] = voucher.categoryId;

        emit NFTMinted(msg.sender, voucher.categoryId, newTokenId, this.tokenURI(newTokenId));
    }

    function _verify(NFTVoucher calldata voucher) internal view {
        string memory rawStr = recoverMessage.concatAddressAndString(msg.sender, voucher.categoryId);
        bytes32 messageHash = keccak256(abi.encodePacked(rawStr));
        string memory converted = string(abi.encodePacked(messageHash));

        require(signer == recoverMessage.recoverStringFromRaw(converted, voucher.signature), "Invalid signature");
    }

    function getRemainingSupply(string memory categoryId) public view returns (uint256) {
        require(bytes(categoryId).length > 0, "Category does not exist");

        NFTCategory storage category = categories[categoryId];

        require(bytes(category.categoryId).length > 0, "Category does not exist");

        return category.maxSupply - category.mintedSupply;
    }

    function getAllCategories() public view returns (NFTCategory[] memory) {
        NFTCategory[] memory allCategories = new NFTCategory[](categoryIds.length);
        for (uint256 i = 0; i < categoryIds.length; i++) {
            allCategories[i] = categories[categoryIds[i]];
        }
        return allCategories;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory categoryId = tokenIdToCategoryId[tokenId];
        require(bytes(categoryId).length > 0, "Invalid tokenId");
        return categories[categoryId].metadataURI;
    }

    // Override transferFrom and safeTransferFrom to prevent NFT transfers
    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(from == address(this), "Trophy NFTs are non-transferable!");
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override {
        require(from == address(this), "Trophy NFTs are non-transferable!");
        super.safeTransferFrom(from, to, tokenId, _data);
    }
}

