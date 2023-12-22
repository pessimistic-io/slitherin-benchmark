// SPDX-License-Identifier: MIT
// OneClicks.sol v1.43

pragma solidity 0.8.16;

import "./StrandsLyraAdapter.sol";

contract OneClicks is StrandsLyraAdapter {
  mapping (string => bool[]) legsSetup;

  event OneClicksTraded(string underlier, string oneClickName,uint totalAbsCost, uint licenseFee);

  constructor() StrandsLyraAdapter() {}

  //Input Leg Details
  struct LegDetails {
    uint amount;
    uint strikeId;
    bool isCall;
    bool isLong;
    uint collateral;
  }

  struct AdditionalLegDetails {
    uint oldPositionId;
    uint finalPositionAmount;
    uint finalPositionCollateral;
    bool finalPositionIsLong;
    int additionalCollateral;
  }

  struct positionsToClose {
    string underlier;
    uint[] positionIds;
  }

  function closeSelectedPositions(positionsToClose[] memory toClose) public {
    for (uint i;i<toClose.length;i++) {
      closeSelectedPositionsByUnderlier(toClose[i].underlier,toClose[i].positionIds);
    }
  }

  function closeAllPositions(string[] memory underliers) public {
    for (uint i;i<underliers.length;i++) {
      closeAllPositionsByUnderlier(underliers[i]);
    }
  }

  function closeSelectedPositionsByUnderlier(string memory underlier, uint[] memory positionIds) public returns (uint[] memory)
  {
    uint8 length=uint8(positionIds.length);
    OptionToken.OptionPosition memory position;
    LegDetails[] memory legs = new LegDetails[](length);
    AdditionalLegDetails[] memory alegs = new AdditionalLegDetails[](length);
    uint[] memory newPositionIds = new uint[](length);
    OptionToken optionToken = marketToToken[underlierToMarket[underlier]];

    for(uint8 i=0;i<length;){
      position=optionToken.getOptionPosition(positionIds[i]);
      if (optionToken.ownerOf(positionIds[i])==msg.sender && positionIds[i]>0) { 
        legs[i].strikeId=position.strikeId;
        alegs[i].finalPositionCollateral=0;
        alegs[i].oldPositionId=positionIds[i];
        legs[i].isCall=StrandsUtils.isThisCall(position.optionType);
        legs[i].isLong=!StrandsUtils.isThisLong(position.optionType);
        legs[i].collateral=0;
        legs[i].amount=position.amount;
        alegs[i].finalPositionCollateral=0;
        alegs[i].finalPositionAmount=0;
        if (position.amount>0) {
            //Temperarily transfer ownership of token to OneClicks contract so it can be adjusted
            optionToken.transferFrom(msg.sender,address(this), positionIds[i]);  
        }
      } 
      unchecked {i++;}
    }

    uint totalAbsCost;
    (totalAbsCost,newPositionIds) = _tradeOneClicks(underlier,legs,alegs);  
    uint closeFee=Math.min(licenseFeeCap,totalAbsCost*closeFeeBasisPoint/10000);
    //quoteAsset.transfer(licenseFeeRecipient,closeFee);
      
    // sent extra sUSD back to user
    quoteAsset.transfer(msg.sender, quoteAsset.balanceOf(address(this)));
    emit OneClicksTraded(underlier, "CloseAll",totalAbsCost, closeFee);
    return newPositionIds;
  }

  function closeAllPositionsByUnderlier(string memory underlier) public returns (uint[] memory)
  {
    OptionToken.OptionPosition[] memory ownerPositions = marketToToken[underlierToMarket[underlier]].getOwnerPositions(msg.sender);
    uint[] memory positionIds=new uint[](ownerPositions.length);
    for(uint i=0;i<ownerPositions.length;i++){
      positionIds[i]=ownerPositions[i].positionId;
    }
    return closeSelectedPositionsByUnderlier(underlier,positionIds);
  }

  function tradeOneClick(
    string memory oneClickName, 
    string memory underlier,
    uint estimatedCost, 
    LegDetails[] memory inputLegs
  ) external returns (uint[] memory positionIds) {
    AdditionalLegDetails[] memory aLegs = new AdditionalLegDetails[](inputLegs.length);
    uint additionalCollateral;
    positionIds = new uint[](inputLegs.length);

    console.log("Trade %s",oneClickName);

    if (keccak256(abi.encodePacked(oneClickName))!=keccak256(abi.encodePacked('UDS'))) {
      require(legsSetup[oneClickName].length>0,'oneClick name not in allowed list');

      bool[] memory legsIsCall=legsSetup[oneClickName];
      require(inputLegs.length==legsIsCall.length,'Incorrect number of legs');

      //Todo: more strict setup check with isLong in additional to isCall
      for(uint i=0; i<inputLegs.length;i++) {
        require(inputLegs[i].isCall==legsIsCall[i],'Legs dont match specs');
      }
    }

    (additionalCollateral,aLegs) = _prepareOneClicksLegs(underlier,inputLegs);
    (inputLegs,aLegs) = reOrderLegs(inputLegs,aLegs);
    
    //console.log("additionalCollateral=%s/100",additionalCollateral/10**16);
    require(quoteAsset.balanceOf(msg.sender) >= estimatedCost + additionalCollateral, "Not enough quote asset in wallet");
    //Transfer estimatedCost from user
    quoteAsset.transferFrom(msg.sender, address(this), estimatedCost + additionalCollateral);
    
    uint totalAbsCost;
    (totalAbsCost,positionIds) = _tradeOneClicks(underlier,inputLegs,aLegs);
    uint licenseFee=Math.min(licenseFeeCap,totalAbsCost*licenseFeeBasisPoint/10000);
    console.log("licenseFee=$%s/10000",licenseFee/10**14);
    //quoteAsset.transfer(licenseFeeRecipient,licenseFee);
      
    // sent extra sUSD back to user
    quoteAsset.transfer(msg.sender, quoteAsset.balanceOf(address(this)));
    emit OneClicksTraded(underlier, oneClickName,totalAbsCost, licenseFee);
    return positionIds;
  }

  function _tradeOneClicks(string memory underlier, LegDetails[] memory legs,AdditionalLegDetails[] memory aLegs) private 
      returns (uint,uint[] memory) {
    OptionMarket.Result memory result;
    OptionToken.OptionPosition memory oldPosition;
    OptionToken optionToken=marketToToken[underlierToMarket[underlier]];
    uint[] memory positionIds = new uint[](legs.length);
    uint totalAbsCost;

    for (uint i = 0; i < legs.length; i++) {
      OptionMarket.TradeInputParameters memory tradeParams = OptionMarket.TradeInputParameters({
        strikeId: legs[i].strikeId,
        positionId: aLegs[i].oldPositionId, 
        iterations: _getIterations(legs[i].amount),
        optionType: StrandsUtils.getLyraOptionType(legs[i].isCall,aLegs[i].finalPositionIsLong),
        amount: legs[i].amount,
        setCollateralTo: aLegs[i].finalPositionCollateral,
        minTotalCost: 0,
        maxTotalCost: type(uint).max,
        referrer: msg.sender
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
          console.log('trade opposite side against old position id=%s amount=%s/100',oldPosition.positionId,oldPosition.amount/10**16);
          if (legs[i].amount>=oldPosition.amount) {
            //new trade changes existing position's isLong
            console.log("close positionId=",aLegs[i].oldPositionId);
            tradeParams.amount=oldPosition.amount;
            tradeParams.optionType=oldPosition.optionType;
            tradeParams.iterations= _getIterations(oldPosition.amount);
            tradeParams.setCollateralTo=0;
            result = _closePosition(underlier,tradeParams);
            //create new position with remaining amount
            tradeParams.amount=aLegs[i].finalPositionAmount;
            tradeParams.optionType=StrandsUtils.getLyraOptionType(legs[i].isCall,aLegs[i].finalPositionIsLong);
            tradeParams.positionId=0;
            if (tradeParams.amount>0) {
              console.log("setCollateralTo=%s/100 totalLyraCost=%s/100 totalLyraFee=%s/100",tradeParams.setCollateralTo/10**16,
                result.totalCost/10**16,result.totalFee/10**16);
              totalAbsCost=totalAbsCost+result.totalCost;
              console.log("open new position with remainder amount=%s/100",tradeParams.amount/10**16);
              tradeParams.iterations= _getIterations(tradeParams.amount);
              tradeParams.setCollateralTo=aLegs[i].finalPositionCollateral;
              result = _openPosition(underlier,tradeParams);
            }
          } else { 
            console.log("partial close positionId=",aLegs[i].oldPositionId);
            tradeParams.optionType=oldPosition.optionType;
            tradeParams.amount=legs[i].amount;
            tradeParams.iterations= _getIterations(legs[i].amount);
            result = _closePosition(underlier,tradeParams);
          }
        }
      }

      console.log("setCollateralTo=%s/100 totalLyraCost=%s/100 totalLyraFee=%s/100",tradeParams.setCollateralTo/10**16,
                result.totalCost/10**16,result.totalFee/10**16);
      totalAbsCost=totalAbsCost+result.totalCost;
      positionIds[i] = result.positionId;
      console.log("result leg positionId=", result.positionId);
      //send optionToken and remaining usd back
      if (optionToken.getOptionPosition(result.positionId).amount>0) {
         optionToken.transferFrom(address(this), msg.sender, result.positionId);
      }
    }
    return (totalAbsCost,positionIds);
  }

  //Calculate final position 
  function _prepareOneClicksLegs(string memory underlier,LegDetails[] memory inputLegs) private 
    returns (uint,AdditionalLegDetails[] memory aLegs) {
    int additionalCollateral;
    uint oldPositionId;  
    OptionToken.OptionPosition memory oldPosition;
    OptionMarket market=underlierToMarket[underlier];
    OptionToken token=marketToToken[market];
    aLegs = new AdditionalLegDetails[](inputLegs.length);

    for(uint i=0; i<inputLegs.length;i++) {
      console.log("legs[%s] amount=%s/100 strikeId=%s",i,inputLegs[i].amount/10**16,inputLegs[i].strikeId);
      console.log("         isLong=%s isCall=%s",inputLegs[i].isLong,inputLegs[i].isCall);
      (oldPositionId,,,) = getExistingPosition(underlier,inputLegs[i].strikeId,inputLegs[i].isCall);
       //using default for finalPositionIsLong, finalPositionAmount, finalPositionCollateral, additionalCollateral... 
       //may change later
      aLegs[i]=AdditionalLegDetails(oldPositionId,inputLegs[i].amount,inputLegs[i].collateral,inputLegs[i].isLong,0); 
      if (oldPositionId>0) {
        oldPosition=token.getOptionPosition(oldPositionId);
        if (StrandsUtils.isThisLong(oldPosition.optionType)==inputLegs[i].isLong) {
          //add to existing position
          aLegs[i].finalPositionCollateral=oldPosition.collateral+inputLegs[i].collateral;
          aLegs[i].finalPositionAmount=inputLegs[i].amount+oldPosition.amount;
        } else {
          // Handle collateral of opposite side
          if (inputLegs[i].amount>=oldPosition.amount) {
            //new trade changes existing position's isLong
            aLegs[i].finalPositionAmount=inputLegs[i].amount-oldPosition.amount;
            aLegs[i].finalPositionIsLong=!StrandsUtils.isThisLong(oldPosition.optionType);
            if (!aLegs[i].finalPositionIsLong) {   
              aLegs[i].finalPositionCollateral=_prorateCollateral(market,inputLegs[i].isCall,
                aLegs[i].finalPositionAmount,inputLegs[i].amount,inputLegs[i].collateral,inputLegs[i].strikeId);
            }
          } else { 
            aLegs[i].finalPositionAmount=oldPosition.amount-inputLegs[i].amount;
            aLegs[i].finalPositionIsLong=StrandsUtils.isThisLong(oldPosition.optionType);
            if (!aLegs[i].finalPositionIsLong) {
              aLegs[i].finalPositionCollateral=_prorateCollateral(market,inputLegs[i].isCall,
                oldPosition.amount-inputLegs[i].amount,oldPosition.amount,oldPosition.collateral,inputLegs[i].strikeId);
            }
          }
        }
      } else if (!inputLegs[i].isCall && !aLegs[i].finalPositionIsLong) {
        //Reduce exessive short put collateral if neccesary
        aLegs[i].finalPositionCollateral=_checkCollateralBounds(market,inputLegs[i].isCall,
          aLegs[i].finalPositionAmount,aLegs[i].finalPositionCollateral,inputLegs[i].strikeId);
      }
      if (aLegs[i].finalPositionIsLong || aLegs[i].finalPositionAmount==0) aLegs[i].finalPositionCollateral=0;
      
      console.log("post prepare leg[%s].finalPostionCollateral=$%s/100",i,aLegs[i].finalPositionCollateral/10**16);
      require(aLegs[i].finalPositionCollateral>=getMinCollateralForStrike(underlier,inputLegs[i].isCall,
        aLegs[i].finalPositionIsLong,inputLegs[i].strikeId,aLegs[i].finalPositionAmount),'Min Collateral not met'); 
      aLegs[i].additionalCollateral=int(aLegs[i].finalPositionCollateral)-int(oldPosition.collateral);
      additionalCollateral=additionalCollateral+aLegs[i].additionalCollateral;

      //After checking positionID
      if (oldPositionId>0 && oldPosition.amount>0) {
        //Temperarily transfer ownership of token to OneClicks contract so it can be adjusted
        marketToToken[market].transferFrom(msg.sender,address(this), aLegs[i].oldPositionId);  
      }
    }
    if (additionalCollateral>0) return (uint(additionalCollateral),aLegs);
    else return (0,aLegs);
  }

  //Reducing long leg (credit event) should always go first
  function reOrderLegs(LegDetails[] memory inputLegs, AdditionalLegDetails[] memory aLegs) private view
    returns (LegDetails[] memory, AdditionalLegDetails[] memory) {
    for (uint i=0;i<inputLegs.length-1;i++) {
      if (aLegs[i].additionalCollateral>0 && aLegs[i].additionalCollateral>aLegs[i+1].additionalCollateral) {
        LegDetails memory inputLegs0=inputLegs[i];
        AdditionalLegDetails memory aLegs0=aLegs[i];
        console.log("swap leg %s with leg %s",i,i+1);
        inputLegs[i]=inputLegs[i+1];
        aLegs[i]=aLegs[i+1];
        inputLegs[i+1]=inputLegs0;
        aLegs[i+1]=aLegs0;
        return reOrderLegs(inputLegs,aLegs);
      }
    }
    return (inputLegs,aLegs);
  }

  function addStrategy(string memory oneClickName,bool[] memory legsIsCall) external onlyAdmins {
    legsSetup[oneClickName]=legsIsCall;
  }

  function deleteStrategy(string memory oneClickName) external onlyAdmins {
    delete legsSetup[oneClickName];
  }


}

