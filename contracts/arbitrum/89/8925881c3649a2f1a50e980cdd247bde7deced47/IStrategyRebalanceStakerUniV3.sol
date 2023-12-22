// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IStrategyRebalanceStakerUniV3 {
  event Deposited(uint256 tokenId, uint256 token0Balance, uint256 token1Balance);
  event Harvested(uint256 tokenId);
  event InitialDeposited(uint256 tokenId);
  event Rebalanced(uint256 tokenId, int24 _tickLower, int24 _tickUpper);
  event Withdrawn(uint256 tokenId, uint256 _liquidity);

  function MAX_PERFORMANCE_TREASURY_FEE() external view returns (uint256);

  function amountsForLiquid() external view returns (uint256, uint256);

  function controller() external view returns (address);

  function deposit() external;

  function determineTicks() external view returns (int24, int24);

  function execute(address _target, bytes memory _data) external payable returns (bytes memory response);

  function getBasisPoints() external view returns (uint256);

  function getHarvestable() external returns (uint256, uint256);

  function getName() external view returns (string memory);

  function governance() external view returns (address);

  function harvest() external;

  function harvesters(address) external view returns (bool);

  function inRangeCalc() external view returns (bool);

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

  function performanceTreasuryFee() external view returns (uint256);

  function performanceTreasuryMax() external view returns (uint256);

  function pool() external view returns (address);

  function rebalance() external returns (uint256 _tokenId);

  function revokeHarvesters(address[] memory _harvesters) external;

  function setController(address _controller) external;

  function setGovernance(address _governance) external;

  function setPerformanceTreasuryFee(uint256 _performanceTreasuryFee) external;

  function setStrategist(address _strategist) external;

  function setSwapPoolFee(uint24 _swapPoolFee) external;

  function setTickRangeMultiplier(int24 _tickRangeMultiplier) external;

  function setTimelock(address _timelock) external;

  function setTwapTime(uint24 _twapTime) external;

  function strategist() external view returns (address);

  function swapPoolFee() external view returns (uint24);

  function tick_lower() external view returns (int24);

  function tick_upper() external view returns (int24);

  function timelock() external view returns (address);

  function token0() external view returns (address);

  function token1() external view returns (address);

  function tokenId() external view returns (uint256);

  function univ3Router() external view returns (address);

  function univ3_staker() external view returns (address);

  function whitelistHarvesters(address[] memory _harvesters) external;

  function withdraw(uint256 _liquidity) external returns (uint256 a0, uint256 a1);

  function withdraw(address _asset) external returns (uint256 balance);

  function withdrawAll() external returns (uint256 a0, uint256 a1);
}

