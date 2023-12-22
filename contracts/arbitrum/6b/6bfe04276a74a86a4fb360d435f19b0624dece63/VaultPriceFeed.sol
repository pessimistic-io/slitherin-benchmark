// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IChainlinkPriceFeed.sol";
import "./IVaultPriceFeed.sol";
import "./IAmmPriceFeed.sol";
import "./IPythPriceFeed.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";

contract VaultPriceFeed is Initializable,OwnableUpgradeable, IVaultPriceFeed{
  uint8 public override constant decimals = 10;
  uint256 public constant PRICE_PRECISION = 10 ** decimals;
  uint256 public constant ONE_USD = PRICE_PRECISION;

  address public override btc;
  address public override eth;

  mapping (address => bool) public strictStableTokens;
  uint256 public maxStrictPriceDeviation;

  address public ammPriceFeed;
  address public override chainlinkPriceFeed;
  address public override pythPriceFeed;

  bool public isAmmEnabled;
  bool public isPythEnabled;

  function initialize(
    address _chainlinkPriceFeed, 
    address _ammPriceFeed,
    address _pythPriceFeed,
    address _btc,
    address _eth
  ) public initializer {
    __Ownable_init();

    chainlinkPriceFeed = _chainlinkPriceFeed;
    ammPriceFeed = _ammPriceFeed;
    pythPriceFeed = _pythPriceFeed;
    btc = _btc;
    eth = _eth;
    isAmmEnabled = true;
    isPythEnabled = false;
  }

  function setTokens(address _btc, address _eth) external override onlyOwner {
    btc = _btc;
    eth = _eth;
  }
  function setPriceFeeds(address _chainlinkPriceFeed, address _ammPriceFeed, address _pythPriceFeed) external onlyOwner {
    chainlinkPriceFeed = _chainlinkPriceFeed;
    ammPriceFeed = _ammPriceFeed;
    pythPriceFeed = _pythPriceFeed;
  }
  function setChainlinkPriceFeed(address _chainlinkPriceFeed) external onlyOwner {
    chainlinkPriceFeed = _chainlinkPriceFeed;
  }
  function setAmmPriceFeed(address _ammPriceFeed) external onlyOwner {
    ammPriceFeed = _ammPriceFeed;
  }
  function setPythPriceFeed(address _pythPriceFeed) external onlyOwner {
    pythPriceFeed = _pythPriceFeed;
  }

  function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external onlyOwner {
    maxStrictPriceDeviation = _maxStrictPriceDeviation;
  }

  function setStrictStableTokens(address[] memory _tokens,bool[] memory _isStrictStableTokens) external onlyOwner{
    require(_tokens.length==_isStrictStableTokens.length, "invalid param");

    for (uint256 i = 0; i < _tokens.length; i++) {
      strictStableTokens[_tokens[i]] = _isStrictStableTokens[i];
    }
  }

  function setAmmEnabled(bool _isEnabled) external override onlyOwner {
    isAmmEnabled = _isEnabled;
  }
  function setPythEnabled(bool _isEnabled) external override onlyOwner {
    isPythEnabled = _isEnabled;
  }

  function getPrice(address _token, bool _maximise) external override view returns (uint256){
    uint256 price = getChainlinkPrice(_token);
    if(isAmmEnabled){
      uint256 ammPrice = getAmmPrice(_token);
      if(ammPrice>0){
        if (_maximise && ammPrice > price) {
          price = ammPrice;
        }
        if (!_maximise && (ammPrice < price || price==0)) {
          price = ammPrice;
        }
      }
    }

    if(isPythEnabled){
      uint256 pythPrice = getPythPrice(_token);
      if(pythPrice > 0){
        if (_maximise && pythPrice > price) {
          price = pythPrice;
        }
        if (!_maximise && (pythPrice < price || price==0)) {
          price = pythPrice;
        }
      }
    }

    if (strictStableTokens[_token]) {
      uint256 delta = price > ONE_USD ? price-ONE_USD : ONE_USD-price;
      if (delta <= maxStrictPriceDeviation) {
        return ONE_USD;
      }

      if (_maximise && price > ONE_USD) {
        return price;
      }

      if (!_maximise && price < ONE_USD) {
        return price;
      }

      return ONE_USD;
    }

    require(price>0, "price error");
    return price;
  }

  function getChainlinkPrice(address _token) private view returns (uint256){
    IChainlinkPriceFeed chainlink = IChainlinkPriceFeed(chainlinkPriceFeed);
    int256 price;
    uint8 priceDecimals;
    if(_token == eth){
      (price,priceDecimals) = chainlink.getEthUsdPrice();
    }else if(_token == btc){
      (price,priceDecimals) = chainlink.getBtcUsdPrice();
    }else{
      (price,priceDecimals) = chainlink.getPrice(_token);
    }
    
    return adjustForDecimals(uint256(price), priceDecimals, decimals);
  }

  function getAmmPrice(address _token) private view returns (uint256) {
    (uint256 price,uint8 priceDecimals) = IAmmPriceFeed(ammPriceFeed).getPrice(_token);
    return adjustForDecimals(price, priceDecimals, decimals);
  }

  function getPythPrice(address _token) private view returns (uint256) {
    try IPythPriceFeed(pythPriceFeed).getPrice(_token) returns(int256 price,uint32 priceDecimals){
      return adjustForDecimals(uint256(price), priceDecimals, decimals);
    } catch {
      return 0;
    }
  }

  function adjustForDecimals(uint256 _value, uint256 _decimalsDiv, uint256 _decimalsMul) public pure returns (uint256) {
    return _value * (10 ** _decimalsMul) / (10 ** _decimalsDiv);
  }
  
}
