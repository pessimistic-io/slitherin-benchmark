//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721.sol";

contract ERC721Batch {

    function batchSafeTransferFrom(address _collectionAddress, address _to, uint256[] calldata _tokenIds) external {
        require(_collectionAddress != address(0), "ERC721Batch: Bad collection address");
        require(_to != address(0), "ERC721Batch: Bad to address");
        require(msg.sender != _to, "ERC721Batch: Cannot send tokens to yourself");
        require(_tokenIds.length > 0, "ERC721Batch: No token ids given");

        IERC721 _collection = IERC721(_collectionAddress);

        for(uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];

            _collection.safeTransferFrom(msg.sender, _to, _tokenId);
        }
    }
}
