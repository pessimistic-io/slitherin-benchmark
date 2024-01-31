// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Math.sol";
import "./IERC20Metadata.sol";
import "./IPriceProvider.sol";

/**
 * @title Price providers' super class that implements common functions
 */
abstract contract PriceProvider is IPriceProvider {
    uint256 public constant USD_DECIMALS = 18;

    /// @inheritdoc IPriceProvider
    function getPriceInUsd(address token_) public view virtual returns (uint256 _priceInUsd, uint256 _lastUpdatedAt);

    /// @inheritdoc IPriceProvider
    function quote(
        address tokenIn_,
        address tokenOut_,
        uint256 amountIn_
    )
        external
        view
        virtual
        override
        returns (
            uint256 _amountOut,
            uint256 _tokenInLastUpdatedAt,
            uint256 _tokenOutLastUpdatedAt
        )
    {
        uint256 _amountInUsd;
        (_amountInUsd, _tokenInLastUpdatedAt) = quoteTokenToUsd(tokenIn_, amountIn_);
        (_amountOut, _tokenOutLastUpdatedAt) = quoteUsdToToken(tokenOut_, _amountInUsd);
    }

    /// @inheritdoc IPriceProvider
    function quoteTokenToUsd(address token_, uint256 amountIn_)
        public
        view
        override
        returns (uint256 _amountOut, uint256 _lastUpdatedAt)
    {
        uint256 _price;
        (_price, _lastUpdatedAt) = getPriceInUsd(token_);
        _amountOut = (amountIn_ * _price) / 10**IERC20Metadata(token_).decimals();
    }

    /// @inheritdoc IPriceProvider
    function quoteUsdToToken(address token_, uint256 amountIn_)
        public
        view
        override
        returns (uint256 _amountOut, uint256 _lastUpdatedAt)
    {
        uint256 _price;
        (_price, _lastUpdatedAt) = getPriceInUsd(token_);
        _amountOut = (amountIn_ * 10**IERC20Metadata(token_).decimals()) / _price;
    }
}

