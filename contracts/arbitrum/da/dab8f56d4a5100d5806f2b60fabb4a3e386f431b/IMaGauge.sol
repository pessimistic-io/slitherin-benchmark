// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMaGauge {
    function depositAll() external returns (uint _tokenId);

    function deposit(uint256 amount) external returns (uint _tokenId);

    function withdrawAndHarvest(uint _tokenId) external;

    function getAllReward() external;

    function getReward(uint _tokenId) external;

    // returns balanceOf nft
    function balanceOf(address account) external view returns (uint256);

    function balanceOfToken(uint _tokenId) external view returns (uint256);

    function earned(uint _tokenId) external view returns (uint256);

    function earned(address account) external view returns (uint256);
}

interface ImaNFT {
    function balanceOf(address account) external view returns (uint256);
}

