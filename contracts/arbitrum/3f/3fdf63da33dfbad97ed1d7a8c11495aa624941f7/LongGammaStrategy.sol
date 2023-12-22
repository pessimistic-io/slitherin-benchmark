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
    console.log("takeFromVault=%s/100",takeFromVault/(10**(quoteAsset.decimals()-2)));
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
    console.log("after trade transfer back strategy quoteBal=%s/100",
      quoteAsset.balanceOf(address(this))/(10**(quoteAsset.decimals()-2)));
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
    //amount is in 18 decimals
    uint amount18 =ConvertDecimals.convertTo18(lockedAmountLeft,quoteAsset.decimals()).divideDecimal(callPrice+putPrice).
      multiplyDecimal(strategyDetail.maxTradeUtilization);
    console.log("start with %s/100000000 straddle",amount18/10**10);
    int totalDelta = _calculateTotalDelta(strikeId, int(amount18), int(amount18));
    if (totalDelta<0) {
      console.log("putAmountMinus=%s/100000000",_abs(totalDelta.divideDecimal(strikePutDelta))/10**10);
      putAmount = amount18-_abs(totalDelta.divideDecimal(strikePutDelta));
      putAmount = amount18-uint(totalDelta.divideDecimal(strikePutDelta));
      callAmount=amount18;
      console.log("putAmount=%s/100000000",putAmount/10**10);
    } else {
      console.log("callAmountMinus=%s/100000000",uint(totalDelta.divideDecimal(strikeCallDelta))/10**10);
      callAmount = amount18-uint(totalDelta.divideDecimal(strikeCallDelta));
      putAmount=amount18;
      console.log("callAmount=%s/100000000",callAmount/10**10);
    }
    //takeFromVault uses quoteAsset decimal
    takeFromVault=ConvertDecimals.convertFrom18((callAmount.multiplyDecimal(callPrice)+
        putAmount.multiplyDecimal(putPrice))*110/100,quoteAsset.decimals());
  }

  function deltaHedge(uint hedgeType) public override onlyVault returns (int balChange,uint[] memory positionIds) {
    //hedgeType 0:buy/sell synthetic 1:reduce bigger delta leg 
    require(activeStrikeId!=0 && hasOpenPosition(),"no position to hedge");

    console.log("spot=%s/100 lastHedgSpot=%s/100",_getSpot()/10**16,lastHedgeSpot/10**16);
    uint strikePrice = oneClicks.underlierToMarket(underlier).getStrike(activeStrikeId).strikePrice;
    console.log("strikeDiff=%s/100",_abs(int(strikePrice)-int(_getSpot()))/10**16);
    console.log("strikeDiffPct=%s/10000",(_abs(int(strikePrice)-int(_getSpot())).divideDecimal(strikePrice))/10**14);

    PositionsInfo memory p =_getAllPositionsDelta();
    if (_abs(p.totalDelta)<strategyDetail.minDeltaToHedge) {
      console.log("Not enough delta(%s/100) to hedge",_abs(p.totalDelta)/10**16);
      return (int(0),positionIds);
    }
    console.log("strikeId=%s call|putPrice=%s/100|%s/100",activeStrikeId, p.callUnitPrice/10**16,p.putUnitPrice/10**16);
    console.log("            call|putDelta=%s/100000000|%s/100000000",
      uint(p.callUnitDelta)/10**10,uint(-1*p.putUnitDelta)/10**10);
    
    console.log("hegeType=%s",hedgeType);
    OneClicks.LegDetails[] memory legs;
    int hedgeCost18;
    string memory ocType;

    if (hedgeType==1) {
      legs = new OneClicks.LegDetails[](1);
      int amount;
      if (p.totalDelta<0) {
        amount=p.totalDelta.divideDecimal(p.putUnitDelta);
        console.log("---sell %s/100 put",_abs(amount)/10**16); 
      } else {
        amount=p.totalDelta.divideDecimal(p.callUnitDelta);
        console.log("---sell %s/100 call",_abs(amount)/10**16);
      }
      ocType='Single Leg';
      legs[0]=OneClicks.LegDetails(_abs(amount),activeStrikeId,p.totalDelta>0,false,0);
    } else {
      legs = new OneClicks.LegDetails[](2);
      if (p.totalDelta<0) {
        console.log("---buy %s/100 synthetic",_abs(p.totalDelta)/10**16);
        hedgeCost18=(int(p.putUnitPrice.multiplyDecimal(1 ether-strategyDetail.bidAskSpread))-
          int(p.callUnitPrice.multiplyDecimal(1 ether+strategyDetail.bidAskSpread))).multiplyDecimal(p.totalDelta);
      } else {
        console.log("---sell %s/100 synthetic",_abs(p.totalDelta)/10**16);
        hedgeCost18=(int(p.putUnitPrice.multiplyDecimal(1 ether+strategyDetail.bidAskSpread))
          -int(p.callUnitPrice.multiplyDecimal(1 ether-strategyDetail.bidAskSpread))).multiplyDecimal(p.totalDelta);
      }
      ocType='Synthetic';
      legs[0]=OneClicks.LegDetails(_abs(p.totalDelta),activeStrikeId,false,p.totalDelta>0,0);
      legs[1]=OneClicks.LegDetails(_abs(p.totalDelta),activeStrikeId,true,p.totalDelta<0,0);
    }
    lastHedgeSpot=_getSpot();
    lastHedgeTimestamp=block.timestamp;

    console.log("hedgeCost18=%s/100 isPositive=%s",_abs(hedgeCost18)/10**16,_isPositive(hedgeCost18));
    if (hedgeCost18<0) hedgeCost18=0;

    quoteAsset.transferFrom(address(vault), address(this), ConvertDecimals.convertFrom18(_abs(hedgeCost18),quoteAsset.decimals()));
    int balBefore = int(quoteAsset.balanceOf(address(this)));
    console.log("before hedge strategy quoteBal=%s/100",uint(balBefore)/10**(quoteAsset.decimals()-2));
    positionIds = oneClicks.tradeOneClick(ocType,underlier,ConvertDecimals.convertFrom18(_abs(hedgeCost18),quoteAsset.decimals()),legs);
    balChange=int(quoteAsset.balanceOf(address(this)))-balBefore;
    console.log("after hedge strategy quoteBal=%s/100 balChange=%s/100",
      quoteAsset.balanceOf(address(this))/10**(quoteAsset.decimals()-2),
      _abs(balChange)/(10**(quoteAsset.decimals()-2)));
    quoteAsset.transfer(address(vault),quoteAsset.balanceOf(address(this)));
    _getAllPositionsDelta();
  }

  function reducePosition(uint closeAmount) external returns (int balChange,uint[] memory positionIds) {
    return deltaHedge(1);
  }
}

