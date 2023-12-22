// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IGMXRewardRouterHandler {
  function handleRewards(
    bool _shouldClaimGmx,
    bool _shouldStakeGmx,
    bool _shouldClaimEsGmx,
    bool _shouldStakeEsGmx,
    bool _shouldStakeMultiplierPoints,
    bool _shouldClaimWeth,
    bool _shouldConvertWethToEth
  ) external;

  function signalTransfer(address _receiver) external;
}

