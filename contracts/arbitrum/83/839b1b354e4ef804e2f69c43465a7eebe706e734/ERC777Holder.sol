// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces_IERC777.sol";
import "./IERC777Recipient.sol";
import "./interfaces_IERC1820Registry.sol";

abstract contract ERC777Holder is IERC777Recipient {
    
    IERC1820Registry constant internal ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    
    constructor() {
        ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));
    }

    function _tokensReceived(IERC777 token, uint256 amount, bytes memory data) internal virtual;
    function _canReceive(address token) internal virtual {}

    function tokensReceived(
        address /*operator*/,
        address /*from*/,
        address /*to*/,
        uint256 amount,
        bytes calldata userData,
        bytes calldata /*operatorData*/
    ) external virtual override {
        _canReceive(msg.sender);
        _tokensReceived(IERC777(msg.sender), amount, userData);
    }

}



