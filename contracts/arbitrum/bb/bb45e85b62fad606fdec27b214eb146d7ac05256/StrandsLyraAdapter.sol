// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

//import "@openzeppelin/contracts/utils/math/Math.sol";
//import "@openzeppelin/contracts/access/Ownable.sol";
//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import "@openzeppelin/contracts/access/Ownable.sol";
import "./OptionMarketViewer.sol";
import "./OptionMarket.sol";
import "./OptionGreekCache.sol";
import "./OptionMarketPricer.sol";
import "./BaseExchangeAdapter.sol";
import "./IFeeCounter.sol";
import "./DecimalMath.sol";
import "./SignedDecimalMath.sol";
import {OwnableAdmins} from "./OwnableAdmins.sol";

import "./StrandsUtils.sol";
import "./console.sol";

contract StrandsLyraAdapter is OwnableAdmins {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  uint public licenseFeeBasisPoint = 25;
  uint public closeFeeBasisPoint = 10;
  uint public licenseFeeCap = 100000000000000000000;
  address public licenseFeeRecipient;
  address public lyraRewardRecipient;
  mapping (string => OptionMarket) public underlierToMarket;
  mapping (OptionMarket=>OptionToken) public marketToToken;
  mapping (string => OptionGreekCache) underlierToGreekCache;
  mapping (string => OptionMarketPricer) underlierToPricer;
  BaseExchangeAdapter exchangeAdapter;
  OptionMarketViewer optionMarketViewer;
  //IFeeCounter public tradingRewards;
  IERC20 public quoteAsset;

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

  function init (address _optionMarketViewer, address _exchangeAdapter, address _quoteAsset) public onlyAdmins {
    licenseFeeRecipient = msg.sender;
    optionMarketViewer = OptionMarketViewer(_optionMarketViewer);
    exchangeAdapter = BaseExchangeAdapter(_exchangeAdapter);
    quoteAsset = IERC20(_quoteAsset);
  }

  function _getIterations(uint amount) internal pure returns (uint) {
    return  Math.max(1,amount/(10 ether));
  }

  function _prorateCollateral(OptionMarket market,bool isCall,uint smallPositionAmount,
      uint bigPositionAmount,uint bigCollateral,uint strikeId) internal view returns (uint) {
    //Prorate the collateral by new position amount / old position amount since front end
    //doesnt know the final position amount when setting the collateral of the short leg.  
    //In future version where front end is aware of existing position collateral and 
    //final position amount,we can do away with this and let the front end set final 
    //collateral directly.
    if (smallPositionAmount==0) return 0;
    //console.log("preprorated collateral=$%s/100",bigCollateral/10**16);
    uint proRatedCollateral=bigCollateral*smallPositionAmount/bigPositionAmount;
    return _checkCollateralBounds(market,isCall,smallPositionAmount,proRatedCollateral,strikeId);
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
    OptionToken.OptionPosition[] memory ownerPositions = marketToToken[underlierToMarket[underlier]].getOwnerPositions(msg.sender);
    for(uint j=0;j<ownerPositions.length;j++){
        if (ownerPositions[j].state==OptionToken.PositionState.ACTIVE && strikeId==ownerPositions[j].strikeId && 
          isCall==StrandsUtils.isThisCall(OptionMarket.OptionType(ownerPositions[j].optionType)))
        {
          console.log("found existing position id=",ownerPositions[j].positionId);
          return (ownerPositions[j].positionId,ownerPositions[j].amount,StrandsUtils.isThisLong(ownerPositions[j].optionType),
            ownerPositions[j].collateral);
        }
      }
    return (positionId, positionAmount,isLong,collateral);
  }

  function _openPosition(string memory underlier, OptionMarket.TradeInputParameters memory tradeParams)
      internal returns (OptionMarket.Result memory) {    
    OptionMarket.Result memory result = underlierToMarket[underlier].openPosition(tradeParams);
    // if (address(tradingRewards) != address(0)) {
    //   tradingRewards.trackFee(address(underlierToMarket[underlier]), lyraRewardRecipient, tradeParams.amount,
    //    result.totalCost, result.totalFee);
    // }
    emit PositionTraded(underlier,false,StrandsUtils.isThisLong(tradeParams.optionType),result.positionId,
      tradeParams.amount,result.totalCost,result.totalFee,msg.sender);
    return result;
  }

  function _closePosition(string memory underlier, OptionMarket.TradeInputParameters memory tradeParams)
      internal returns (OptionMarket.Result memory result) {
    OptionMarketPricer.TradeLimitParameters memory tlp = underlierToPricer[underlier].getTradeLimitParams();
    (int callDelta,) = getDeltas(underlier,tradeParams.strikeId);
    if (callDelta > (int(DecimalMath.UNIT) - tlp.minDelta) || callDelta < tlp.minDelta)
    {
      //console.log("ForceClose");
      result=underlierToMarket[underlier].forceClosePosition(tradeParams);
    } else {result=underlierToMarket[underlier].closePosition(tradeParams);}
    
    // if (address(tradingRewards) != address(0)) {
    //   tradingRewards.trackFee(address(underlierToMarket[underlier]), lyraRewardRecipient, tradeParams.amount,
    //       result.totalCost, result.totalFee);
    // }
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
    OptionMarketViewer.MarketOptionPositions[] memory MOPositions = optionMarketViewer.getOwnerPositions(address(this));
    for(uint i=0; i<MOPositions.length ; i++){
      OptionToken.OptionPosition[] memory positions = MOPositions[i].positions;
      for(uint j=1;j<positions.length;j++){
        marketToToken[OptionMarket(MOPositions[i].market)].transferFrom(address(this), msg.sender, positions[j].positionId);
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
    uint spotPrice=exchangeAdapter.getSpotPriceForMarket(address(underlierToMarket[underlier]),BaseExchangeAdapter.PriceType.REFERENCE);
    uint minCollateral= underlierToGreekCache[underlier].getMinCollateral(StrandsUtils.getLyraOptionType(isCall,isLong), strikePrice, expiry, spotPrice, amount);
    console.log("minimal Collateral=$%s/100",minCollateral/10**16);
    return minCollateral;
  }

  function addMarket(string memory underlier, OptionMarket market, OptionToken token, 
      OptionGreekCache greekCache, OptionMarketPricer pricer) external onlyAdmins {
    underlierToMarket[underlier]=market;
    underlierToGreekCache[underlier]=greekCache;
    underlierToPricer[underlier]=pricer;
    marketToToken[market]=token;
    quoteAsset.approve(address(underlierToMarket[underlier]), type(uint).max);
  }

  function deleteMarket(string memory underlier) external onlyAdmins {
    delete marketToToken[underlierToMarket[underlier]];
    delete underlierToMarket[underlier];
  }

  function setLyraRewardRecipient(address recipient) external onlyAdmins {
    lyraRewardRecipient = recipient;
  }

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
}

