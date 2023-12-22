// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IERC1155 } from "./IERC1155.sol";

interface IERC1155Supply is IERC1155 {
    function totalSupply(uint256 id) external view returns (uint256);
}

