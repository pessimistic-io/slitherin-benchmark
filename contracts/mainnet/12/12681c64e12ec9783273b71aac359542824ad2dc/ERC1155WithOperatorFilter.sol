// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155Base.sol";
import {DefaultOperatorFilterer} from "./DefaultOperatorFilterer.sol";

contract ERC1155WithOperatorFilterTarget is
    ERC1155Base,
    DefaultOperatorFilterer
{
    constructor(
        string memory _init_name,
        string memory _init_symbol,
        TargetInit memory params,
        bytes memory data
    ) ERC1155Base(_init_name, _init_symbol, params, data) {}

    function setApprovalForAll(address operator, bool approved)
        public
        override
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    function isApprovedForAll(address account, address operator)
        public
        view
        override
        onlyAllowedOperatorApproval(operator)
        returns (bool)
    {
        return super.isApprovedForAll(account, operator);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeBatchTransferFrom(from, to, tokenIds, amounts, data);
    }
}

