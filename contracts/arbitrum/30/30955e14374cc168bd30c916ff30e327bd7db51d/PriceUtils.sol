// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IGlpManager} from "./IGlpManager.sol";
import {IGlp} from "./IGlp.sol";
import {IVault} from "./IVault.sol";
import {IPoolStateHelper} from "./IPoolStateHelper.sol";
import {ILeveragedPool} from "./ILeveragedPool.sol";
import {ExpectedPoolState, ILeveragedPool2} from "./IPoolStateHelper.sol";
import {PositionType} from "./PositionType.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract PriceUtils is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  IGlpManager private glpManager;
  IGlp private glp;
  IVault private vault;
  IPoolStateHelper private poolStateHelper;
  uint32 private constant USDC_MULTIPLIER = 1*10**6;
  uint32 private constant PERCENT_DIVISOR = 1000;

  function initialize(address _glpManager, address _glp, address _vaultAddress, address _poolStateHelperAddress) public initializer {
    glpManager = IGlpManager(_glpManager);
    glp = IGlp(_glp);
    vault = IVault(_vaultAddress);
    poolStateHelper = IPoolStateHelper(_poolStateHelperAddress);

    __Ownable_init();
  }

  function _authorizeUpgrade(address) internal override onlyOwner {}

  function glpPrice() public view returns (uint256) {
    uint256 aum = glpManager.getAumInUsdg(true);
    uint256 totalSupply = glp.totalSupply();
    
    return aum * USDC_MULTIPLIER / totalSupply;
  }

  function getTokenPrice(address priceFeedAddress) public view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddress); 

    (
      /*uint80 roundID*/,
      int price,
      /*uint startedAt*/,
      /*uint timeStamp*/,
      /*uint80 answeredInRound*/
    ) = priceFeed.latestRoundData();

    return uint256(price);
  }

  function perpPoolTokenPrice(address leveragedPoolAddress, PositionType positionType) public view returns (uint256) {
      ExpectedPoolState memory poolState = poolStateHelper.getExpectedState(ILeveragedPool2(leveragedPoolAddress), 1);
  
      if (positionType == PositionType.Long) {
        return poolState.longBalance * USDC_MULTIPLIER / (poolState.longSupply + poolState.remainingPendingLongBurnTokens);
      }

      return poolState.shortBalance * USDC_MULTIPLIER / (poolState.shortSupply + poolState.remainingPendingShortBurnTokens);
  }
} 
