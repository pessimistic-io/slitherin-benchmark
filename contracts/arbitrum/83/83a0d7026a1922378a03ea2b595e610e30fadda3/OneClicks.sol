// SPDX-License-Identifier: MIT
// OneClicks.sol v1.45c

pragma solidity 0.8.16;

import "./StrandsLyraAdapter.sol";

contract OneClicks is StrandsLyraAdapter {
  using DecimalMath for uint;

  event OneClicksTraded(string underlier, string oneClickName,uint totalAbsCost, uint licenseFee);

  constructor(address _lyraRegistry, bytes32 _exchangeAdapter) 
    StrandsLyraAdapter(_lyraRegistry,_exchangeAdapter){}

  //Input Leg Details
  struct LegDetails {
    uint amount;
    uint strikeId;
    bool isCall;
    bool isLong;
    uint finalPositionCollateral;  //18 decimals, not token decimals
  }

  struct AdditionalLegDetails {
    uint oldPositionId;
    uint finalPositionAmount;
    bool finalPositionIsLong;
    int additionalCollateral;
    int estPremium;
  }

  struct positionsToClose {
    string underlier;
    uint[] positionIds;
  }

  function closeSelectedPositions(positionsToClose[] memory toClose) public {
    for (uint8 i;i<toClose.length;i++) {
      closeSelectedPositionsByUnderlier(toClose[i].underlier,toClose[i].positionIds);
    }
  }

  function closeAllPositions(string[] memory underliers) public {
    for (uint8 i;i<underliers.length;i++) {
      closeAllPositionsByUnderlier(underliers[i]);
    }
  }

  function closeSelectedPositionsByUnderlier(string memory underlier, uint[] memory positionIds) public returns (uint[] memory newPositionIds)
  {
    uint8 length=uint8(positionIds.length);
    OptionToken.OptionPosition memory position;
    LegDetails[] memory legs = new LegDetails[](length);
    AdditionalLegDetails[] memory alegs = new AdditionalLegDetails[](length);
    newPositionIds = new uint[](length);
    OptionToken optionToken = OptionToken(lyraRegistry.getMarketAddresses(underlierToMarket[underlier]).optionToken);

    for(uint8 i=0;i<length;){
      position=optionToken.getOptionPosition(positionIds[i]);
      if (optionToken.ownerOf(positionIds[i])==msg.sender && positionIds[i]>0) { 
        legs[i].strikeId=position.strikeId;
        alegs[i].oldPositionId=positionIds[i];
        legs[i].isCall=StrandsUtils.isThisCall(position.optionType);
        legs[i].isLong=!StrandsUtils.isThisLong(position.optionType);
        legs[i].amount=position.amount;
        alegs[i].additionalCollateral=-1*int(position.collateral);
        if (position.amount>0) {
            //Temperarily transfer ownership of token to OneClicks contract so it can be adjusted
            optionToken.transferFrom(msg.sender,address(this), positionIds[i]);  
        }
      } 
      unchecked {i++;}
    }

    uint totalAbsCost;
    (totalAbsCost,newPositionIds) = _tradeOneClicks(underlier,legs,alegs);
    uint closeFee=ConvertDecimals.convertFrom18(Math.min(licenseFeeCap,
      totalAbsCost*closeFeeBasisPoint/10000), quoteAsset.decimals());

    // sent extra quoteAsset back to user
    quoteAsset.transfer(msg.sender, quoteAsset.balanceOf(address(this)));
    emit OneClicksTraded(underlier, "CloseAll",totalAbsCost, closeFee);
  }

  function closeAllPositionsByUnderlier(string memory underlier) public returns (uint[] memory)
  {
    OptionToken.OptionPosition[] memory ownerPositions = lyraRegistry.getMarketAddresses(
      underlierToMarket[underlier]).optionToken.getOwnerPositions(msg.sender);
    uint[] memory positionIds=new uint[](ownerPositions.length);
    for(uint8 i=0;i<ownerPositions.length;i++){
      positionIds[i]=ownerPositions[i].positionId;
    }
    return closeSelectedPositionsByUnderlier(underlier,positionIds);
  }

  function tradeOneClick(
    string memory oneClickName, 
    string memory underlier,
    uint estimatedCost, //in native decimals, eg 6 for USDC
    LegDetails[] memory inputLegs
  ) external returns (uint[] memory positionIds) {
    AdditionalLegDetails[] memory aLegs = new AdditionalLegDetails[](inputLegs.length);
    uint additionalCollateral;

    console.log("Trade %s",oneClickName);

    (additionalCollateral,aLegs) = _prepareOneClicksLegs(underlier,inputLegs);
    (inputLegs,aLegs) = reOrderLegs(inputLegs,aLegs);
    
    console.log("total diffCollateral=%s/100 (0 if <0)",additionalCollateral/10**16);
    //console.log("estCost=%s/100 (0 if <0)",estimatedCost/10**16);
    //console.log("quoteBal=%s/100",quoteAsset.balanceOf(msg.sender)/10**16);
    uint takeFromWallet =estimatedCost + ConvertDecimals.convertFrom18(additionalCollateral, quoteAsset.decimals());
    console.log("takeFromWallet=%s",takeFromWallet);

    require(quoteAsset.balanceOf(msg.sender) >= takeFromWallet,"Not enough quoteAsset");
    quoteAsset.transferFrom(msg.sender, address(this), takeFromWallet);
    
    uint totalAbsCost; //in 18 decimals
    (totalAbsCost,positionIds) = _tradeOneClicks(underlier,inputLegs,aLegs);
    uint licenseFee=ConvertDecimals.convertFrom18(Math.min(licenseFeeCap,
      totalAbsCost*licenseFeeBasisPoint/10000), quoteAsset.decimals());
    console.log("licenseFee=$%s/100",licenseFee/(quoteAsset.decimals()-2));
    quoteAsset.transfer(licenseFeeRecipient,licenseFee);
      
    // sent extra quoteAsset back to user
    quoteAsset.transfer(msg.sender, quoteAsset.balanceOf(address(this)));
    emit OneClicksTraded(underlier, oneClickName,totalAbsCost, licenseFee);
  }

  function _tradeOneClicks(string memory underlier, LegDetails[] memory legs,AdditionalLegDetails[] memory aLegs) private 
      returns (uint totalAbsCost,uint[] memory positionIds) {
    OptionMarket.Result memory result;
    OptionToken.OptionPosition memory oldPosition;
    positionIds = new uint[](legs.length);
    OptionToken optionToken=lyraRegistry.getMarketAddresses(underlierToMarket[underlier]).optionToken;

    //console.log("before trade quoteBal=%s/100",quoteAsset.balanceOf(address(this))/(10**(quoteAsset.decimals()-2)));
    for (uint8 i = 0; i < legs.length; i++) {
      OptionMarket.TradeInputParameters memory tradeParams = OptionMarket.TradeInputParameters({
        strikeId: legs[i].strikeId,
        positionId: aLegs[i].oldPositionId, 
        iterations: _getIterations(legs[i].amount,underlier),
        optionType: StrandsUtils.getLyraOptionType(legs[i].isCall,aLegs[i].finalPositionIsLong),
        amount: legs[i].amount,
        setCollateralTo: legs[i].finalPositionCollateral,
        minTotalCost: 0,
        maxTotalCost: type(uint).max,
        referrer: referralRecipient
      });
      if (aLegs[i].oldPositionId==0)  {
        //new position
        result = _openPosition(underlier,tradeParams);
      } else {
        oldPosition = optionToken.getOptionPosition(aLegs[i].oldPositionId);       
        if (StrandsUtils.isThisLong(oldPosition.optionType)==legs[i].isLong) {
          console.log("add to positionId=",tradeParams.positionId);
          result = _openPosition(underlier,tradeParams);
        } else { 
          console.log('trade %s/100 against pid=%s of %s/100',
            legs[i].amount/10**16,oldPosition.positionId,oldPosition.amount/10**16);
          if (legs[i].amount>=oldPosition.amount) {
            //new trade changes existing position's isLong
            //console.log("close positionId=",aLegs[i].oldPositionId);
            tradeParams.amount=oldPosition.amount;
            tradeParams.optionType=oldPosition.optionType;
            tradeParams.iterations= _getIterations(oldPosition.amount,underlier);
            tradeParams.setCollateralTo=0;
            result = _closePosition(underlier,tradeParams);
            //create new position with remaining amount
            tradeParams.amount=aLegs[i].finalPositionAmount;
            tradeParams.optionType=StrandsUtils.getLyraOptionType(legs[i].isCall,aLegs[i].finalPositionIsLong);
            tradeParams.positionId=0;
            if (tradeParams.amount>0) {
              console.log("setCollateralTo=%s/100 totalLyraCost|Fee=%s/100|%s/100",tradeParams.setCollateralTo/10**16,
                result.totalCost/10**16,result.totalFee/10**16);
              totalAbsCost=totalAbsCost+result.totalCost;
              console.log("open new pos /w remainder %s/100",tradeParams.amount/10**16);
              tradeParams.iterations= _getIterations(tradeParams.amount,underlier);
              tradeParams.setCollateralTo=legs[i].finalPositionCollateral;
              result = _openPosition(underlier,tradeParams);
            }
          } else { 
            console.log("partial close positionId=",aLegs[i].oldPositionId);
            tradeParams.optionType=oldPosition.optionType;
            tradeParams.amount=legs[i].amount;
            tradeParams.iterations= _getIterations(legs[i].amount,underlier);
            result = _closePosition(underlier,tradeParams);
          }
        }
        console.log("after leg %s quoteBal=%s/100",i,quoteAsset.balanceOf(address(this))/(10**(quoteAsset.decimals()-2)));
      }

      console.log("setCollateralTo=%s/100 totalLyraCost|Fee=%s/100|%s/100",tradeParams.setCollateralTo/10**16,
                result.totalCost/10**16,result.totalFee/10**16);
      totalAbsCost=totalAbsCost+result.totalCost;
      positionIds[i] = result.positionId;
      console.log("result leg pid=", result.positionId);
      //send optionToken and remaining usd back
      if (optionToken.getOptionPosition(result.positionId).amount>0) {
         optionToken.transferFrom(address(this), msg.sender, result.positionId);
      }
    }
  }

  //Calculate final position 
  function _prepareOneClicksLegs(string memory underlier,LegDetails[] memory inputLegs) private 
    returns (uint,AdditionalLegDetails[] memory aLegs) {
    int additionalCollateral;
    uint oldPositionId;  
    uint oldAmount;
    uint oldCollateral;
    uint optionPrice;
    bool oldIsLong;
    OptionMarket market=underlierToMarket[underlier];
    aLegs = new AdditionalLegDetails[](inputLegs.length);

    for(uint8 i=0; i<inputLegs.length;i++) {
      console.log("legs[%s] amount=%s/100 strikeId=%s",i,inputLegs[i].amount/10**16,inputLegs[i].strikeId);
      console.log("         isLong=%s isCall=%s",inputLegs[i].isLong,inputLegs[i].isCall);
      (oldPositionId,oldAmount,oldIsLong,oldCollateral) = getExistingPosition(underlier,inputLegs[i].strikeId,inputLegs[i].isCall);
       //using default for finalPositionIsLong, finalPositionAmount,additionalCollateral
      aLegs[i]=AdditionalLegDetails(oldPositionId,inputLegs[i].amount,inputLegs[i].isLong,int(inputLegs[i].finalPositionCollateral),0); 
      if (oldPositionId>0) {
        if (oldIsLong==inputLegs[i].isLong) {
          //add to existing position
          aLegs[i].finalPositionAmount=inputLegs[i].amount+oldAmount;
        } else {
          // Handle collateral of opposite side
          if (inputLegs[i].amount>=oldAmount) {
            //new trade changes existing position's isLong
            aLegs[i].finalPositionAmount=inputLegs[i].amount-oldAmount;
            aLegs[i].finalPositionIsLong=!oldIsLong;
          } else { 
            aLegs[i].finalPositionAmount=oldAmount-inputLegs[i].amount;
            aLegs[i].finalPositionIsLong=oldIsLong;
          }
        }
      }
      if (aLegs[i].finalPositionIsLong) inputLegs[i].finalPositionCollateral=0;
      aLegs[i].additionalCollateral=int(inputLegs[i].finalPositionCollateral)-int(oldCollateral);
      
      if (inputLegs[i].isCall) (optionPrice,) = getOptionPrices(underlier,inputLegs[i].strikeId);
      else (,optionPrice) = getOptionPrices(underlier,inputLegs[i].strikeId);
      aLegs[i].estPremium=int(inputLegs[i].amount.multiplyDecimal(optionPrice));
      if (!inputLegs[i].isLong) aLegs[i].estPremium=-1*aLegs[i].estPremium;
      
      console.log("legs[%s].estPremium=$%s/100 >0?%s",i, _abs(aLegs[i].estPremium)/10**16,_isPositive(aLegs[i].estPremium));
      console.log("legs[%s] finalPosositionCollat=$%s/100",i,inputLegs[i].finalPositionCollateral/10**16);
      console.log("legs[%s] diffCollat=$%s/100 >0?%s",i,
        _abs(aLegs[i].additionalCollateral)/10**16,_isPositive(aLegs[i].additionalCollateral));
      require(inputLegs[i].finalPositionCollateral>=getMinCollateralForStrike(underlier,inputLegs[i].isCall,
        aLegs[i].finalPositionIsLong,inputLegs[i].strikeId,aLegs[i].finalPositionAmount),'Min Collateral not met'); 
      additionalCollateral=additionalCollateral+aLegs[i].additionalCollateral;

      //After checking positionID
      if (oldPositionId>0 && oldAmount>0) {
        //Temperarily transfer ownership of token to OneClicks contract so it can be adjusted
        lyraRegistry.getMarketAddresses(market).optionToken.transferFrom(msg.sender,address(this), aLegs[i].oldPositionId);  
      }
    }
    if (additionalCollateral>0) return (uint(additionalCollateral),aLegs);
    else return (0,aLegs);
  }

  function _isPositive(int signedInt) internal pure returns (bool) {
    if (signedInt<0) {return false;} else {return true;}
  }

  //Reducing long leg (credit event) should always go first
  function reOrderLegs(LegDetails[] memory inputLegs, AdditionalLegDetails[] memory aLegs) private view
      returns (LegDetails[] memory, AdditionalLegDetails[] memory) {
    for (uint8 i=0;i<inputLegs.length-1;i++) {
      if (aLegs[i].additionalCollateral+aLegs[i].estPremium>0 && aLegs[i].additionalCollateral+aLegs[i].estPremium>
          aLegs[i+1].additionalCollateral+aLegs[i+1].estPremium) {
        //console.log("leg %s additionalCollateral=%s/100",i+1,_abs(aLegs[i+1].additionalCollateral)/10**16);
        //console.log("isPositive=%s",_isPositive(aLegs[i+1].additionalCollateral));
        console.log("swap leg %s with leg %s",i,i+1);
        (inputLegs[i],inputLegs[i+1])=(inputLegs[i+1],inputLegs[i]);
        (aLegs[i],aLegs[i+1])=(aLegs[i+1],aLegs[i]);
        return reOrderLegs(inputLegs,aLegs);
      }
    }
    return (inputLegs,aLegs);
  }

}

