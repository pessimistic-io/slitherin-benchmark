//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {OptionMarket} from "./OptionMarket.sol";
import {BlackScholes,DecimalMath} from "./BlackScholes.sol";
import {BaseExchangeAdapter} from "./BaseExchangeAdapter.sol";

import {console} from "./console.sol";

library StrandsUtils {
    using DecimalMath for uint;
    using BlackScholes for BlackScholes.BlackScholesInputs;

  function getLyraOptionType(bool isCall, bool isLong) public pure returns (OptionMarket.OptionType ot) {
    if (isCall && !isLong) return OptionMarket.OptionType.SHORT_CALL_QUOTE;
    else if (!isCall && !isLong) return OptionMarket.OptionType.SHORT_PUT_QUOTE;
    else if (isCall && isLong) return OptionMarket.OptionType.LONG_CALL;
    else if (!isCall && isLong) return OptionMarket.OptionType.LONG_PUT;
  }

  function getDeltas(OptionMarket market, BaseExchangeAdapter exchangeAdapter,
      uint strikeId) public view returns (int,int) {
    uint spot = exchangeAdapter.getSpotPriceForMarket(address(market),BaseExchangeAdapter.PriceType.REFERENCE);
    
    (OptionMarket.Strike memory strike, OptionMarket.OptionBoard memory board) = 
      market.getStrikeAndBoard(strikeId);
        BlackScholes.BlackScholesInputs memory bsInput = BlackScholes.BlackScholesInputs({
      timeToExpirySec: board.expiry - block.timestamp,
      volatilityDecimal: board.iv.multiplyDecimal(strike.skew),
      spotDecimal: spot,
      strikePriceDecimal: strike.strikePrice,
      rateDecimal: exchangeAdapter.rateAndCarry(address(market))
    });
    return BlackScholes.delta(bsInput); //(callDelta, putDelta);
  }

  function getOptionPrices(OptionMarket market, BaseExchangeAdapter exchangeAdapter,
      uint strikeId) public view returns (uint, uint) {
    uint spot = exchangeAdapter.getSpotPriceForMarket(address(market),BaseExchangeAdapter.PriceType.REFERENCE);
    
    (OptionMarket.Strike memory strike, OptionMarket.OptionBoard memory board) = 
      market.getStrikeAndBoard(strikeId);
    
    (uint callPrice,uint putPrice) = BlackScholes.BlackScholesInputs({
      timeToExpirySec: board.expiry - block.timestamp,
      volatilityDecimal: board.iv.multiplyDecimal(strike.skew),
      spotDecimal: spot,
      strikePriceDecimal: strike.strikePrice,
      rateDecimal:exchangeAdapter.rateAndCarry(address(market))
    }).optionPrices();
    return (callPrice,putPrice);
    //return BlackScholes.optionPrices(bsInput);
  }

  function isThisCall(OptionMarket.OptionType optionType) public pure returns (bool) {
    return optionType==OptionMarket.OptionType.LONG_CALL || optionType==OptionMarket.OptionType.SHORT_CALL_QUOTE;
  }

  /// @dev Check if position is long
  function isThisLong(OptionMarket.OptionType optionType) public pure returns (bool) {
    return optionType==OptionMarket.OptionType.LONG_CALL || optionType==OptionMarket.OptionType.LONG_PUT;
  }

  function getStrikeIV(OptionMarket market,uint strikeId) public view returns (uint iv) {
    (OptionMarket.Strike memory strike, OptionMarket.OptionBoard memory board) = 
      market.getStrikeAndBoard(strikeId);
      iv = board.iv.multiplyDecimal(strike.skew);
  }

}
