// SPDX-License-Identifier: MIT
// LongGammaStrategy.sol v1.0b
pragma solidity ^0.8.16;


import {StrandsStrategyBase} from "./StrandsStrategyBase.sol";
import {console} from "./console.sol";
import {StrandsUtils} from "./StrandsUtils.sol";
import {StrandsVault} from "./StrandsVault.sol";
import {OneClicks} from "./OneClicks.sol";
import {DecimalMath} from "./DecimalMath.sol";
import {SignedDecimalMath} from "./SignedDecimalMath.sol";
import {ConvertDecimals} from "./ConvertDecimals.sol";

contract LongGammaStrategy is StrandsStrategyBase {
  using DecimalMath for uint;
  using SignedDecimalMath for int;


  constructor(StrandsVault _vault, string memory _underlier, address _oneClicksAddress, address _lyraRegistry)
    StrandsStrategyBase(_vault, _underlier, _oneClicksAddress, _lyraRegistry) {}


  function shouldWeHedge() public view returns (uint, uint, PositionsInfo memory) {
    PositionsInfo memory p =_getAllPositionsDelta();
    return (lastHedgeTimestamp,lastHedgeSpot,p);
  }

  function doTrade(uint strikeId) public override onlyVault returns (int balChange,uint[] memory positionIds) {
    if (activeStrikeId>0 && hasOpenPosition()) {
      console.log("already has active strike id = ",activeStrikeId);
      strikeId=activeStrikeId;
    }
    require(isValidStrike(strikeId), "invalid strike");
    uint strikeIV = StrandsUtils.getStrikeIV(oneClicks.underlierToMarket(underlier),strikeId);
    console.log("strikeIV=%s/100",strikeIV/10**16);
    require(strikeIV<strategyDetail.maxVol,"IV too high to open straddle");
    
    (uint callAmount,uint putAmount,uint takeFromVault) = _getZeroDeltaStraddle(strikeId);
    console.log("takeFromVault18=%s/100",takeFromVault/10**16);
    quoteAsset.transferFrom(address(vault), address(this), takeFromVault);
    console.log("before trade strategy quoteBal=%s/100",quoteAsset.balanceOf(address(this))/(10**(quoteAsset.decimals()-2)));
    OneClicks.LegDetails[] memory legs = new OneClicks.LegDetails[](2);
    legs[0]=OneClicks.LegDetails(putAmount,strikeId,false,true,0);
    legs[1]=OneClicks.LegDetails(callAmount,strikeId,true,true,0);
    int balBefore = int(quoteAsset.balanceOf(address(this)));
    positionIds = oneClicks.tradeOneClick('Straddle',underlier,takeFromVault,legs);
    balChange=int(quoteAsset.balanceOf(address(this)))-balBefore;
    console.log("after trade strategy quoteBal=%s/100 balanceChange=-%s/100",
      quoteAsset.balanceOf(address(this))/(10**(quoteAsset.decimals()-2)),
      _abs(balChange)/(10**(quoteAsset.decimals()-2)));
    quoteAsset.transfer(address(vault),quoteAsset.balanceOf(address(this)));
    console.log("after trade transfer back strategy quoteBal=%s/100",quoteAsset.balanceOf(address(this))/(10**(quoteAsset.decimals()-2)));
    activeStrikeId=strikeId;
    lastTradeTimestamp=block.timestamp;
    console.log("-----done with trade----");
     _getAllPositionsDelta();
    lastHedgeSpot=_getSpot();
    lastHedgeTimestamp=block.timestamp;
  }

  function _getZeroDeltaStraddle(uint strikeId) private view returns (uint callAmount, uint putAmount, uint takeFromVault) {
    console.log('spot=%s/100',_getSpot()/10**16);
    (uint callPrice, uint putPrice) = oneClicks.getOptionPrices(underlier,strikeId);
    (int strikeCallDelta, int strikePutDelta) = oneClicks.getDeltas(underlier,strikeId);
    console.log("strikeId=%s call|putPrice=%s/100|%s/100",strikeId, callPrice/10**16,putPrice/10**16);
    console.log("            call|putDelta=%s/100000000|%s/100000000",
      uint(strikeCallDelta)/10**10,uint(-1*strikePutDelta)/10**10);
    (,,,uint lockedAmountLeft,,,,) =vault.vaultState();
    uint amount=lockedAmountLeft.divideDecimal(callPrice+putPrice).multiplyDecimal(strategyDetail.maxTradeUtilization);
    console.log("start with %s/100000000 straddle",amount/10**10);
    int totalDelta = _calculateTotalDelta(strikeId, int(amount), int(amount));
    if (totalDelta<0) {
      console.log("putAmountMinus=%s/100000000",_abs(totalDelta.divideDecimal(strikePutDelta))/10**10);
      putAmount = amount-_abs(totalDelta.divideDecimal(strikePutDelta));
      putAmount = amount-uint(totalDelta.divideDecimal(strikePutDelta));
      callAmount=amount;
      console.log("putAmount=%s/100000000",putAmount/10**10);
    } else {
      console.log("callAmountMinus=%s/100000000",uint(totalDelta.divideDecimal(strikeCallDelta))/10**10);
      callAmount = amount-uint(totalDelta.divideDecimal(strikeCallDelta));
      putAmount=amount;
      console.log("callAmount=%s/100000000",callAmount/10**10);
    } 
    takeFromVault=ConvertDecimals.convertFrom18((callAmount.multiplyDecimal(callPrice)+putAmount.multiplyDecimal(putPrice))*110/100,quoteAsset.decimals());
  }

  function deltaHedge(uint hedgeType) public override onlyVault returns (int balChange,uint[] memory positionIds) {
    //hedgeType 0:buy/sell synthetic 1:reduce bigger delta leg 
    require(activeStrikeId>0 && hasOpenPosition(),"no position to hedge");

    console.log("spot=%s/100 lastHedgSpot=%s/100",_getSpot()/10**16,lastHedgeSpot/10**16);
    uint strikePrice = oneClicks.underlierToMarket(underlier).getStrike(activeStrikeId).strikePrice;
    console.log("strikeDiff=%s/100",_abs(int(strikePrice)-int(_getSpot()))/10**16);
    console.log("strikeDiffPct=%s/10000",(_abs(int(strikePrice)-int(_getSpot())).divideDecimal(strikePrice))/10**14);

    PositionsInfo memory p =_getAllPositionsDelta();
    
    console.log("hegeType=%s",hedgeType);
    OneClicks.LegDetails[] memory legs = new OneClicks.LegDetails[](2);
    int hedgeCost18;
    int putAmount;
    int callAmount; 

    if (hedgeType==1) {
      if (p.totalDelta<0) {
        callAmount=-1*p.totalDelta.divideDecimal(p.callUnitDelta);
        console.log("---buy %s/100 call",_abs(callAmount)/10**16);
        hedgeCost18=int(p.callUnitPrice.multiplyDecimal(_abs(callAmount)).multiplyDecimal(1 ether+strategyDetail.bidAskSpread));
       } else {
        putAmount=-1*p.totalDelta.divideDecimal(p.putUnitDelta);
        console.log("---buy %s/100 call",_abs(putAmount)/10**16);
        hedgeCost18=int(p.putUnitPrice.multiplyDecimal(_abs(putAmount)).multiplyDecimal(1 ether+strategyDetail.bidAskSpread));
       }
      lastHedgeSpot=_getSpot();
      lastHedgeTimestamp=block.timestamp;
    } else {
      if (p.totalDelta<0) {
        console.log("---buy %s/100 synthetic",_abs(p.totalDelta)/10**16);
        hedgeCost18=(int(p.putUnitPrice.multiplyDecimal(1 ether-strategyDetail.bidAskSpread))-
          int(p.callUnitPrice.multiplyDecimal(1 ether+strategyDetail.bidAskSpread))).multiplyDecimal(p.totalDelta);
      } else {
        console.log("---sell %s/100 synthetic",_abs(p.totalDelta)/10**16);
        hedgeCost18=(int(p.putUnitPrice.multiplyDecimal(1 ether+strategyDetail.bidAskSpread))
          -int(p.callUnitPrice.multiplyDecimal(1 ether-strategyDetail.bidAskSpread))).multiplyDecimal(p.totalDelta);
      }
      putAmount=p.totalDelta;
      callAmount=-1*p.totalDelta;

      lastHedgeSpot=_getSpot();
      lastHedgeTimestamp=block.timestamp;
    }

    console.log("trade putAmount=%s/100 isPositive=%s",_abs(putAmount)/10**16,_isPositive(putAmount));
    console.log("trade callAmount=%s/100 isPositive=%s",_abs(callAmount)/10**16,_isPositive(callAmount));
    legs[0]=OneClicks.LegDetails(_abs(putAmount),activeStrikeId,false,_isPositive(putAmount),0);
    legs[1]=OneClicks.LegDetails(_abs(callAmount),activeStrikeId,true,_isPositive(callAmount),0);
    console.log("hedgeCost18=%s/100 isPositive=%s",_abs(hedgeCost18)/10**16,_isPositive(hedgeCost18));
    if (hedgeCost18<0) hedgeCost18=0;

    quoteAsset.transferFrom(address(vault), address(this), ConvertDecimals.convertFrom18(_abs(hedgeCost18),quoteAsset.decimals()));
    console.log("before hedge strategy quoteBal=%s/100",quoteAsset.balanceOf(address(this))/(quoteAsset.decimals()-2));
    int balBefore = int(quoteAsset.balanceOf(address(this)));
    positionIds = oneClicks.tradeOneClick('Synthetic',underlier,ConvertDecimals.convertFrom18(_abs(hedgeCost18),quoteAsset.decimals()),legs);
    balChange=int(quoteAsset.balanceOf(address(this)))-balBefore;
    console.log("after hedge strategy quoteBal=%s/100 balChange=%s/100",
      quoteAsset.balanceOf(address(this))/(quoteAsset.decimals()-2),
      _abs(balChange)/(10**(quoteAsset.decimals()-2)));
    quoteAsset.transfer(address(vault),quoteAsset.balanceOf(address(this)));
    _getAllPositionsDelta();
  }

  function reducePosition(uint closeAmount) external returns (int balChange,uint[] memory positionIds) {
    return deltaHedge(1);
  }
}

