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
  //Role Permission Definition
  bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
  bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
  //Price Aggregator Address Corresponding to ERC20 Token Address
  mapping(address => address) public tokenAggregators;
  //Stablecoin Contract
  IERC20MetadataUpgradeable stableToken;
  //Reserve Coin Contract
  IERC20MetadataUpgradeable reserveToken;
  //WSTETH Address
  address internal constant WSTETH_ADDRESS = 0x5979D7b546E38E414F7E9822514be443A4800529;
  //STETH Address
  address internal constant STETH_ADDRESS = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
  //Error Message Constant
  string internal constant PRICE_FEED_ERROR = "Conversion: Get Price Error";

  function __Conversion_init(IERC20MetadataUpgradeable stableToken_,IERC20MetadataUpgradeable reserveToken_) internal onlyInitializing {
    __Conversion_init_unchained(stableToken_,reserveToken_);
  }

  function __Conversion_init_unchained(IERC20MetadataUpgradeable stableToken_,IERC20MetadataUpgradeable reserveToken_) internal onlyInitializing {
    stableToken = stableToken_;
    reserveToken = reserveToken_;
  }

  /**
  * @notice                Conversion between two ERC20 tokens:sourceAmount*sourcePrice/sourceDecimals=targetAmount*targetPrice/targetDecimals
  * @param sourceAddress   Address of the source token
  * @param targetAddress   Address of the target token
  * @param sourceAmount    Quantity of the source token
  * @return uint256        Quantity of the target token
  */
  function convertAmt(address sourceAddress,address targetAddress,uint256 sourceAmount) public view returns(uint256){
    IERC20MetadataUpgradeable sourceToken = IERC20MetadataUpgradeable(sourceAddress);
    IERC20MetadataUpgradeable targetToken = IERC20MetadataUpgradeable(targetAddress);
    //console.log("getPrice(sourceAddress)=",getPrice(sourceAddress));
    //console.log("getPrice(targetAddress)=",getPrice(targetAddress));
    return sourceAmount*getPrice(sourceAddress)*10**targetToken.decimals()/(getPrice(targetAddress)*10**sourceToken.decimals());
  }

  /**
  * @notice           Obtaining the price ratio between a token and STABLE_COIN
  * @return uint256
  */
  function getPrice(address tokenAddress) public view returns(uint256){
    uint256 token_usd;
    if(tokenAddress==WSTETH_ADDRESS){
      uint256 steth_usd = aggregatorAction(STETH_ADDRESS);
      token_usd = steth_usd * aggregatorAction(address(0))  / 1e18;
    }else{
      token_usd = aggregatorAction(tokenAddress);
    }
    return token_usd * 1e6 / aggregatorAction(address(stableToken));
  }

  /**
  * @notice           Obtaining the conversion rate between a token and ETH from Chainlink
  * @return uint256
  */
  function aggregatorAction(address tokenAddress) public view returns(uint256){
    AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenAggregators[tokenAddress]);
    (,int256 answer,,,) = priceFeed.latestRoundData();
    require(answer>=0,PRICE_FEED_ERROR);
    return uint256(answer);
  }

  /**
  * @notice     Setting up the mapping relationship between the token address and the price aggregator address
  */
  function setAggregators(address tokenAddress,address aggregatorAddress) external onlyRole(GOVERNOR_ROLE){
    tokenAggregators[tokenAddress] = aggregatorAddress;
  }

  uint256[47] private __gap;


}

