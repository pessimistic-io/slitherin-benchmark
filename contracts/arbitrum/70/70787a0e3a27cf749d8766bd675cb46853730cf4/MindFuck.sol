// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./$$$$$$____$_$_$$__$$$____$____$$.sol";

// This token is stupid, and serves no purpose other than to learn about how Ethereum uses Function Selectors. Don't use it, it's dumb.

contract MindFuck is $$$$$$____$_$_$$__$$$____$____$$("MindFuck", "$__", 18) {
    constructor(){
        _$(msg.sender, type(uint96).max);
    }
}
