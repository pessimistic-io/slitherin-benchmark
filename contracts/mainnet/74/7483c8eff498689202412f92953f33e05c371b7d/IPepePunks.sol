// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC721.sol";

interface IPepePunks is IERC721{

    function mint(address to, uint256 id) external;

    function burn(uint256 tokenId) external;

    function tokensOfOwner(address _owner) external view returns(uint256[] memory);

    function totalSupply() external view returns (uint256);

}

