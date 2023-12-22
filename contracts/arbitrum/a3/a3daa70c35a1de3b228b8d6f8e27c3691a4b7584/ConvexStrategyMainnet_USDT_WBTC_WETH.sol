//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_USDT_WBTC_WETH is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8e0B8c8BB9db49a46697F3a5Bb8A308e744821D2); // Info -> LP Token address
    address rewardPool = address(0xA9249f8667cb120F065D9dA1dCb37AD28E1E8FF0); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address cvx = address(0xb952A807345991BD529FDded05009F5e80Fe8F45);
    address curveDeposit = address(0x960ea3e3C7FB317332d990873d354E18d7645590); // only needed if deposits are not via underlying
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      8,  // Pool id: Info -> Rewards contract address -> read -> pid
      weth, // depositToken
      2, //depositArrayPosition. Find deposit transaction -> input params
      curveDeposit, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      3, //nTokens -> total number of deposit tokens
      false //metaPool -> if LP token address == pool address (at curve)
    );
    rewardTokens = [crv, cvx];
    reward2WETH[crv] = [crv, weth];
    reward2WETH[cvx] = [cvx, weth];
  }
}
