// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

abstract contract SupportedTokens {
    error TokenNotSupported(address token);

    function supportedTokens() public view virtual returns (address[] memory t);

    function _checkToken(address token) internal view {
        if (!_isTokenSupported(token)) {
            revert TokenNotSupported(token);
        }
    }

    function _isTokenSupported(
        address
    ) internal view virtual returns (bool isSupported);
}

