pragma solidity ^0.8.0;

import "./IStrategyRebalanceStakerUniV3.sol";
import "./IUniV3Rebalancer.sol";
import "./IUniswapV3Pool.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

contract UniV3Rebalancer is OwnableUpgradeable, IUniV3Rebalancer {
  address[] public dysonPools;
  mapping(address => bool) public uniPoolCheck;
  mapping(address => bool) public harvesters;

  int24 public thresholdMulti;
  int24 public constant THRESHOLD_MULTI_MAX = 100;

  struct DysonPoolData {
    int24 tickLower;
    int24 tickUpper;
    int24 tickLowerThreshold;
    int24 tickUpperThreshold;
  }

  mapping(address => DysonPoolData) public dysonPoolData;

  // **** Modifiers **** //

  modifier onlyBenevolent() {
    require(harvesters[msg.sender] || msg.sender == owner());
    _;
  }

  function initialize() public initializer {
    __Ownable_init();
  }

  /**
   * @notice  Rebalances all pools, if condition applies
   *          if no pool is to be re-balanced, send revert
   *          to save gas of the execution
   * @dev     Simsala
   */
  function rebalancePools() public onlyBenevolent {
    uint256 k;
    for (uint256 i = 0; i < dysonPools.length; i++) {
      IStrategyRebalanceStakerUniV3 dysonStrategy = IStrategyRebalanceStakerUniV3(dysonPools[i]);
      IUniswapV3Pool uniPool = IUniswapV3Pool(dysonStrategy.pool());

      if (!_inRangeCalc(dysonStrategy, uniPool)) {
        dysonStrategy.rebalance();
        k++;
      }
    }

    require(k > 0, "no pools to re-balance");
  }

  /**
   * @notice Harvests all Dyson pools that haven't been harvested in the past day
   *
   * @dev This function iterates through all the Dyson pools and calls the `harvest` function
   * on each of them if it hasn't been called in the past day.
   */
  function harvest() public onlyBenevolent {
    uint256 k;
    for (uint256 i = 0; i < dysonPools.length; i++) {
      IStrategyRebalanceStakerUniV3 dysonStrategy = IStrategyRebalanceStakerUniV3(dysonPools[i]);

      if (block.timestamp > dysonStrategy.lastHarvest() + 1 days) {
        dysonStrategy.harvest();
        k++;
      }
    }

    require(k > 0, "no pools to harvest");
  }

  /**
   * @notice  Rebalances all pools within threshold, if condition applies
   *          if no pool is to be re-balanced, send revert
   *          to save gas of the execution
   * @dev     Simsala
   */
  function thresholdRebalancePools() public onlyBenevolent {
    uint256 k;
    for (uint256 i = 0; i < dysonPools.length; i++) {
      IStrategyRebalanceStakerUniV3 dysonStrategy = IStrategyRebalanceStakerUniV3(dysonPools[i]);
      if (dysonStrategy.swapPoolFee() < 500) continue;
      IUniswapV3Pool uniPool = IUniswapV3Pool(dysonStrategy.pool());
      DysonPoolData memory dysonPool = dysonPoolData[dysonPools[i]];
      (int24 _lower, int24 _upper) = dysonStrategy.determineTicks();
      (, int24 currentTick, , , , , ) = uniPool.slot0();

      // calculate the difference between the ticks
      dysonPool.tickLower = _lower;
      dysonPool.tickUpper = _upper;

      dysonPool.tickLowerThreshold = _lower + (((currentTick - _lower) * (THRESHOLD_MULTI_MAX - thresholdMulti)) / 100);
      dysonPool.tickUpperThreshold = _upper - (((_upper - currentTick) * (THRESHOLD_MULTI_MAX - thresholdMulti)) / 100);

      if (!_inThresholdCalc(currentTick, dysonPool)) {
        dysonPoolData[dysonPools[i]] = dysonPool;
        dysonStrategy.rebalance();
        k++;
      }
    }

    require(k > 0, "no pools to re-balance");
  }

  /**
   * @notice  Overwrites all values inside the dysonPoolData and re-balances all pools
   * @dev     Simsala
   */
  function overwriteRebalancePools() public onlyBenevolent {
    uint256 k;
    for (uint256 i = 0; i < dysonPools.length; i++) {
      IStrategyRebalanceStakerUniV3 dysonStrategy = IStrategyRebalanceStakerUniV3(dysonPools[i]);
      if (dysonStrategy.swapPoolFee() < 500) continue;
      IUniswapV3Pool uniPool = IUniswapV3Pool(dysonStrategy.pool());
      DysonPoolData memory dysonPool = dysonPoolData[dysonPools[i]];
      (int24 _lower, int24 _upper) = dysonStrategy.determineTicks();
      (, int24 currentTick, , , , , ) = uniPool.slot0();

      // calculate the difference between the ticks
      dysonPool.tickLower = _lower;
      dysonPool.tickUpper = _upper;

      dysonPool.tickLowerThreshold = _lower + (((currentTick - _lower) * (THRESHOLD_MULTI_MAX - thresholdMulti)) / 100);
      dysonPool.tickUpperThreshold = _upper - (((_upper - currentTick) * (THRESHOLD_MULTI_MAX - thresholdMulti)) / 100);

      dysonPoolData[dysonPools[i]] = dysonPool;
      dysonStrategy.rebalance();
      k++;
    }
  }

  /**
   * @notice  Overwrites all values inside the dysonPoolData and re-balances all pools
   * @dev     Simsala
   */
  function overwriteRebalancePools(address dysonPool) public onlyBenevolent {
    for (uint256 i = 0; i < dysonPools.length; i++) {
      if (dysonPools[i] != dysonPool) continue;
      IStrategyRebalanceStakerUniV3 dysonStrategy = IStrategyRebalanceStakerUniV3(dysonPools[i]);
      IUniswapV3Pool uniPool = IUniswapV3Pool(dysonStrategy.pool());
      DysonPoolData memory dysonPool = dysonPoolData[dysonPools[i]];
      (int24 _lower, int24 _upper) = dysonStrategy.determineTicks();
      (, int24 currentTick, , , , , ) = uniPool.slot0();

      // calculate the difference between the ticks
      dysonPool.tickLower = _lower;
      dysonPool.tickUpper = _upper;

      dysonPool.tickLowerThreshold = _lower + (((currentTick - _lower) * (THRESHOLD_MULTI_MAX - thresholdMulti)) / 100);
      dysonPool.tickUpperThreshold = _upper - (((_upper - currentTick) * (THRESHOLD_MULTI_MAX - thresholdMulti)) / 100);

      dysonPoolData[dysonPools[i]] = dysonPool;
      dysonStrategy.rebalance();
    }
  }

  /**
   * @notice  Compute if pool is in range
   * @dev     Simsala
   * @param   dysonStrategy  strategy to check
   * @param   uniPool  uni pool to check
   * @return  bool  if in range, pool gets skipped
   */
  function _inRangeCalc(IStrategyRebalanceStakerUniV3 dysonStrategy, IUniswapV3Pool uniPool)
    internal
    view
    returns (bool)
  {
    (, int24 currentTick, , , , , ) = uniPool.slot0();

    return currentTick > dysonStrategy.tick_lower() && currentTick < dysonStrategy.tick_upper();
  }

  /**
   * @notice  Compute if pool is within threshold (to be rebalanced)
   * @dev     Simsala
   * @param   currentTick  uni pool to check
   * @param   dysonPool  strategy to check
   * @return  bool  if in range, pool gets skipped
   */
  function _inThresholdCalc(int24 currentTick, DysonPoolData memory dysonPool) internal pure returns (bool) {
    return currentTick > dysonPool.tickLowerThreshold && currentTick < dysonPool.tickUpperThreshold;
  }

  /**
   * @notice  Recovers Native asset to owner
   * @dev     Simsala
   * @param   _receiver  address that receives native assets
   */
  function clearStuckBalance(address _receiver) external onlyOwner {
    uint256 balance = address(this).balance;
    payable(_receiver).transfer(balance);
    emit ClearStuckBalance(balance, _receiver, block.timestamp);
  }

  /**
   * @notice  returns assets of balance to owner
   * @dev     Simsala
   * @param   tokenAddress  address of ERC-20 to be refunded
   */
  function rescueToken(address tokenAddress) external onlyOwner {
    uint256 tokens = IERC20(tokenAddress).balanceOf(address(this));
    emit RescueToken(tokenAddress, msg.sender, tokens, block.timestamp);
    IERC20(tokenAddress).transfer(msg.sender, tokens);
  }

  /**
   * @notice  Update the threshold for rebalancing
   * @dev     Simsala
   * @param   _threshold  value for the multiplier
   */
  function updateThreshold(int24 _threshold) external onlyOwner {
    thresholdMulti = _threshold;
    emit UpdateThreshold(_threshold);
  }

  /**
   * @notice  Returns the dyson pool array
   * @dev     Simsala
   * @return  address[]  dyson pool array
   */
  function dysonPoolsCheck() public view returns (address[] memory) {
    return dysonPools;
  }

  // **** Setters **** //

  /**
   * @notice  Whitelist harvesters for autocompounding, governance & strategists are whitelisted by default
   * @param   _harvesters  array of addresses to be whitelisted
   */
  function whitelistHarvesters(address[] calldata _harvesters) external {
    require(msg.sender == owner() || harvesters[msg.sender], "not authorized");

    for (uint256 i = 0; i < _harvesters.length; i++) {
      harvesters[_harvesters[i]] = true;
    }
  }

  /**
   * @notice  Revoke address from harvesting power, governance & strategists can't be turned off
   * @param   _harvesters  array of addresses to not be whitelisted
   */
  function revokeHarvesters(address[] calldata _harvesters) external {
    require(msg.sender == owner(), "not authorized");

    for (uint256 i = 0; i < _harvesters.length; i++) {
      harvesters[_harvesters[i]] = false;
    }
  }

  /**
   * @notice  Add dyson strategy to be checked for
   * @dev     Simsala
   * @param   _dysonPool  Dyson pool
   * @param   _value  if true, adds strategy, if false, remove from loop
   */
  function addDysonStrategy(address _dysonPool, bool _value) external onlyOwner {
    require(uniPoolCheck[_dysonPool] != _value, "Value already set");

    uniPoolCheck[_dysonPool] = _value;

    if (_value) {
      dysonPools.push(_dysonPool);
    } else {
      for (uint256 i = 0; i < dysonPools.length; i++) {
        if (dysonPools[i] == _dysonPool) {
          dysonPools[i] = dysonPools[dysonPools.length - 1];
          dysonPools.pop();
          break;
        }
      }
    }

    emit SetUniContracts(address(_dysonPool), _value);
  }
}

