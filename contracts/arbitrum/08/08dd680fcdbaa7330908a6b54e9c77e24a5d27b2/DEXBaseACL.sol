// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./EnumerableSet.sol";

import "./BaseACL.sol";

/// @title DEXBaseACL - ACL template for DEX.
/// @author Cobo Safe Dev Team https://www.cobo.com/
abstract contract DEXBaseACL is BaseACL {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet swapInTokenWhitelist;
    EnumerableSet.AddressSet swapOutTokenWhitelist;

    struct SwapInToken {
        address token;
        bool tokenStatus;
    }

    struct SwapOutToken {
        address token;
        bool tokenStatus;
    }

    constructor(address _owner, address _caller) BaseACL(_owner, _caller) {}

    // External set functions.

    function setSwapInToken(address _token, bool _tokenStatus) external onlyOwner {
        // sell
        if (_tokenStatus) {
            swapInTokenWhitelist.add(_token);
        } else {
            swapInTokenWhitelist.remove(_token);
        }
    }

    function setSwapInTokens(SwapInToken[] calldata _swapInToken) external onlyOwner {
        for (uint256 i = 0; i < _swapInToken.length; i++) {
            if (_swapInToken[i].tokenStatus) {
                swapInTokenWhitelist.add(_swapInToken[i].token);
            } else {
                swapInTokenWhitelist.remove(_swapInToken[i].token);
            }
        }
    }

    function setSwapOutToken(address _token, bool _tokenStatus) external onlyOwner {
        // buy
        if (_tokenStatus) {
            swapOutTokenWhitelist.add(_token);
        } else {
            swapOutTokenWhitelist.remove(_token);
        }
    }

    function setSwapOutTokens(SwapOutToken[] calldata _swapOutToken) external onlyOwner {
        for (uint256 i = 0; i < _swapOutToken.length; i++) {
            if (_swapOutToken[i].tokenStatus) {
                swapOutTokenWhitelist.add(_swapOutToken[i].token);
            } else {
                swapOutTokenWhitelist.remove(_swapOutToken[i].token);
            }
        }
    }

    // External view functions.
    function hasSwapInToken(address _token) public view returns (bool) {
        return swapInTokenWhitelist.contains(_token);
    }

    function getSwapInTokens() external view returns (address[] memory tokens) {
        return swapInTokenWhitelist.values();
    }

    function hasSwapOutToken(address _token) public view returns (bool) {
        return swapOutTokenWhitelist.contains(_token);
    }

    function getSwapOutTokens() external view returns (address[] memory tokens) {
        return swapOutTokenWhitelist.values();
    }

    // Internal check utility functions.

    function swapInTokenCheck(address _token) internal view {
        require(hasSwapInToken(_token), "In token not allowed");
    }

    function swapOutTokenCheck(address _token) internal view {
        require(hasSwapOutToken(_token), "Out token not allowed");
    }

    function swapInOutTokenCheck(address _inToken, address _outToken) internal view {
        swapInTokenCheck(_inToken);
        swapOutTokenCheck(_outToken);
    }
}

