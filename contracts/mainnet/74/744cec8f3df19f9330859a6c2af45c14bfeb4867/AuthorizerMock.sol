// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Authorizer.sol";

contract AuthorizerMock is Authorizer {
    constructor() {
        _authorize(msg.sender, Authorizer.authorize.selector);
        _authorize(msg.sender, Authorizer.unauthorize.selector);
    }
}

