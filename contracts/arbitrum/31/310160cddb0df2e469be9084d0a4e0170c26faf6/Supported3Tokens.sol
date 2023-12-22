// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {SupportedTokens} from "./SupportedTokens.sol";

contract Supported3Tokens is SupportedTokens {
    address private immutable T0;
    address private immutable T1;
    address private immutable T2;

    constructor(address t0, address t1, address t2) {
        T0 = t0;
        T1 = t1;
        T2 = t2;
    }

    function supportedTokens()
        public
        view
        override
        returns (address[] memory t)
    {
        t = new address[](3);
        t[0] = T0;
        t[1] = T1;
        t[2] = T2;
    }

    function _isTokenSupported(
        address token
    ) internal view override returns (bool isSupported) {
        return token == T0 || token == T1 || token == T2;
    }
}

