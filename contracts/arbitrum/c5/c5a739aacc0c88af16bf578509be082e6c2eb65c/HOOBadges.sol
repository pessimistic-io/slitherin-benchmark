// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./TransferlessERC1155.sol";

// Halls of Olympia Badge Tokens
contract HOOBadges is TransferlessERC1155 {
    string public constant name = "HOO Badges";
    string public constant symbol = "HOOB";

    constructor(
        address _gov,
        address[] memory _admins,
        string memory _uri
    ) TransferlessERC1155(_gov, _admins, _uri) {}
}

