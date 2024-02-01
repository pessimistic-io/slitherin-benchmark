// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./contracts-exposed_OSB721.sol";

contract $OSB721 is OSB721 {
    constructor() {}

    function $_beforeTokenTransfer(address from,address to,uint256 tokenId) external {
        return super._beforeTokenTransfer(from,to,tokenId);
    }

    function $__Ownable_init() external {
        return super.__Ownable_init();
    }

    function $__Ownable_init_unchained() external {
        return super.__Ownable_init_unchained();
    }

    function $_transferOwnership(address newOwner) external {
        return super._transferOwnership(newOwner);
    }

    function $__ERC2981_init() external {
        return super.__ERC2981_init();
    }

    function $__ERC2981_init_unchained() external {
        return super.__ERC2981_init_unchained();
    }

    function $_feeDenominator() external pure returns (uint96) {
        return super._feeDenominator();
    }

    function $_setDefaultRoyalty(address receiver,uint96 feeNumerator) external {
        return super._setDefaultRoyalty(receiver,feeNumerator);
    }

    function $_deleteDefaultRoyalty() external {
        return super._deleteDefaultRoyalty();
    }

    function $_setTokenRoyalty(uint256 tokenId,address receiver,uint96 feeNumerator) external {
        return super._setTokenRoyalty(tokenId,receiver,feeNumerator);
    }

    function $_resetTokenRoyalty(uint256 tokenId) external {
        return super._resetTokenRoyalty(tokenId);
    }

    function $__ERC721Enumerable_init() external {
        return super.__ERC721Enumerable_init();
    }

    function $__ERC721Enumerable_init_unchained() external {
        return super.__ERC721Enumerable_init_unchained();
    }

    function $__ERC721_init(string calldata name_,string calldata symbol_) external {
        return super.__ERC721_init(name_,symbol_);
    }

    function $__ERC721_init_unchained(string calldata name_,string calldata symbol_) external {
        return super.__ERC721_init_unchained(name_,symbol_);
    }

    function $_baseURI() external view returns (string memory) {
        return super._baseURI();
    }

    function $_safeTransfer(address from,address to,uint256 tokenId,bytes calldata _data) external {
        return super._safeTransfer(from,to,tokenId,_data);
    }

    function $_exists(uint256 tokenId) external view returns (bool) {
        return super._exists(tokenId);
    }

    function $_isApprovedOrOwner(address spender,uint256 tokenId) external view returns (bool) {
        return super._isApprovedOrOwner(spender,tokenId);
    }

    function $_safeMint(address to,uint256 tokenId) external {
        return super._safeMint(to,tokenId);
    }

    function $_safeMint(address to,uint256 tokenId,bytes calldata _data) external {
        return super._safeMint(to,tokenId,_data);
    }

    function $_mint(address to,uint256 tokenId) external {
        return super._mint(to,tokenId);
    }

    function $_burn(uint256 tokenId) external {
        return super._burn(tokenId);
    }

    function $_transfer(address from,address to,uint256 tokenId) external {
        return super._transfer(from,to,tokenId);
    }

    function $_approve(address to,uint256 tokenId) external {
        return super._approve(to,tokenId);
    }

    function $_setApprovalForAll(address owner,address operator,bool approved) external {
        return super._setApprovalForAll(owner,operator,approved);
    }

    function $_afterTokenTransfer(address from,address to,uint256 tokenId) external {
        return super._afterTokenTransfer(from,to,tokenId);
    }

    function $__ERC165_init() external {
        return super.__ERC165_init();
    }

    function $__ERC165_init_unchained() external {
        return super.__ERC165_init_unchained();
    }

    function $__Context_init() external {
        return super.__Context_init();
    }

    function $__Context_init_unchained() external {
        return super.__Context_init_unchained();
    }

    function $_msgSender() external view returns (address) {
        return super._msgSender();
    }

    function $_msgData() external view returns (bytes memory) {
        return super._msgData();
    }
}

