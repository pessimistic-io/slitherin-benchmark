// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Supported1Token} from "./Supported1Token.sol";

contract Supported2Tokens is Supported1Token {
    address immutable _supportedToken2;

    constructor(
        address supportedToken1_,
        address supportedToken2_
    ) Supported1Token(supportedToken1_) {
        _supportedToken2 = supportedToken2_;
    }

    function _isTokenSupported(
        address token
    ) internal view virtual override returns (bool) {
        return token == _supportedToken2 || super._isTokenSupported(token);
    }
}

