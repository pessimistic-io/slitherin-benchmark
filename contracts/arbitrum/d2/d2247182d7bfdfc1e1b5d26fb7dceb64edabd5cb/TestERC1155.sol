// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ITestERC1155.sol";
import "./ERC1155.sol";

contract TestERC1155 is ERC1155, ITestERC1155 {
    constructor() ERC1155("TestToken ERC1155") {}

    function mint(
        uint256 amount,
        uint256 id,
        address receiver
    ) public override {
        _mint(receiver, id, amount, "");
    }
}

