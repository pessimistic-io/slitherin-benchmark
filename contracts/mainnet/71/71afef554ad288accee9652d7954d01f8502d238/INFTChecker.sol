// SPDX-License-Identifier: MIT 
pragma solidity 0.8.16; 

interface INFTChecker { 
    function isERC1155(address nftAddress) external view returns (bool);
    function isERC721(address nftAddress) external view returns (bool);
    function isERC165(address nftAddress) external view returns (bool);
    function isNFT(address _contractAddr) external view returns (bool);
    function isImplementRoyalty(address nftAddress) external view returns (bool);
}
