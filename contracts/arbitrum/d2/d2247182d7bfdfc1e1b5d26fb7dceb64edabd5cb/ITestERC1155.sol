// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC1155.sol";

interface ITestERC1155 is IERC1155 {
    function mint(
        uint256 amount,
        uint256 id,
        address receiver
    ) external;
}

