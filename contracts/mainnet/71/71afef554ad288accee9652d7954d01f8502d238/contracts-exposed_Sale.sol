// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./contracts-exposed_Sale.sol";

contract $Sale is Sale {
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

    function $__ERC1155Holder_init() external {
        return super.__ERC1155Holder_init();
    }

    function $__ERC1155Holder_init_unchained() external {
        return super.__ERC1155Holder_init_unchained();
    }

    function $__ERC1155Receiver_init() external {
        return super.__ERC1155Receiver_init();
    }

    function $__ERC1155Receiver_init_unchained() external {
        return super.__ERC1155Receiver_init_unchained();
    }

    function $__ERC165_init() external {
        return super.__ERC165_init();
    }

    function $__ERC165_init_unchained() external {
        return super.__ERC165_init_unchained();
    }

    function $__ERC721Holder_init() external {
        return super.__ERC721Holder_init();
    }

    function $__ERC721Holder_init_unchained() external {
        return super.__ERC721Holder_init_unchained();
    }

    function $__ReentrancyGuard_init() external {
        return super.__ReentrancyGuard_init();
    }

    function $__ReentrancyGuard_init_unchained() external {
        return super.__ReentrancyGuard_init_unchained();
    }
}

