// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {SupportedTokens} from "./SupportedTokens.sol";

contract Supported1Token is SupportedTokens {
    address private immutable _supportedToken1;

    constructor(address supportedToken1_) {
        _supportedToken1 = supportedToken1_;
    }

    function _isTokenSupported(
        address token
    ) internal view override returns (bool) {
        return token == _supportedToken1;
    }

    function _supportedTokens()
        internal
        view
        override
        returns (address[] memory t)
    {
        t = new address[](1);
        t[0] = _supportedToken1;
    }
}

