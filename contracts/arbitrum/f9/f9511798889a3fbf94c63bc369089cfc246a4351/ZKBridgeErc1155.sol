// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC1155URIStorage.sol";
import "./Ownable.sol";
import "./BaseZKBridgeErc1155.sol";


contract ZKBridgeErc1155 is BaseZKBridgeErc1155, Ownable {
    constructor() BaseZKBridgeErc1155("", msg.sender, false) {

    }
}
