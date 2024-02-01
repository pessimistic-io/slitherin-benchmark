// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./contracts-exposed_OSB1155.sol";

contract $OSB1155 is OSB1155 {
    constructor() {}

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

    function $__ERC1155_init(string calldata uri_) external {
        return super.__ERC1155_init(uri_);
    }

    function $__ERC1155_init_unchained(string calldata uri_) external {
        return super.__ERC1155_init_unchained(uri_);
    }

    function $_safeTransferFrom(address from,address to,uint256 id,uint256 amount,bytes calldata data) external {
        return super._safeTransferFrom(from,to,id,amount,data);
    }

    function $_safeBatchTransferFrom(address from,address to,uint256[] calldata ids,uint256[] calldata amounts,bytes calldata data) external {
        return super._safeBatchTransferFrom(from,to,ids,amounts,data);
    }

    function $_setURI(string calldata newuri) external {
        return super._setURI(newuri);
    }

    function $_mint(address to,uint256 id,uint256 amount,bytes calldata data) external {
        return super._mint(to,id,amount,data);
    }

    function $_mintBatch(address to,uint256[] calldata ids,uint256[] calldata amounts,bytes calldata data) external {
        return super._mintBatch(to,ids,amounts,data);
    }

    function $_burn(address from,uint256 id,uint256 amount) external {
        return super._burn(from,id,amount);
    }

    function $_burnBatch(address from,uint256[] calldata ids,uint256[] calldata amounts) external {
        return super._burnBatch(from,ids,amounts);
    }

    function $_setApprovalForAll(address owner,address operator,bool approved) external {
        return super._setApprovalForAll(owner,operator,approved);
    }

    function $_beforeTokenTransfer(address operator,address from,address to,uint256[] calldata ids,uint256[] calldata amounts,bytes calldata data) external {
        return super._beforeTokenTransfer(operator,from,to,ids,amounts,data);
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

