// SPDX-License-Identifier: MIT
// Derivable Contracts (token/ERC1155/IERC1155Maturity.sol)

pragma solidity 0.8.20;

import "./IERC1155Supply.sol";

interface IERC1155Maturity is IERC1155Supply {
    /**
     * @dev Returns the maturity time of tokens of token type `id` owned by `account`.
     *
     */
    function maturityOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {maturityOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function maturityOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
}

