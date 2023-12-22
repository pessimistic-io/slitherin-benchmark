// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;

interface IUniversalReceiver {
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data) external returns (bytes4);
    function onERC1155BatchReceived(address operator, address from, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external returns (bytes4); 
}

abstract contract UniversalReceiver is IUniversalReceiver {
    receive() external payable {}
    fallback() external payable {}

    function supportsInterface(bytes4 interfaceID) public pure override returns (bool) {
        return interfaceID != 0xffffffff;
    }

    function onERC721Received(address, address, uint256, bytes calldata) public pure override returns (bytes4) {
        return IUniversalReceiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) public pure override returns (bytes4) {
        return IUniversalReceiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) public pure override returns (bytes4) {
        return IUniversalReceiver.onERC1155BatchReceived.selector;
    }
}

