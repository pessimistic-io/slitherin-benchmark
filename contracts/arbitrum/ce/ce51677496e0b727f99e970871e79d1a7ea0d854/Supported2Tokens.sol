// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SupportedTokens} from "./SupportedTokens.sol";

contract Supported2Tokens is SupportedTokens {
    address private immutable T0;
    address private immutable T1;

    constructor(address t0, address t1) {
        T0 = t0;
        T1 = t1;
    }

    function supportedTokens()
        public
        view
        override
        returns (address[] memory t)
    {
        t = new address[](2);
        t[0] = T0;
        t[1] = T1;
    }

    function _isTokenSupported(
        address token
    ) internal view override returns (bool isSupported) {
        return token == T0 || token == T1;
    }
}

