// SPDX-License-Identifier: AGPL-3.0
pragma solidity =0.8.7;

import {ICollateral, ILongShortToken, IPrePOMarket} from "./IPrePOMarket.sol";
import {ISwapRouter} from "./ISwapRouter.sol";

interface IArbitrageBroker {
  struct OffChainTradeParams {
    uint256 deadline;
    uint256 longShortAmount;
    uint256 collateralLimitForLong;
    uint256 collateralLimitForShort;
  }

  event ArbitrageProfit(
    address indexed market,
    bool indexed minting,
    uint256 profits
  );

  error InvalidMarket(address market);
  error UnprofitableTrade(uint256 balanceBefore, uint256 balanceAfter);

  function buyAndRedeem(
    IPrePOMarket market,
    OffChainTradeParams calldata tradeParams
  )
    external
    returns (
      uint256 profit,
      uint256 collateralToBuyLong,
      uint256 collateralToBuyShort
    );

  function mintAndSell(
    IPrePOMarket market,
    OffChainTradeParams calldata tradeParams
  )
    external
    returns (
      uint256 profit,
      uint256 collateralFromSellingLong,
      uint256 collateralFromSellingShort
    );

  function getCollateral() external view returns (ICollateral);

  function getSwapRouter() external view returns (ISwapRouter);

  function POOL_FEE_TIER() external view returns (uint24);

  function BUY_AND_REDEEM_ROLE() external view returns (bytes32);

  function MINT_AND_SELL_ROLE() external view returns (bytes32);

  function SET_ACCOUNT_LIST_ROLE() external view returns (bytes32);

  function WITHDRAW_ERC20_ROLE() external view returns (bytes32);
}

