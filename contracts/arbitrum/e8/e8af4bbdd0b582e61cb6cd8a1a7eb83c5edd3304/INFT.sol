//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INFT {
    function destroy() external;

    function setOwner(address _newOwner) external;
    function setBaseURI(string memory _newBaseURI) external;

    function mintNFT(uint256 tokenId, address receiver) external returns (uint256);

    function burn(uint256 tokenId) external;

    function updateMintEndTime(uint256 _mintEndTime) external;
    function updateMaxMintAmount(uint256 _maxMintAmount) external;
}

