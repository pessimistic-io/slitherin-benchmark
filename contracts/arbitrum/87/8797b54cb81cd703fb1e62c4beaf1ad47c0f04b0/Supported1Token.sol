// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {SupportedTokens} from "./SupportedTokens.sol";

contract Supported1Token is SupportedTokens {
    address immutable _supportedToken1;

    constructor(address supportedToken1_) {
        _supportedToken1 = supportedToken1_;
    }

    function _isTokenSupported(
        address token
    ) internal view virtual override returns (bool) {
        return token == _supportedToken1;
    }
}

