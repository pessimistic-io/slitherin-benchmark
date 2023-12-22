// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.17;

import { ITokenUsdOracle } from "./Interface.sol";

import "./IERC20Metadata.sol";
import "./IERC20.sol";
import "./AggregatorV3Interface.sol";
import "./OffchainOracle.sol";


/// @title Interface for any USD oracle for Goerli compatible networks
/// @author DFKassa Team
contract ArbitrumTokenUsdOracle is ITokenUsdOracle {
    uint256 public constant E16 = 10 ** 16;
    uint256 public constant SPOT_PRICE_NATIVE_CURRENCY_NUMERATOR = 10 ** 18;
    address public constant spotPriceAggregator = 0x735247fb0a604c0adC6cab38ACE16D0DbA31295F;
    address public constant nativeCurrencyToUsdOracle = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    /// @inheritdoc ITokenUsdOracle
    function calcE18(
        address _token,
        uint256 _amount
    ) public view returns (uint256 _priceInUsd, uint256 _amountInUsd) {
        AggregatorV3Interface _priceFeedContract = AggregatorV3Interface(nativeCurrencyToUsdOracle);
        OffchainOracle _spotPriceAggregatorContract = OffchainOracle(spotPriceAggregator);

        (, int256 _nativeCurrencyUsdPriceIntValue, , ,) = _priceFeedContract.latestRoundData();
        uint256 _nativeCurrencyUsdPriceValue = uint256(_nativeCurrencyUsdPriceIntValue);
        uint8 _nativeCurrencyUsdPriceDecimals = _priceFeedContract.decimals();

        uint256 _tokenDecimals;
        uint256 _rateToNativeCurrency;
        if (_token == address(0)) {
            _tokenDecimals = SPOT_PRICE_NATIVE_CURRENCY_NUMERATOR;
            _rateToNativeCurrency = SPOT_PRICE_NATIVE_CURRENCY_NUMERATOR;
        } else {
            IERC20Metadata _tokenContract = IERC20Metadata(_token);
            _tokenDecimals = 10 ** _tokenContract.decimals();
            _rateToNativeCurrency = _spotPriceAggregatorContract.getRateToEth(_tokenContract, false);
        }

        _priceInUsd = (
            _rateToNativeCurrency
            * _tokenDecimals
            / SPOT_PRICE_NATIVE_CURRENCY_NUMERATOR
            * _nativeCurrencyUsdPriceValue
            / (10 ** _nativeCurrencyUsdPriceDecimals)
        );

        _amountInUsd = (
            _amount * _priceInUsd
            / _tokenDecimals // because of _amount multiplier
        );
    }

    /// @inheritdoc ITokenUsdOracle
    function calcE2(
        address _token,
        uint256 _amount
    ) public view returns (uint256 _priceInUsd, uint256 _amountInUsd) {
        (uint256 _priceInUsdE18, uint256 _amountInUsdE18) = calcE18(_token, _amount);
        _priceInUsd = _priceInUsdE18 / E16;
        _amountInUsd = _amountInUsdE18 / E16;
    }
}

