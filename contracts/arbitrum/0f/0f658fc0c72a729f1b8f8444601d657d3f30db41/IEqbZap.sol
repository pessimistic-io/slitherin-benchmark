// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IPendleRouter.sol";

interface IEqbZap {
  function zapIn(
    uint256 _pid,
    uint256 _minLpOut,
    IPendleRouter.ApproxParams calldata _guessPtReceivedFromSy,
    IPendleRouter.TokenInput calldata _input,
    bool _stake
  ) external payable;

  function withdraw(uint256 _pid, uint256 _amount) external;

  function zapOut(
    uint256 _pid,
    uint256 _amount,
    IPendleRouter.TokenOutput calldata _output,
    bool _stake
  ) external;

  function claimRewards(uint256[] calldata _pids) external;
}

