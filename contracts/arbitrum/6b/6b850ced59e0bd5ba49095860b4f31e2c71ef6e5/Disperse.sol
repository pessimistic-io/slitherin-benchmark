// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

interface IERC1155 {
    function mint(address to,uint256 id,uint256 amount) external;
}

contract Disperse is Ownable {
    function mintBatch(IERC1155 erc1155, TokenMintInfo[] calldata mints) external onlyOwner {
        uint256 length = mints.length;
        for(uint256 i = 0; i < length;) {
            TokenMintInfo calldata cur = mints[i];
            erc1155.mint(cur.recipient, cur.tokenId, cur.amt);
            unchecked { ++i; }
        }
    }
}

struct TokenMintInfo {
    address recipient;
    uint256 tokenId;
    uint256 amt;
}
