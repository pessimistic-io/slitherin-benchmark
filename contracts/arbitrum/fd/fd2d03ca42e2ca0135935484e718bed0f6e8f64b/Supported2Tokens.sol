// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {SupportedTokens} from "./SupportedTokens.sol";

contract Supported2Tokens is SupportedTokens {
    address private immutable _supportedToken1;
    address private immutable _supportedToken2;

    constructor(address supportedToken1_, address supportedToken2_) {
        _supportedToken1 = supportedToken1_;
        _supportedToken2 = supportedToken2_;
    }

    function _isTokenSupported(
        address token
    ) internal view override returns (bool) {
        return token == _supportedToken1 || token == _supportedToken2;
    }

    function _supportedTokens()
        internal
        view
        override
        returns (address[] memory t)
    {
        t = new address[](2);
        t[0] = _supportedToken1;
        t[1] = _supportedToken2;
    }
}

