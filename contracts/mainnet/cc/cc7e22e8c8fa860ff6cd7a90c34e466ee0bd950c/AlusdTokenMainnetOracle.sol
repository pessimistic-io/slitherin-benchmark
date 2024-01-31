// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Math.sol";
import "./UsingProvidersAggregator.sol";
import "./UsingMaxDeviation.sol";
import "./UsingStableCoinProvider.sol";
import "./UsingStalePeriod.sol";
import "./IUpdatableOracle.sol";
import "./IUniswapV2LikePriceProvider.sol";

/**
 * @title alUSD Oracle (mainnet-only)
 */
contract AlusdTokenMainnetOracle is
    IUpdatableOracle,
    UsingProvidersAggregator,
    UsingStableCoinProvider,
    UsingStalePeriod
{
    uint256 public constant ONE_ALUSD = 1e18;
    address public constant ALUSD_ADDRESS = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(
        IPriceProvidersAggregator providersAggregator_,
        IStableCoinProvider stableCoinProvider_,
        uint256 stalePeriod_
    )
        UsingProvidersAggregator(providersAggregator_)
        UsingStableCoinProvider(stableCoinProvider_)
        UsingStalePeriod(stalePeriod_)
    {
        require(address(stableCoinProvider_) != address(0), "stable-coin-provider-is-null");
    }

    /// @inheritdoc ITokenOracle
    function getPriceInUsd(address _asset) external view returns (uint256 _priceInUsd) {
        require(address(_asset) == ALUSD_ADDRESS, "invalid-token");

        uint256 _lastUpdatedAt;
        (_priceInUsd, _lastUpdatedAt) = providersAggregator.quoteTokenToUsd(
            DataTypes.Provider.SUSHISWAP,
            ALUSD_ADDRESS,
            ONE_ALUSD
        );

        require(_priceInUsd > 0 && !_priceIsStale(_lastUpdatedAt), "price-invalid");
    }

    /// @inheritdoc IUpdatableOracle
    function update() external override {
        IUniswapV2LikePriceProvider _sushiswap = IUniswapV2LikePriceProvider(
            address(providersAggregator.priceProviders(DataTypes.Provider.SUSHISWAP))
        );
        _sushiswap.updateOrAdd(ALUSD_ADDRESS, WETH_ADDRESS);
        _sushiswap.updateOrAdd(WETH_ADDRESS, stableCoinProvider.getStableCoinIfPegged());
    }
}

