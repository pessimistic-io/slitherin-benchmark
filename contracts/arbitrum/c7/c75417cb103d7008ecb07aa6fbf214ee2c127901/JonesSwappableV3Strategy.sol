// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {JonesStrategyV3Base} from "./JonesStrategyV3Base.sol";
import {SushiAdapter} from "./SushiAdapter.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";

abstract contract JonesSwappableV3Strategy is JonesStrategyV3Base {
    using SafeERC20 for IERC20;
    using SushiAdapter for IUniswapV2Router02;

    /// Indicates if whitelist check for token swap should be required.
    bool public requireWhitelist = true;

    /// supported tokens for swapping tokens on GMX and Sushi
    mapping(address => bool) public whitelistedTokens;

    /**
     * Swaps source token to destination token on sushiswap
     * @param _source source asset
     * @param _destination destination asset
     * @param _amountIn the amount of source asset to swap
     * @param _amountOutMin minimum amount of destination asset that must be received for the transaction not to revert
     */
    function swapAssetsOnSushi(address _source, address _destination, uint256 _amountIn, uint256 _amountOutMin)
        public
        virtual
        onlyRole(KEEPER)
    {
        _validateSwapParams(_source, _destination);
        IERC20(_source).safeApprove(address(sushiRouter), _amountIn);
        address[] memory path = _getPathForSushiSwap(_source, _destination);
        sushiRouter.swapTokens(_amountIn, _amountOutMin, path, address(this));
        IERC20(_source).safeApprove(address(sushiRouter), 0);
    }

    /**
     * Whitelists `_token` for swapping.
     */
    function whitelistToken(address _token) public virtual onlyRole(GOVERNOR) {
        _whitelistToken(_token);
    }

    /**
     * Removes `_token` for whitelist.
     */
    function removeWhitelistedToken(address _token) public virtual onlyRole(GOVERNOR) {
        if (!whitelistedTokens[_token]) {
            revert TOKEN_NOT_WHITELISTED();
        }
        whitelistedTokens[_token] = false;
        IERC20(_token).safeApprove(address(sushiRouter), 0);
        _afterRemoveWhitelistedToken(_token);
    }

    /**
     * Sets whitelist requirement to `_required`. If set to true, tokens will be checked for whitelist before performing swaps.
     */
    function setRequireWhitelist(bool _required) public virtual onlyRole(GOVERNOR) {
        requireWhitelist = _required;
    }

    /**
     * A helper function that whitelists `_tokens`.
     */
    function _whitelistTokens(address[] memory _tokens) internal virtual {
        for (uint256 i = 0; i < _tokens.length; i++) {
            _whitelistToken(_tokens[i]);
        }
    }

    /**
     * A helper function that whitelist a token with address `_token`.
     */
    function _whitelistToken(address _token) internal virtual {
        if (_token == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        whitelistedTokens[_token] = true;
    }

    /**
     * Fetches sushi swap path for specified `_source` and `_destination`.
     */
    function _getPathForSushiSwap(address _source, address _destination)
        internal
        virtual
        returns (address[] memory _path)
    {
        if (_source == wETH || _destination == wETH) {
            _path = new address[](2);
            _path[0] = _source;
            _path[1] = _destination;
        } else {
            _path = new address[](3);
            _path[0] = _source;
            _path[1] = wETH;
            _path[2] = _destination;
        }
    }

    /**
     * Performs parameter valudation for swap.
     */
    function _validateSwapParams(address _source, address _destination) internal virtual {
        if (_source == address(0) || _destination == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        if (_source == _destination) {
            revert INVALID_INPUT_TOKEN();
        }

        if (!whitelistedTokens[_destination] && requireWhitelist) {
            revert TOKEN_NOT_WHITELISTED();
        }
    }

    /**
     * Hook that is invoked after removing whitelisted `_token`.
     */
    function _afterRemoveWhitelistedToken(address _token) internal virtual {}

    error INVALID_INPUT_TOKEN();
    error TOKEN_NOT_WHITELISTED();
}

