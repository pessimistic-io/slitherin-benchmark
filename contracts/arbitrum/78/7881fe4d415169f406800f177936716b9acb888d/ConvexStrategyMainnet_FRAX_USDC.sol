//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./ConvexStrategy.sol";

contract ConvexStrategyMainnet_FRAX_USDC is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xC9B8a3FDECB9D5b218d02555a8Baf332E5B740d5); // Info -> LP Token address
    address rewardPool = address(0x93729702Bf9E1687Ae2124e191B8fFbcC0C8A0B0); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address cvx = address(0xb952A807345991BD529FDded05009F5e80Fe8F45);
    address usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      10,  // Pool id: Info -> Rewards contract address -> read -> pid
      usdc, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false //metaPool -> if LP token address == pool address (at curve)
    );
    rewardTokens = [crv, cvx];
    reward2WETH[crv] = [crv, weth];
    reward2WETH[cvx] = [cvx, weth];
    WETH2deposit = [weth, usdc];
    storedPairFee[weth][usdc] = 500;
  }
}
