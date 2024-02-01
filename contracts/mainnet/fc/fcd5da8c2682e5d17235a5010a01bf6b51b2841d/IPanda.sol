// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721_IERC721.sol";

interface IPanda is IERC721 {
    function safeMint(address to) external;
    function totalSupply() external view returns(uint256);
}



