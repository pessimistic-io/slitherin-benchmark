// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./StrategyRebalanceStakerUniV3.sol";

contract StrategyUniV3Staker is StrategyRebalanceStakerUniV3 {
  address private privPool;
  string private name;

  constructor(
    int24 _tickRangeMultiplier,
    address _governance,
    address _strategist,
    address _controller,
    address _timelock,
    address _privPool,
    string memory _name
  )
    public
    StrategyRebalanceStakerUniV3(_privPool, _tickRangeMultiplier, _governance, _strategist, _controller, _timelock)
  {
    univ3_staker = 0xe34139463bA50bD61336E0c446Bd8C0867c6fE65;
    privPool = _privPool;
    name = _name;
  }

  function getName() external view override returns (string memory) {
    return name;
  }
}

