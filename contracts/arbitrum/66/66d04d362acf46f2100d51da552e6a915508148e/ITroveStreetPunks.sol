// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ITroveStreetPunks {

    function transferFrom(address _from, address _to, uint256 _tokenId) external;

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external;

    function walletOfOwner(address _address) external view returns (uint256[] memory);

    function tokenURI(uint256 _tokenId) external view returns (string memory);

    function totalSupply() external view returns (uint256);
    
}
