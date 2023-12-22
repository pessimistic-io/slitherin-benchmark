// SPDX-License-Identifier: MIT
// Derivable Contracts (token/ERC1155/IERC1155Supply.sol)

pragma solidity 0.8.20;

import "./IERC1155.sol";

interface IERC1155Supply is IERC1155 {
    /**
     * @dev Total amount of tokens in with a given id.
     */
    function totalSupply(uint256 id) external view returns (uint256);
}

