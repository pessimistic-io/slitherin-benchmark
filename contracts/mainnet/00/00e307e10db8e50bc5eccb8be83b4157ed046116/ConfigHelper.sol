// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./ISwapRouter.sol";
import "./AlloyxConfig.sol";
import "./IAlloyxWhitelist.sol";
import "./IMintBurnableERC20.sol";
import "./ISortedGoldfinchTranches.sol";
import "./IAlloyxStakeInfo.sol";
import "./IAlloyxTreasury.sol";
import "./IAlloyxExchange.sol";
import "./IGoldfinchDesk.sol";
import "./IStakeDesk.sol";
import "./ITruefiDesk.sol";
import "./IBackerRewards.sol";
import "./IStableCoinDesk.sol";
import "./ISeniorPool.sol";
import "./IPoolTokens.sol";
import "./IManagedPortfolio.sol";
import "./IMapleDesk.sol";
import "./IPool.sol";
import "./IClearPoolDesk.sol";
import "./IRibbonDesk.sol";
import "./IRibbonLendDesk.sol";

/**
 * @title ConfigHelper
 * @notice A convenience library for getting easy access to other contracts and constants within the
 *  protocol, through the use of the AlloyxConfig contract
 * @author AlloyX
 */

library ConfigHelper {
  function treasuryAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.Treasury));
  }

  function exchangeAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.Exchange));
  }

  function configAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.Config));
  }

  function goldfinchDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.GoldfinchDesk));
  }

  function stableCoinDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.StableCoinDesk));
  }

  function stakeDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.StakeDesk));
  }

  function truefiDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.TruefiDesk));
  }

  function mapleDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.MapleDesk));
  }

  function clearPoolDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.ClearPoolDesk));
  }

  function ribbonDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.RibbonDesk));
  }

  function ribbonLendDeskAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.RibbonLendDesk));
  }

  function swapRouterAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.SwapRouter));
  }

  function mplAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.MPL));
  }

  function whitelistAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.Whitelist));
  }

  function alloyxStakeInfoAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.AlloyxStakeInfo));
  }

  function poolTokensAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.PoolTokens));
  }

  function seniorPoolAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.SeniorPool));
  }

  function sortedGoldfinchTranchesAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.SortedGoldfinchTranches));
  }

  function fiduAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.FIDU));
  }

  function gfiAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.GFI));
  }

  function usdcAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.USDC));
  }

  function wethAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.WETH));
  }

  function duraAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.DURA));
  }

  function crwnAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.CRWN));
  }

  function backerRewardsAddress(AlloyxConfig config) internal view returns (address) {
    return config.getAddress(uint256(ConfigOptions.Addresses.BackerRewards));
  }

  function getWhitelist(AlloyxConfig config) internal view returns (IAlloyxWhitelist) {
    return IAlloyxWhitelist(whitelistAddress(config));
  }

  function getTreasury(AlloyxConfig config) internal view returns (IAlloyxTreasury) {
    return IAlloyxTreasury(treasuryAddress(config));
  }

  function getExchange(AlloyxConfig config) internal view returns (IAlloyxExchange) {
    return IAlloyxExchange(exchangeAddress(config));
  }

  function getConfig(AlloyxConfig config) internal view returns (IAlloyxConfig) {
    return IAlloyxConfig(treasuryAddress(config));
  }

  function getGoldfinchDesk(AlloyxConfig config) internal view returns (IGoldfinchDesk) {
    return IGoldfinchDesk(goldfinchDeskAddress(config));
  }

  function getStableCoinDesk(AlloyxConfig config) internal view returns (IStableCoinDesk) {
    return IStableCoinDesk(stableCoinDeskAddress(config));
  }

  function getStakeDesk(AlloyxConfig config) internal view returns (IStakeDesk) {
    return IStakeDesk(stakeDeskAddress(config));
  }

  function getTruefiDesk(AlloyxConfig config) internal view returns (ITruefiDesk) {
    return ITruefiDesk(truefiDeskAddress(config));
  }

  function getMapleDesk(AlloyxConfig config) internal view returns (IMapleDesk) {
    return IMapleDesk(mapleDeskAddress(config));
  }

  function getClearPoolDesk(AlloyxConfig config) internal view returns (IClearPoolDesk) {
    return IClearPoolDesk(clearPoolDeskAddress(config));
  }

  function getRibbonDesk(AlloyxConfig config) internal view returns (IRibbonDesk) {
    return IRibbonDesk(ribbonDeskAddress(config));
  }

  function getRibbonLendDesk(AlloyxConfig config) internal view returns (IRibbonLendDesk) {
    return IRibbonLendDesk(ribbonLendDeskAddress(config));
  }

  function getAlloyxStakeInfo(AlloyxConfig config) internal view returns (IAlloyxStakeInfo) {
    return IAlloyxStakeInfo(alloyxStakeInfoAddress(config));
  }

  function getPoolTokens(AlloyxConfig config) internal view returns (IPoolTokens) {
    return IPoolTokens(poolTokensAddress(config));
  }

  function getSeniorPool(AlloyxConfig config) internal view returns (ISeniorPool) {
    return ISeniorPool(seniorPoolAddress(config));
  }

  function getSwapRouter(AlloyxConfig config) internal view returns (ISwapRouter) {
    return ISwapRouter(swapRouterAddress(config));
  }

  function getSortedGoldfinchTranches(AlloyxConfig config)
    internal
    view
    returns (ISortedGoldfinchTranches)
  {
    return ISortedGoldfinchTranches(sortedGoldfinchTranchesAddress(config));
  }

  function getFIDU(AlloyxConfig config) internal view returns (IERC20Upgradeable) {
    return IERC20Upgradeable(fiduAddress(config));
  }

  function getGFI(AlloyxConfig config) internal view returns (IERC20Upgradeable) {
    return IERC20Upgradeable(gfiAddress(config));
  }

  function getWETH(AlloyxConfig config) internal view returns (IERC20Upgradeable) {
    return IERC20Upgradeable(wethAddress(config));
  }

  function getMPL(AlloyxConfig config) internal view returns (IERC20Upgradeable) {
    return IERC20Upgradeable(mplAddress(config));
  }

  function getUSDC(AlloyxConfig config) internal view returns (IERC20Upgradeable) {
    return IERC20Upgradeable(usdcAddress(config));
  }

  function getDURA(AlloyxConfig config) internal view returns (IMintBurnableERC20) {
    return IMintBurnableERC20(duraAddress(config));
  }

  function getCRWN(AlloyxConfig config) internal view returns (IMintBurnableERC20) {
    return IMintBurnableERC20(crwnAddress(config));
  }

  function getBackerRewards(AlloyxConfig config) internal view returns (IBackerRewards) {
    return IBackerRewards(backerRewardsAddress(config));
  }

  function getPermillageDuraRedemption(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.PermillageDuraRedemption));
  }

  function getPermillageDuraToFiduFee(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.PermillageDuraToFiduFee));
  }

  function getPermillageDuraRepayment(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.PermillageDuraRepayment));
  }

  function getPermillageCRWNEarning(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.PermillageCRWNEarning));
  }

  function getPermillageJuniorRedemption(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.PermillageJuniorRedemption));
  }

  function getPermillageInvestJunior(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.PermillageInvestJunior));
  }

  function getPermillageRewardPerYear(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.PermillageRewardPerYear));
  }

  function getUniswapFeeBasePoint(AlloyxConfig config) internal view returns (uint256) {
    return config.getNumber(uint256(ConfigOptions.Numbers.UniswapFeeBasePoint));
  }

  function isPaused(AlloyxConfig config) internal view returns (bool) {
    return config.getBoolean(uint256(ConfigOptions.Booleans.IsPaused));
  }
}

