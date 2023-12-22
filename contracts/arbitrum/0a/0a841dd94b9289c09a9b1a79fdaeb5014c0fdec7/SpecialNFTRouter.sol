// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;
import "./ISpecialNFT.sol";

contract SpecialNFTRouter {
    ISpecialNFT token;

    constructor(address _tokenAddress) {
        token = ISpecialNFT(_tokenAddress);
    }

    function getAllBalance(address owner) external view returns (uint256[] memory, uint256[] memory) {
        uint256 balance = token.balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256[] memory tokenTypes = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = token.tokenOfOwnerByIndex(owner, i);
            tokenTypes[i] = token.getSpecialNFTType(tokenIds[i]);
        }
        return (tokenIds, tokenTypes);
    }

    function getBalanceOf(address owner, uint256 typeId) external view returns (uint256[] memory) {
        uint256 balance = token.balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 count = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = token.tokenOfOwnerByIndex(owner, i);
            uint256 tokenType = token.getSpecialNFTType(tokenId);
            if (tokenType == typeId) {
                tokenIds[count] = tokenId;
                count++;
            }
        }
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tokenIds[i];
        }
        return (result);
    }
}

