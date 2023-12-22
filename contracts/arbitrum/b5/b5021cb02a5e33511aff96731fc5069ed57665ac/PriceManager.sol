// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./Address.sol";
import "./IPriceManager.sol";
import "./IVaultPriceFeed.sol";
import "./BaseAccess.sol";
import {Constants} from "./Constants.sol";

contract PriceManager is IPriceManager, BaseAccess, Constants {
    address public RUSD;
    IVaultPriceFeed public vaultPriceFeed;
    mapping(address => bool) public isInitialized;

    mapping(address => bool) public override isForex;
    mapping(address => uint256) public override maxLeverage; //  50 * 10000 50x
    mapping(address => uint256) public override tokenDecimals;

    event SetRUSD(address rUSD);
    event SetVaultPriceFeed(address indexed vaultPriceFeed);

    constructor(address _rUSD, address _vaultPriceFeed) {
        require(Address.isContract(_rUSD), "Invalid RUSD address");
        RUSD = _rUSD;
        emit SetRUSD(_rUSD);

        if (_vaultPriceFeed != address(0)) {
            vaultPriceFeed = IVaultPriceFeed(vaultPriceFeed);
            emit SetVaultPriceFeed(_vaultPriceFeed);
        }
    }

    //Config functions
    function setVaultPriceFeed(address _vaultPriceFeed) external onlyOwner {
        vaultPriceFeed = IVaultPriceFeed(_vaultPriceFeed);
        emit SetVaultPriceFeed(_vaultPriceFeed);
    }

    function setTokenConfig(address _token, uint256 _tokenDecimals, uint256 _maxLeverage, bool _isForex) external onlyOwner {
        require(Address.isContract(_token), "Token invalid");
        require(!isInitialized[_token], "Already initialized");
        tokenDecimals[_token] = _tokenDecimals;
        require(_maxLeverage > MIN_LEVERAGE, "MaxLeverage should be greater than MinLeverage");
        maxLeverage[_token] = _maxLeverage;
        isForex[_token] = _isForex;
        _getLastPrice(_token);
        isInitialized[_token] = true;
    }
    //End config functions

    function getNextAveragePrice(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _nextPrice
    ) external override view returns (uint256) {
        (bool hasProfit, uint256 delta) = _getDelta(_indexToken, _size, _averagePrice, _isLong, _nextPrice);
        uint256 nextSize = _size + _sizeDelta;
        uint256 divisor;

        if (_isLong) {
            divisor = hasProfit ? nextSize + delta : nextSize - delta;
        } else {
            divisor = hasProfit ? nextSize - delta : nextSize + delta;
        }

        return (_nextPrice * nextSize) / divisor;
    }

    function fromTokenToUSD(address _token, uint256 _tokenAmount) external view override returns (uint256) {
        return _fromTokenToUSD(_token, _tokenAmount, _getLastPrice(_token));
    }

    function fromTokenToUSD(address _token, uint256 _tokenAmount, uint256 _tokenPrice) external view override returns (uint256) {
        return _fromTokenToUSD(_token, _tokenAmount, _tokenPrice);
    } 

    function _fromTokenToUSD(address _token, uint256 _tokenAmount, uint256 _tokenPrice) internal view returns (uint256) {
        if (_tokenAmount == 0) {
            return 0;
        }

        require(_tokenPrice > 0, "Token price must not be ZERO");
        uint256 decimals = tokenDecimals[_token];
        require(decimals > 0, "Token decimals must not be ZERO");
        return (_tokenAmount * _tokenPrice) / (10 ** decimals);
    }

    function fromUSDToToken(address _token, uint256 _usdAmount) external view override returns (uint256) {
        return _fromUSDToToken(_token, _usdAmount, _getLastPrice(_token));
    }

    function fromUSDToToken(address _token, uint256 _usdAmount, uint256 _tokenPrice) external view override returns (uint256) {
        return _fromUSDToToken(_token, _usdAmount, _tokenPrice);
    }

    function _fromUSDToToken(address _token, uint256 _usdAmount, uint256 _tokenPrice) internal view returns (uint256) {
        if (_usdAmount == 0) {
            return 0;
        }

        require(_tokenPrice > 0, "Token price must not be ZERO");
        uint256 decimals = tokenDecimals[_token];
        require(decimals > 0, "Token decimals must not be ZERO");
        return (_usdAmount * (10 ** decimals)) / _tokenPrice;
    }

    function floorTokenAmount(uint256 _amount, address _token) external view returns(uint256) {
        return _floorTokenAmount(_amount, _token);
    }

    function _floorTokenAmount(uint256 _amount, address _token) internal view returns(uint256) {
        require(tokenDecimals[_token] > 0, "Not initialized this token");
        uint256 decimalsDiff = PRICE_PRECISION / 10**(tokenDecimals[_token]);

        if (decimalsDiff == 1) {
            return _amount;
        }

        require(_amount >= 10**decimalsDiff, "Invalid amount");
        return _amount - (_amount % (10**decimalsDiff));
    }

    function getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _indexPrice
    ) external view override returns (bool, uint256) {
        return _getDelta(_indexToken, _size, _averagePrice, _isLong, _indexPrice);
    }

    function _getDelta(
        address _indexToken,
        uint256 _size,
        uint256 _averagePrice,
        bool _isLong,
        uint256 _indexPrice
    ) internal view returns (bool, uint256) {
        require(_averagePrice > 0, "Average price must not be ZERO");
        uint256 price = _indexPrice == 0 ? _getLastPrice(_indexToken) : _indexPrice;
        require(price > 0, "Token price must not be ZERO");
        uint256 priceDelta = _averagePrice >= price ? _averagePrice - price : price - _averagePrice;
        uint256 delta = (_size * priceDelta) / _averagePrice;
        bool hasProfit = _isLong ? price >= _averagePrice : _averagePrice >= price;

        return (hasProfit, delta);
    }

    function getLastPrice(address _token) external view override returns (uint256) {
        return _token == RUSD ? PRICE_PRECISION : _getLastPrice(_token);
    }

    function _getLastPrice(address _token) internal view returns(uint256) {
        _verifyVaultPriceFeedIntialized();
        (uint256 lastPrice, , ) = IVaultPriceFeed(vaultPriceFeed).getLastPrice(_token);
        return lastPrice;
    }

    function getLatestSynchronizedPrice(address _token) external view override returns (uint256, uint256, bool) {
        _verifyVaultPriceFeedIntialized();
        return IVaultPriceFeed(vaultPriceFeed).getLastPrice(_token);
    }

    function getLatestSynchronizedPrices(address[] memory _tokens) public view override returns (uint256[] memory, bool) {
        _verifyVaultPriceFeedIntialized();
        return IVaultPriceFeed(vaultPriceFeed).getLastPrices(_tokens);
    }

    function setLatestPrice(address _token, uint256 _latestPrice) limitAccess external {
        if (address(vaultPriceFeed) != address(0)) {
            try IVaultPriceFeed(vaultPriceFeed).setLatestPrice(_token, _latestPrice) {}
            catch {}
        }
    }

    function setLatestPrices(address[] memory _tokens, uint256[] memory _prices) limitAccess external {
        require(_tokens.length > 0, "Invalid array length, ZERO");
        require(_tokens.length == _prices.length, "Invalid array length, not same");

        for (uint256 i = 0; i < _tokens.length; i++) {
            try IVaultPriceFeed(vaultPriceFeed).setLatestPrice(_tokens[i], _prices[i]) {}
            catch {}
        }
    }

    function getTokenDecimals(address _token) external view returns(uint256) {
        uint256 tokenDecimal = tokenDecimals[_token];
        require(tokenDecimal > 0, "Invalid token decimals");
        return tokenDecimal;
    }

    function setInitializedForDev(address _token, bool _isInitialized) external onlyOwner {
       isInitialized[_token] = _isInitialized;
    }

    function _verifyVaultPriceFeedIntialized() internal view {
        require(address(vaultPriceFeed) != address(0), "VaultPriceFeed not initialized");
    }
}
