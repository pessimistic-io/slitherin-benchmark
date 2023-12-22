// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPlayerCard {
    function ownerOf(uint256 id) external view returns (address owner);

    function idOf(address owner) external view returns (uint256 id);

    function balanceOf(address _owner) external view returns (uint256);

    function mint() external returns (uint256);

    function mint(address to) external returns (uint256);

    function ownerData(uint256 id) external view returns (bytes memory);

    function updateOwnerData(address owner, bytes memory data) external;
}

