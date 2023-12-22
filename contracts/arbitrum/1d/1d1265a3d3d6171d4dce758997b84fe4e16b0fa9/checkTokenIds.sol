//SPDX-License-Identifier: MIT
pragma solidity >= 0.8.16;

import "./IERC721.sol";

contract CheckTokenIds {
    IERC721 public immutable nftContract;


    constructor(
        IERC721 _nftAddress
    ) {
        require(address(_nftAddress) != address(0), "Zero nft address");

        nftContract = _nftAddress;
    }

    function _checkTokenIds() public view returns (uint256[] memory) {
        uint256 amount = nftContract.balanceOf(msg.sender);
        uint256[] memory tokenIds;
        uint256 index = 0;
        for(uint256 i = 1; i < 48001; i++) {
            require(index < amount, "Retrieved all tokenIds");
            if(msg.sender == nftContract.ownerOf(i)) {
                tokenIds[index] = i;
                index += 1;
            }
        } 
        return tokenIds;
    }
}
