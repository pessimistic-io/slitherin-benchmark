// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

//import "@openzeppelin/contracts/utils/math/Math.sol";
//import "openzeppelin-contracts-4.4.1/access/Ownable.sol";
//import "openzeppelin-contracts-4.4.1/token/ERC20/ERC20.sol";
//import "openzeppelin-contracts-4.4.1/token/ERC20/IERC20.sol";


import {ConvertDecimals} from "./ConvertDecimals.sol";
import {Math} from "./Math.sol";
import {OptionMarketViewer} from "./OptionMarketViewer.sol";
import {OptionMarket} from "./OptionMarket.sol";
import {OptionGreekCache} from "./OptionGreekCache.sol";
import {OptionToken} from "./OptionToken.sol";
import {OptionMarketPricer} from "./OptionMarketPricer.sol";
import {DecimalMath} from "./DecimalMath.sol";
import {SignedDecimalMath} from "./SignedDecimalMath.sol";
import {LyraRegistry} from "./LyraRegistry.sol";
import {BaseExchangeAdapter} from "./BaseExchangeAdapter.sol";
import {IERC20Decimals} from "./IERC20Decimals.sol";

import {OwnableAdmins} from "./OwnableAdmins.sol";

import {StrandsUtils} from "./StrandsUtils.sol";
import {console} from "./console.sol";

contract StrandsLyraAdapter is OwnableAdmins {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  
  uint public licenseFeeBasisPoint = 25;
  uint public closeFeeBasisPoint = 10;
  uint public licenseFeeCap = 100000000000000000000;
  address public licenseFeeRecipient;
  // address public lyraRewardRecipient;
  mapping (string => OptionMarket) public underlierToMarket;
  BaseExchangeAdapter public exchangeAdapter;
  LyraRegistry lyraRegistry;
  OptionMarketViewer optionMarketViewer;
  IERC20Decimals public quoteAsset;
  
    /**
   * @dev Emitted when a position is traded
   */
  event PositionTraded(
    string underlier,
    bool isLong,
    bool isClose,
    uint indexed positionId,
    uint amount,
    uint totalCost,
    uint totalLyraFee,
    address indexed owner
  );
  
  constructor(){}

  function init(address _lyraRegistry) public onlyAdmins {
    bytes32 EXCHANGE_ADAPTER = "GMX_ADAPTER";
    bytes32 MARKET_VIEWER = "MARKET_VIEWER";
    lyraRegistry = LyraRegistry(_lyraRegistry);
    exchangeAdapter = BaseExchangeAdapter(lyraRegistry.getGlobalAddress(EXCHANGE_ADAPTER));
    licenseFeeRecipient = msg.sender;
    optionMarketViewer = OptionMarketViewer(lyraRegistry.getGlobalAddress(MARKET_VIEWER));
  }

  function _getIterations(uint amount) internal pure returns (uint) {
    return  Math.max(1,amount/(10 ether));
  }

  function _checkCollateralBounds(OptionMarket market,bool isCall,uint amount,uint collateral,uint strikeId) 
    internal view returns(uint) {
    collateral=Math.max(420 ether,collateral);
    if (!isCall) {
      //Biggest necessary collateral for short put is strike*amount
      uint strikePrice=market.getStrike(strikeId).strikePrice;
      collateral=Math.min(strikePrice.multiplyDecimal(amount),collateral);
    } 
    //console.log("new collateral=$%s/100",collateral/10**18,collateral%10**16);
    return collateral;
  }

  function getExistingPosition(string memory underlier, uint strikeId, bool isCall) 
      public view returns (uint positionId, uint positionAmount, bool isLong, uint collateral)
  {
    OptionToken.OptionPosition[] memory ownerPositions = OptionToken(lyraRegistry.getMarketAddresses(
        underlierToMarket[underlier]).optionToken).getOwnerPositions(msg.sender);
    for(uint j=0;j<ownerPositions.length;j++){
        if (ownerPositions[j].state==OptionToken.PositionState.ACTIVE && strikeId==ownerPositions[j].strikeId && 
          isCall==StrandsUtils.isThisCall(OptionMarket.OptionType(ownerPositions[j].optionType)))
        {
          console.log("found existing position id=%s state=%s",ownerPositions[j].positionId,uint(ownerPositions[j].state));
          return (ownerPositions[j].positionId,ownerPositions[j].amount,StrandsUtils.isThisLong(ownerPositions[j].optionType),
            ownerPositions[j].collateral);
        }
      }
    return (positionId, positionAmount,isLong,collateral);
  }

  function _openPosition(string memory underlier, OptionMarket.TradeInputParameters memory tradeParams)
      internal returns (OptionMarket.Result memory) {    
    OptionMarket.Result memory result = underlierToMarket[underlier].openPosition(tradeParams);
    emit PositionTraded(underlier,false,StrandsUtils.isThisLong(tradeParams.optionType),result.positionId,
      tradeParams.amount,result.totalCost,result.totalFee,msg.sender);
    return result;
  }

  function _closePosition(string memory underlier, OptionMarket.TradeInputParameters memory tradeParams)
      internal returns (OptionMarket.Result memory result) {
    OptionMarketPricer.TradeLimitParameters memory tlp = OptionMarketPricer(lyraRegistry.getMarketAddresses(
      underlierToMarket[underlier]).optionMarketPricer).getTradeLimitParams();
    (int callDelta,) = getDeltas(underlier,tradeParams.strikeId);
    if (callDelta > (int(DecimalMath.UNIT) - tlp.minDelta) || callDelta < tlp.minDelta)
    {
      //console.log("ForceClose");
      result=underlierToMarket[underlier].forceClosePosition(tradeParams);
    } else {result=underlierToMarket[underlier].closePosition(tradeParams);}

    emit PositionTraded(underlier,true,StrandsUtils.isThisLong(tradeParams.optionType),result.positionId,
        tradeParams.amount,result.totalCost,result.totalFee,msg.sender);
    return result;
  }

  function getOptionPrices(string memory underlier, uint strikeId) public view returns (uint callPrice, uint putPrice) {
    return StrandsUtils.getOptionPrices(underlierToMarket[underlier],exchangeAdapter,strikeId);
  }

  function getDeltas(string memory underlier,uint strikeId) public view returns (int,int) {
    return StrandsUtils.getDeltas(underlierToMarket[underlier],exchangeAdapter,strikeId);
  }

  function getStrikeIV(string memory underlier,uint strikeId) public view returns (uint iv) {
    return StrandsUtils.getStrikeIV(underlierToMarket[underlier],strikeId);
  }

  function emergencyWithdrawal() external onlyAdmins {
    OptionToken optionToken;
    OptionMarketViewer.MarketOptionPositions[] memory MOPositions = optionMarketViewer.getOwnerPositions(address(this));
    if (MOPositions.length>0) {
      optionToken =OptionToken(lyraRegistry.getMarketAddresses(OptionMarket(MOPositions[0].market)).optionToken);
    }
    for(uint i=0; i<MOPositions.length ; i++){
      OptionToken.OptionPosition[] memory positions = MOPositions[i].positions;
      for(uint j=1;j<positions.length;j++){
        optionToken.transferFrom(address(this), msg.sender, positions[j].positionId);
      }
    }
    address payable receiver = payable(msg.sender);
    receiver.transfer(address(this).balance);
  }

  //Exposed this outside so front end can get minimal Collateral
  function getMinCollateralForStrike(string memory underlier,bool isCall,bool isLong,uint strikeId,
    uint amount) public view returns (uint) {
    if (isLong) return 0;
    (uint strikePrice,uint expiry) = underlierToMarket[underlier].getStrikeAndExpiry(strikeId);
    uint spotPrice=exchangeAdapter.getSpotPriceForMarket(address(underlierToMarket[underlier]),
      BaseExchangeAdapter.PriceType.REFERENCE);
    uint minCollateral= OptionGreekCache(lyraRegistry.getMarketAddresses(underlierToMarket[underlier]).greekCache).
      getMinCollateral(StrandsUtils.getLyraOptionType(isCall,isLong), strikePrice, expiry, spotPrice, amount);
    console.log("minimal Collateral=$%s/100",minCollateral/10**16);
    return minCollateral;
  }

  function addMarket(string memory underlier, address optionMarket) external onlyAdmins {
    LyraRegistry.OptionMarketAddresses memory addresses = lyraRegistry.getMarketAddresses(OptionMarket(optionMarket));
    underlierToMarket[underlier]=OptionMarket(optionMarket);
    quoteAsset=IERC20Decimals(address(addresses.quoteAsset));
    quoteAsset.approve(address(optionMarket), type(uint).max);
  }

  function deleteMarket(string memory underlier) external onlyAdmins {
    quoteAsset.approve(address(underlierToMarket[underlier]), 0);
    delete underlierToMarket[underlier];
  }

  // function setLyraRewardRecipient(address recipient) external onlyAdmins {
  //   lyraRewardRecipient = recipient;
  // }

  function setLicenseFeeRecipient(address recipient) external onlyAdmins {
    licenseFeeRecipient = recipient;
  }

  /// @notice set license fee
  /// @param newLFBP new license fee rate in basis points 
  function setLicenseFeeRate(uint newLFBP) external onlyAdmins {
    licenseFeeBasisPoint = newLFBP;
  }

  /// @notice set license fee
  /// @param newCFBP new license fee rate in basis points 
  function setCloseFeeRate(uint newCFBP) external onlyAdmins {
    closeFeeBasisPoint = newCFBP;
  }

  /// @notice set license fee cap
  /// @param newLFCap new license fee cap
  function setLicenseFeeCap(uint newLFCap) external onlyAdmins {
    licenseFeeCap = newLFCap;
  }

  function _abs(int val) internal pure returns (uint) {
    return val >= 0 ? uint(val) : uint(-val);
  }
}

