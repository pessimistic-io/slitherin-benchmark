//  SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.10;

import {ICToken} from "./compound_ICToken.sol";
import {IComptroller} from "./IComptroller.sol";
import {ITenderPriceOracle} from "./ITenderPriceOracle.sol";
import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {SafeMath} from "./SafeMath.sol";
import {PriceHelper} from "./PriceHelper.sol";
import {GLPHelper} from "./GLPHelper.sol";
import {Addresses} from "./Addresses.sol";

library CTokenHelper {
  using SafeMath for uint256;
  // Using this instead of reading from market since it is more gas efficient
  IComptroller public constant comptroller = IComptroller(Addresses.unitroller);

  function getCollateralFactor(ICToken cToken, address account) public view returns (uint256) {
    // we use tx.origin here in case this is called during the flashloan callback
    // since the vault has a check that msg.sender == tx.origin this is safe
    bool vip = comptroller.getIsAccountVip(account);
    (, uint256 collateralFactor,, uint256 collateralFactorVip,,,,) = comptroller.markets(address(cToken));
    return vip ? collateralFactorVip : collateralFactor;
  }

  function getLiquidationThreshold(ICToken cToken) public view returns (uint256) {
    bool vip = comptroller.getIsAccountVip(tx.origin);
    (,, uint256 liqThreshold, uint256 liqThresholdVip,,,,) = comptroller.markets(address(cToken));
    return vip ? liqThresholdVip : liqThreshold;
  }

  // 18 decimals: 1e18/result gives multiplier: (e.g. 10)
  function maxLeverageMultiplier(ICToken cToken, address account) public view returns (uint256) {
    uint256 totalValueThreshold = 1e18;
    uint256 maxValue = 1e36;
    uint256 collateralFactor = getCollateralFactor(cToken, account);
    uint256 totalValueDividend = totalValueThreshold.sub(collateralFactor);
    return maxValue.div(totalValueDividend);
  }

  function getHypotheticalLiquidity(
    ICToken market,
    address account,
    uint redeemAmount,
    uint borrowAmount
  ) public view returns (uint liquidity) {
    (,liquidity,) = comptroller.getHypotheticalAccountLiquidity(account, address(market), redeemAmount, borrowAmount, false);
  }

  function getLiquidity(address account) public view returns (uint) {
    // do not handle error because new users will revert
    (, uint liquidity, uint shortfall) = comptroller.getHypotheticalAccountLiquidity(account, address(0), 0, 0, false);
    require(shortfall == 0, "Error: shortfall detected");
    return liquidity;

  }

  function getMaxLeverageUSD(
    ICToken mintMarket,
    address account
  ) public view returns (uint) {
    uint liquidity = getLiquidity(account);
    return liquidity.mul(maxLeverageMultiplier(mintMarket, account)).div(1e18);
  }

  // returns max number of tokens supplyable from looping a given market
  function getMaxLeverageTokens(
    ICToken mintMarket,
    address account
  ) public view returns(uint) {
    uint leverageUSD = getMaxLeverageUSD(mintMarket, account);
    uint tokensPerUSD = PriceHelper.getTokensPerUSD(mintMarket.underlying());
    return tokensPerUSD.mul(leverageUSD).div(1e18);
  }

  function approveMarket(ICToken market, uint amount) internal returns (bool) {
    if(market.underlying() == GLPHelper.fsGLP) {
      return GLPHelper.stakedGlp.approve(address(market), amount);
    }
    return market.underlying().approve(address(market), amount);
  }
}

