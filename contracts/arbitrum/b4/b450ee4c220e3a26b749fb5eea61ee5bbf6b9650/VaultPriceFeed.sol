// SPDX-License-Identifier: MIT

import "./Address.sol";
import "./IVaultPriceFeed.sol";
import "./ISettingsManager.sol";
import "./AggregatorV3Interface.sol";
import "./BaseConstants.sol";
import "./IFastPriceFeed.sol";
import "./BaseAccess.sol";

pragma solidity ^0.8.12;

contract VaultPriceFeed is IVaultPriceFeed, BaseConstants, BaseAccess {
    ISettingsManager public settingsManager;
    mapping(address => address) public fastPriceFeeds;
    mapping(address => uint256) public priceDecimals;
    mapping(address => address) public chainLinkAggregators;
    bool public isSupportFastPrice;

    event SetTokenConfig(address indexed token, address fastPriceFeed, uint256 priceDecimals);
    event SetSupportFastPrice(bool isSupportFastPrice);
    event SetTokenAggregator(address indexed token, address aggreagator);
    event SetSettingsManager(address indexed settingsManager);

    function setSupportFastPrice(bool _isSupport) external onlyOwner {
        isSupportFastPrice = _isSupport;
        emit SetSupportFastPrice( _isSupport);
    }

    function setSettingsManager(address _settingsManager) external onlyOwner {
        require(Address.isContract(_settingsManager), "Invalid settingsManager");
        settingsManager = ISettingsManager(_settingsManager);
        emit SetSettingsManager(_settingsManager);
    }

    /*
    @dev: Set token config, allow to set address(0) for fastPriceFeed
    */
    function setTokenConfig(address _token, address _fastPriceFeed, uint256 _priceDecimals) external override  onlyOwner {
        require(Address.isContract(_token), "Invalid token");
        fastPriceFeeds[_token] = _fastPriceFeed;
        priceDecimals[_token] = _priceDecimals;
        emit SetTokenConfig(_token, _fastPriceFeed, _priceDecimals);
    }

    function setTokenAggregator(address _indexToken, address _agregator) external onlyOwner {
        chainLinkAggregators[_indexToken] = _agregator;
        emit SetTokenAggregator(_indexToken, _agregator);
    }

    /*
    @dev: Return the last price including price, updatedAt, isFastPrice
    */
    function getLastPrice(address _token) external view override returns (uint256, uint256, bool) {
        (uint256 price, uint256 updatedAt, bool isFastPrice) = _getLastPrice(_token);
        return (price, updatedAt, isFastPrice ? block.timestamp - updatedAt <= _getMaxPriceUpdatedDelay() : false);
    }

    /*
    @dev: Return the lastPrices and isLastestSync result, 
        which is the union of all checks between maxPriceUpdatedDelay and updatedAt combined with isFastPrice
    */
    function getLastPrices(address[] memory _tokens) external view override returns(uint256[] memory, bool) {
        require(_tokens.length > 0, "Invalid tokens length");
        bool isLastestSync = true;
        uint256[] memory prices = new uint256[](_tokens.length);
        uint256 maxPriceUpdatedDelay = _getMaxPriceUpdatedDelay();

        for (uint256 i = 0; i < prices.length; i++) {
            (uint256 price, uint256 updatedAt, bool isFastPrice) = _getLastPrice(_tokens[i]);
            prices[i] = price;

            if (!isFastPrice) {
                isLastestSync = false;
            } else if (isLastestSync) {
                isLastestSync = block.timestamp - updatedAt <= maxPriceUpdatedDelay;
            }
        }

        return (prices, isLastestSync);
    }

    function _getLastPrice(address _token) internal view returns (uint256, uint256, bool) {
        uint256 price; 
        uint256 updatedAt;

        if (!isSupportFastPrice) {
            (price, updatedAt) = _getLastPriceByAggregator(_token);
            return (price, updatedAt, false);
        } 

        require(fastPriceFeeds[_token] != address(0), "Invalid fastPriceFeed");
        
        try IFastPriceFeed(fastPriceFeeds[_token]).latestSynchronizedPrice() 
                returns (uint256 fastPrice, uint256 fastPriceUpdatedAt) {
            if (fastPrice != 0) {
                return (fastPrice, fastPriceUpdatedAt, true);
            } else {
                (price, updatedAt) = _getLastPriceByAggregator(_token); 
                return (price, updatedAt, false);
            }
        } catch {
            (price, updatedAt) = _getLastPriceByAggregator(_token); 
            return (price, updatedAt, false);
        }
    }

    function getLastPriceByAggregator(address _token) external view returns(uint256, uint256) {
        return _getLastPriceByAggregator(_token);
    }

    function _getLastPriceByAggregator(address _token) internal view returns (uint256, uint256) {
        address aggreagatorAddress = chainLinkAggregators[_token];
        require(aggreagatorAddress != address(0), "This token has not been set up aggregator");
            (, int256 answer, , uint256 updatedAt, ) = AggregatorV3Interface(aggreagatorAddress).latestRoundData();
        uint256 aggregatorDecimals = AggregatorV3Interface(aggreagatorAddress).decimals();
        return (uint256(answer) * PRICE_PRECISION / (10**aggregatorDecimals), updatedAt);
    }

    function setLatestPrice(address _token, uint256 _latestPrice) external limitAccess {
        if (fastPriceFeeds[_token] != address(0)) {
            try IFastPriceFeed(fastPriceFeeds[_token]).setLatestAnswer(_latestPrice) {} 
            catch {}
        }
    }

    function _getMaxPriceUpdatedDelay() internal view returns (uint256) {
        require(address(settingsManager) != address(0), "SettingsManager not initialized");
        uint256 maxPriceUpdatedDelay = settingsManager.maxPriceUpdatedDelay();
        require(maxPriceUpdatedDelay > 0, "Invalid maxPriceUpdatedDelay");
        return maxPriceUpdatedDelay;
    }
}
