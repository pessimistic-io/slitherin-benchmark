//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./RadiantFoldStrategy.sol";

contract RadiantFoldStrategyMainnet_USDC is RadiantFoldStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address aToken = address(0x48a29E756CC1C097388f3B2f3b570ED270423b3d);
    address lendingPool = address(0xF4B1486DD74D07706052A33d31d7c0AAFD0659E1);
    address incentivesController = address(0xebC85d44cefb1293707b11f707bd3CEc34B4D5fA);
    address rdnt = address(0x3082CC23568eA640225c2467653dB90e9250AaA0);
    RadiantFoldStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      lendingPool,
      incentivesController,
      750,
      800,
      1000,
      true
    );
    rewardTokens = [rdnt];
    reward2WETH[rdnt] = [rdnt, weth];
    WETH2underlying = [weth, underlying];
    poolIds[rdnt][weth] = bytes32(0x32df62dc3aed2cd6224193052ce665dc181658410002000000000000000003bd);
  }
}
