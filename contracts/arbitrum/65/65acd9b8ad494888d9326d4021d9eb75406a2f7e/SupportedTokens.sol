// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

abstract contract SupportedTokens {
    error TokenNotSupported(address token);

    function _checkToken(address token) internal view {
        if (!_isTokenSupported(token)) {
            revert TokenNotSupported(token);
        }
    }

    function _isTokenSupported(address) internal view virtual returns (bool);

    function _supportedTokens()
        internal
        view
        virtual
        returns (address[] memory);
}

