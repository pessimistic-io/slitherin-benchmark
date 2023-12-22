//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISSOV} from "./ISSOV.sol";

interface INativeSSOV is ISSOV {
    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external payable returns (uint256, uint256);

    function deposit(uint256 strikeIndex, address user)
        external
        payable
        returns (bool);

    function depositMultiple(
        uint256[] memory strikeIndices,
        uint256[] memory amounts,
        address user
    ) external payable returns (bool);
}

