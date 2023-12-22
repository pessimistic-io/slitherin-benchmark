// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./AggregatorV3Interface.sol";
import "./IConversion.sol";
//import "hardhat/console.sol";

contract ConversionUpgradeable is Initializable,AccessControlEnumerableUpgradeable,IConversion{
  using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
  //角色权限定义
  bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  //ERC20代币地址对应的价格聚合器地址
  mapping(address => address) public tokenAggregators;
  //稳定币合约
  IERC20MetadataUpgradeable stableToken;
  //储备币合约
  IERC20MetadataUpgradeable reserveToken;
  //WSTETH地址
  address internal constant WSTETH_ADDRESS = 0x5979D7b546E38E414F7E9822514be443A4800529;
  //STETH地址
  address internal constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
  //报错信息常量
  string internal constant PRICE_FEED_ERROR = "Conversion: Get Price Error";

  function __Conversion_init(IERC20MetadataUpgradeable stableToken_,IERC20MetadataUpgradeable reserveToken_) internal onlyInitializing {
    __Conversion_init_unchained(stableToken_,reserveToken_);
  }

  function __Conversion_init_unchained(IERC20MetadataUpgradeable stableToken_,IERC20MetadataUpgradeable reserveToken_) internal onlyInitializing {
    stableToken = stableToken_;
    reserveToken = reserveToken_;
  }

  /**
  * @notice                两种ERC20token之间的转化:sourceAmount*sourcePrice/sourceDecimals=targetAmount*targetPrice/targetDecimals
  * @param sourceAddress   来源token的地址
  * @param targetAddress   目标token的地址
  * @param sourceAmount    来源token数量
  * @return uint256        目标token数量
  */
  function convertAmt(address sourceAddress,address targetAddress,uint256 sourceAmount) public view returns(uint256){
    IERC20MetadataUpgradeable sourceToken = IERC20MetadataUpgradeable(sourceAddress);
    IERC20MetadataUpgradeable targetToken = IERC20MetadataUpgradeable(targetAddress);
    //console.log("getPrice(sourceAddress)=",getPrice(sourceAddress));
    //console.log("getPrice(targetAddress)=",getPrice(targetAddress));
    return sourceAmount*getPrice(sourceAddress)*10**targetToken.decimals()/(getPrice(targetAddress)*10**sourceToken.decimals());
  }

  /**
  * @notice           获取token跟STABLE_COIN的价格比
  * @return uint256
  */
  function getPrice(address tokenAddress) public view returns(uint256){
    uint256 stable_coin_usd = aggregatorAction(address(stableToken));
    uint256 token_usd;
    if(tokenAddress==WSTETH_ADDRESS){
      uint256 steth_usd = aggregatorAction(STETH_ADDRESS);
      token_usd = steth_usd * aggregatorAction(address(0))  / 1e18;
    }else{
      token_usd = aggregatorAction(tokenAddress);
    }
    return token_usd * 1e6 / stable_coin_usd;
  }

  /**
  * @notice           从chainlink获取token跟ETH的转换比率
  * @return uint256
  */
  function aggregatorAction(address tokenAddress) public view returns(uint256){
    AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenAggregators[tokenAddress]);
    (,int256 answer,,,) = priceFeed.latestRoundData();
    require(answer>=0,PRICE_FEED_ERROR);
    uint256 rate = uint256(answer);
    return rate;
  }

  /**
  * @notice     设置token地址跟询价聚合器地址的对应关系
  */
  function setAggregators(address tokenAddress,address aggregatorAddress) external onlyRole(GOVERNOR_ROLE){
    tokenAggregators[tokenAddress] = aggregatorAddress;
  }

  uint256[47] private __gap;


}

