// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

interface IStrategyRebalanceStakerUniV3 {
  event Deposited(
    uint256 tokenId,
    uint256 token0Balance,
    uint256 token1Balance
  );
  event Harvested(uint256 tokenId);
  event InitialDeposited(uint256 tokenId);
  event Initialized(uint8 version);
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event Rebalanced(uint256 tokenId, int24 _tickLower, int24 _tickUpper);
  event Withdrawn(uint256 tokenId, uint256 _liquidity);

  function PERFORMANCE_TREASURY_MAX() external view returns (uint256);

  function adjustHarvesters(
    address[] memory _harvesters,
    bool[] memory _values
  ) external;

  function amountsForLiquid() external view returns (uint256, uint256);

  function controller() external view returns (address);

  function deposit() external;

  function determineTicks()
  external
  view
  returns (
    int24 _lowerTick,
    int24 _upperTick,
    int24 _innerLowerTick,
    int24 _innerUpperTick
  );

  function getBasisPoints() external view returns (uint256);

  function getMinLiquidity()
  external
  view
  returns (uint256 _minLiq0, uint256 _minLiq1);

  function governance() external view returns (address);

  function harvest() external;

  function harvesters(address) external view returns (bool);

  function inRangeCalc() external view returns (bool);

  function initialize(
    address _pool,
    int24 _tickRangeMultiplier,
    address _governance,
    address _strategist,
    address _controller,
    address _timelock,
    address _iUniswapCalculator
  ) external;

  function innerTickRangeMultiplier() external view returns (int24);

  function inner_tick_lower() external view returns (int24);

  function inner_tick_upper() external view returns (int24);

  function lastHarvest() external view returns (uint256);

  function liquidityOf() external view returns (uint256);

  function liquidityOfPool() external view returns (uint256);

  function liquidityOfThis() external view returns (uint256);

  function nftManager() external view returns (address);

  function onERC721Received(
    address,
    address,
    uint256,
    bytes memory
  ) external pure returns (bytes4);

  function overWriteTicks() external view returns (bool);

  function owner() external view returns (address);

  function performanceTreasuryFee() external view returns (uint256);

  function pool() external view returns (address);

  function readBalanceProportion()
  external
  view
  returns (
    uint256,
    address,
    address
  );

  function rebalance() external returns (uint256 _tokenId);

  function rebalanceVia1inch(address _oneInchRouter, bytes memory _data)
  external
  returns (uint256 _tokenId);

  function renounceOwnership() external;

  function setController(address _controller) external;

  function setGovernance(address _governance) external;

  function setPerformanceTreasuryFee(uint256 _performanceTreasuryFee)
  external;

  function setStrategist(address _strategist) external;

  function setSwapPoolFee(uint24 _swapPoolFee) external;

  function setTickRangeMultiplier(
    int24 _tickRangeMultiplier,
    int24 _innerTickRangeMultiplier
  ) external;

  function setTicks(
    int24 _tick_lower,
    int24 _tick_upper,
    int24 _inner_tick_lower,
    int24 _inner_tick_upper,
    bool _overWriteTicks
  ) external;

  function setTimelock(address _timelock) external;

  function setTwapTime(uint24 _twapTime) external;

  function strategist() external view returns (address);

  function swapPoolFee() external view returns (uint24);

  function tickRangeMultiplier() external view returns (int24);

  function tick_lower() external view returns (int24);

  function tick_upper() external view returns (int24);

  function timelock() external view returns (address);

  function token0() external view returns (address);

  function token1() external view returns (address);

  function tokenId() external view returns (uint256);

  function transferOwnership(address newOwner) external;

  function uniswapCalculator() external view returns (address);

  function uniswapQuoter() external view returns (address);

  function univ3Router() external view returns (address);

  function univ3_staker() external view returns (address);

  function withdraw(uint256 _liquidity)
  external
  returns (uint256 a0, uint256 a1);

  function withdraw(address _asset) external returns (uint256 balance);

  function withdrawAll() external returns (uint256 a0, uint256 a1);
}
