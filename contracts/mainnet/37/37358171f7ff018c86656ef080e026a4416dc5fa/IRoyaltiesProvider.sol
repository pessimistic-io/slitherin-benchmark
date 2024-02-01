// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./LibPart.sol";

interface IRoyaltiesProvider {
    function getRoyalties(address token, uint256 tokenId) external returns (LibPart.Part[] memory);
}

