//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;


interface INFT {
    function ownerOf(uint256 tokenId) external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256 balance);
}

contract XenBoxHelper {
    /* ================ VIEW FUNCTIONS ================ */

    function getOwnedTokenIdList(
        address target,
        address owner,
        uint256 start,
        uint256 end
    ) external view returns (uint256[] memory tokenIdList) {
        require(start < end, "end must over start");
        INFT erc721 = INFT(target);
        uint256[] memory list = new uint256[](end - start);
        uint256 index;
        for (uint256 tokenId = start; tokenId < end; tokenId++) {
            if (erc721.ownerOf(tokenId) == owner) {
                list[index] = tokenId;
                index++;
            }
        }
        tokenIdList = new uint256[](index);
        for (uint256 i; i < index; i++) {
            tokenIdList[i] = list[i];
        }
    }

    /* ================ TRAN FUNCTIONS ================ */

    /* ================ ADMIN FUNCTIONS ================ */
}
