// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./erc20.sol";
import "./IControllerV7.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Staker.sol";
import "./ISwapRouter.sol";
import "./IUniswapCalculator.sol";
import "./IUniswapV3PositionsNFT.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";

contract StrategyRebalanceStakerUniV3 is Initializable, OwnableUpgradeable {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;

  // Cache struct for calculations
  struct Info {
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0;
    uint256 amount1;
    uint128 liquidity;
  }

  // Perfomance fees - start with 20%
  uint256 public performanceTreasuryFee;
  uint256 public constant PERFORMANCE_TREASURY_MAX = 10000;

  // User accounts
  address public governance;
  address public controller;
  address public strategist;
  address public timelock;

  address public univ3_staker;

  // Dex
  address public constant univ3Router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

  // Tokens
  IUniswapV3Pool public pool;

  IERC20 public token0;
  IERC20 public token1;
  uint256 public tokenId;

  int24 public tick_lower;
  int24 public tick_upper;
  int24 private tickSpacing;
  int24 public tickRangeMultiplier;
  uint24 public swapPoolFee;
  uint24 private twapTime;
  uint256 public lastHarvest;

  IUniswapV3PositionsNFT public constant nftManager =
    IUniswapV3PositionsNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

  mapping(address => bool) public harvesters;

  int24 public innerTickRangeMultiplier;
  int24 public inner_tick_lower;
  int24 public inner_tick_upper;
  IUniswapCalculator public uniswapCalculator;
  bool public overWriteTicks;

  event InitialDeposited(uint256 tokenId);
  event Harvested(uint256 tokenId);
  event Deposited(uint256 tokenId, uint256 token0Balance, uint256 token1Balance);
  event Withdrawn(uint256 tokenId, uint256 _liquidity);
  event Rebalanced(uint256 tokenId, int24 _tickLower, int24 _tickUpper);

  function initialize(
    address _pool,
    int24 _tickRangeMultiplier,
    address _governance,
    address _strategist,
    address _controller,
    address _timelock,
    address _iUniswapCalculator
  ) public initializer {
    __Ownable_init_unchained();
    governance = _governance;
    strategist = _strategist;
    controller = _controller;
    timelock = _timelock;

    uniswapCalculator = IUniswapCalculator(_iUniswapCalculator);

    performanceTreasuryFee = 2000;
    twapTime = 60;

    pool = IUniswapV3Pool(_pool);

    token0 = IERC20(pool.token0());
    token1 = IERC20(pool.token1());

    tickSpacing = pool.tickSpacing();
    tickRangeMultiplier = _tickRangeMultiplier;
    innerTickRangeMultiplier = (_tickRangeMultiplier * 8) / 10;

    token0.safeApprove(address(nftManager), type(uint128).max);
    token1.safeApprove(address(nftManager), type(uint128).max);
    nftManager.setApprovalForAll(address(nftManager), true);
    harvesters[msg.sender] = true;
    performanceTreasuryFee = 2000;
    twapTime = 60;
    swapPoolFee = pool.fee();
  }

  // **** Modifiers **** //

  modifier onlyBenevolent() {
    require(harvesters[msg.sender] || msg.sender == governance || msg.sender == strategist);
    _;
  }

  // **** Views **** //

  /**
   * @notice  Total liquidity
   * @return  uint256  returns amount of liquidity
   */
  function liquidityOfThis() public view returns (uint256) {
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    uint256 liquidity = uint256(
      uniswapCalculator.liquidityForAmounts(
        sqrtRatioX96,
        token0.balanceOf(address(this)),
        token1.balanceOf(address(this)),
        tick_lower,
        tick_upper
      )
    );
    return liquidity;
  }

  /**
   * @notice  The liquidity of our Uni position
   * @return  uint256  returns total liquidity
   */
  function liquidityOfPool() public view returns (uint256) {
    (, , , , , , , uint128 _liquidity, , , , ) = nftManager.positions(tokenId);
    return _liquidity;
  }

  /**
   * @notice  Total liquidity
   * @return  uint256  returns total liquidity
   */
  function liquidityOf() public view returns (uint256) {
    return liquidityOfThis() + (liquidityOfPool());
  }

  // **** Setters **** //

  /**
   * @notice  Adjusts harvesters for autocompounding, governance & strategists are whitelisted by default
   * @param   _harvesters  array of addresses to be whitelisted
   * @param   _values     boolean to allow or disallow harvesters
   */
  function adjustHarvesters(address[] calldata _harvesters, bool[] calldata _values) external {
    require(msg.sender == governance || msg.sender == strategist || harvesters[msg.sender], "not authorized");

    for (uint256 i = 0; i < _harvesters.length; i++) {
      harvesters[_harvesters[i]] = _values[i];
    }
  }

  /**
   * @notice  Performance fee of the protocol to be taken, the timelock only can update
   * @param   _performanceTreasuryFee  Amount of treasury fee
   */
  function setPerformanceTreasuryFee(uint256 _performanceTreasuryFee) external {
    require(msg.sender == timelock, "!timelock");
    performanceTreasuryFee = _performanceTreasuryFee;
  }

  /**
   * @notice  Set a new swap pool fee, initial is based on Uniswap
   * @param   _swapPoolFee  amount new swap pool fee
   */
  function setSwapPoolFee(uint24 _swapPoolFee) external {
    require(msg.sender == governance, "!governance");
    swapPoolFee = _swapPoolFee;
  }

  /**
   * @notice  Update the new strategy, only by governance
   * @param   _strategist  new address
   */
  function setStrategist(address _strategist) external {
    require(msg.sender == governance, "!governance");
    strategist = _strategist;
  }

  /**
   * @notice  Update the new governance, only by governance
   * @param   _governance  new address
   */
  function setGovernance(address _governance) external {
    require(msg.sender == governance, "!governance");
    governance = _governance;
  }

  /**
   * @notice  Update the new governance, only by governance
   * @param   _timelock  new address
   */
  function setTimelock(address _timelock) external {
    require(msg.sender == timelock, "!timelock");
    timelock = _timelock;
  }

  /**
   * @notice  Update to the new timelock, only by timelock
   * @param   _controller  new address
   */
  function setController(address _controller) external {
    require(msg.sender == timelock, "!timelock");
    controller = _controller;
  }

  /**
   * @notice  Twap time, changeable only by governance
   * @param   _twapTime  new value
   */
  function setTwapTime(uint24 _twapTime) public {
    require(msg.sender == governance, "!governance");
    twapTime = _twapTime;
  }

  /**
   * @notice  Twap time, changeable only by governance
   * @param   _twapTime  new value
   */
  /**
   * @notice  .
   * @dev     .
   * @param   _tick_lower  .
   * @param   _tick_upper  .
   * @param   _inner_tick_lower  .
   * @param   _inner_tick_upper  .
   * @param   _overWriteTicks  .
   */
  function setTicks(
    int24 _tick_lower,
    int24 _tick_upper,
    int24 _inner_tick_lower,
    int24 _inner_tick_upper,
    bool _overWriteTicks
  ) public {
    require(msg.sender == governance, "!governance");
    if (!_overWriteTicks) {
      overWriteTicks = _overWriteTicks;
    } else {
      tick_lower = _tick_lower;
      tick_upper = _tick_upper;
      inner_tick_lower = _inner_tick_lower;
      inner_tick_upper = _inner_tick_upper;
      overWriteTicks = _overWriteTicks;
    }
  }

  /**
   * @notice  Tick range multiplier for the rebalance
   * @param   _tickRangeMultiplier  the multiplier value
   * @param   _innerTickRangeMultiplier  the multiplier value for inner road
   */
  function setTickRangeMultiplier(int24 _tickRangeMultiplier, int24 _innerTickRangeMultiplier) public {
    require(msg.sender == governance, "!governance");
    tickRangeMultiplier = _tickRangeMultiplier;
    innerTickRangeMultiplier = _innerTickRangeMultiplier;
  }

  /**
   * @notice  amount of liquid
   * @return  uint256  token0 value
   * @return  uint256  token1 value
   */
  function amountsForLiquid() public view returns (uint256, uint256) {
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    (uint256 a1, uint256 a2) = uniswapCalculator.amountsForLiquidity(sqrtRatioX96, 1e18, tick_lower, tick_upper);
    return (a1, a2);
  }

  /**
   * @notice  Determine the optimal tick for our pool
   * @return  _lowerTick  lower tick
   * @return  _upperTick  upper tick
   * @return  _innerLowerTick  inner lower tick
   * @return  _innerUpperTick  inner upper tick
   */
  function determineTicks()
    public
    view
    returns (
      int24 _lowerTick,
      int24 _upperTick,
      int24 _innerLowerTick,
      int24 _innerUpperTick
    )
  {
    uint32[] memory _observeTime = new uint32[](2);
    _observeTime[0] = twapTime;
    _observeTime[1] = 0;
    (int56[] memory _cumulativeTicks, ) = pool.observe(_observeTime);

    (_innerLowerTick, _innerUpperTick) = uniswapCalculator.determineTicksCalc(
      _cumulativeTicks,
      tickSpacing,
      innerTickRangeMultiplier,
      twapTime
    );

    (_lowerTick, _upperTick) = uniswapCalculator.determineTicksCalc(
      _cumulativeTicks,
      tickSpacing,
      tickRangeMultiplier,
      twapTime
    );
  }

  /**
   * @notice  Determine the pool fee type of Uniswap
   * @return  uint256  gets the Uniswap fee
   */
  function getBasisPoints() public view returns (uint256) {
    return pool.fee();
  }

  // **** State mutations **** //

  /**
   * @notice  withdraw the token and re-deposit with new total liquidity
   */
  function deposit() public {
    uint256 _token0 = token0.balanceOf(address(this));
    uint256 _token1 = token1.balanceOf(address(this));

    if (_token0 > 0 && _token1 > 0) {
      nftManager.increaseLiquidity(
        IUniswapV3PositionsNFT.IncreaseLiquidityParams({
          tokenId: tokenId,
          amount0Desired: _token0,
          amount1Desired: _token1,
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp + 300
        })
      );
    }

    emit Deposited(tokenId, _token0, _token1);
  }

  /**
   * @notice  Withdraw some assets from the protocol
   * @param   _liquidity  amount to be withdrawn
   * @return  uint256  return amount 0
   * @return  uint256  return amount 1
   */
  function _withdrawSome(uint256 _liquidity) internal returns (uint256, uint256) {
    if (_liquidity == 0) return (0, 0);

    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    (uint256 _a0Expect, uint256 _a1Expect) = uniswapCalculator.amountsForLiquidity(
      sqrtRatioX96,
      uint128(_liquidity),
      tick_lower,
      tick_upper
    );
    (uint256 amount0, uint256 amount1) = nftManager.decreaseLiquidity(
      IUniswapV3PositionsNFT.DecreaseLiquidityParams({
        tokenId: tokenId,
        liquidity: uint128(_liquidity),
        amount0Min: _a0Expect,
        amount1Min: _a1Expect,
        deadline: block.timestamp + 300
      })
    );

    //Only collect decreasedLiquidity, not trading fees.
    nftManager.collect(
      IUniswapV3PositionsNFT.CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: uint128(amount0),
        amount1Max: uint128(amount1)
      })
    );

    return (amount0, amount1);
  }

  /**
   * @notice  Controller only function for creating additional rewards from dust
   * @param   _asset  withdraw assets from the protocol
   * @return  balance  asset amount that has been withdrawn
   */
  function withdraw(IERC20 _asset) external returns (uint256 balance) {
    require(msg.sender == controller, "!controller");
    balance = _asset.balanceOf(address(this));
    _asset.safeTransfer(controller, balance);
  }

  /**
   * @notice  Override base withdraw function to redeposit
   * @param   _liquidity  amount of assets to be withdrawn
   * @return  a0  token0 amount
   * @return  a1  token1 amount
   */
  function withdraw(uint256 _liquidity) external returns (uint256 a0, uint256 a1) {
    require(msg.sender == controller, "!controller");
    (a0, a1) = _withdrawSome(_liquidity);

    address _vault = IControllerV7(controller).vaults(address(pool));
    require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

    token0.safeTransfer(_vault, a0);
    token1.safeTransfer(_vault, a1);

    emit Withdrawn(tokenId, _liquidity);
  }

  /**
   * @notice  Withdraw all funds, normally used when migrating strategies
   * @return  a0  amount of token0
   * @return  a1  amount of token1
   */
  function withdrawAll() external returns (uint256 a0, uint256 a1) {
    require(msg.sender == controller, "!controller");
    _withdrawAll();
    address _vault = IControllerV7(controller).vaults(address(pool));
    require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

    a0 = token0.balanceOf(address(this));
    a1 = token1.balanceOf(address(this));
    token0.safeTransfer(_vault, a0);
    token1.safeTransfer(_vault, a1);
  }

  /**
   * @notice  Withdraw all assets of pool
   * @return  a0  amount of token0
   * @return  a1  amount of token1
   */
  function _withdrawAll() internal returns (uint256 a0, uint256 a1) {
    (a0, a1) = _withdrawSome(liquidityOfPool());
  }

  /**
   * @notice  Rebalancing, re-set the position and taking performance fee for the user
   */
  function harvest() public onlyBenevolent {
    uint256 _initToken0 = token0.balanceOf(address(this));
    uint256 _initToken1 = token1.balanceOf(address(this));

    nftManager.collect(
      IUniswapV3PositionsNFT.CollectParams({
        tokenId: tokenId,
        recipient: address(this),
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );

    nftManager.sweepToken(address(token0), 0, address(this));
    nftManager.sweepToken(address(token1), 0, address(this));

    _distributePerformanceFees(
      token0.balanceOf(address(this)) - (_initToken0),
      token1.balanceOf(address(this)) - (_initToken1)
    );

    _balanceProportion(tick_lower, tick_upper);

    deposit();

    lastHarvest = block.timestamp;

    emit Harvested(tokenId);
  }

  /**
   * @notice  rebalances the pool
   * @return  _tokenId  new token id
   */
  function rebalance() external onlyBenevolent returns (uint256 _tokenId) {
    if (tokenId != 0) {
      uint256 _initToken0 = token0.balanceOf(address(this));
      uint256 _initToken1 = token1.balanceOf(address(this));

      (, , , , , , , uint256 _liquidity, , , , ) = nftManager.positions(tokenId);
      (uint256 _liqAmt0, uint256 _liqAmt1) = nftManager.decreaseLiquidity(
        IUniswapV3PositionsNFT.DecreaseLiquidityParams({
          tokenId: tokenId,
          liquidity: uint128(_liquidity),
          amount0Min: 0,
          amount1Min: 0,
          deadline: block.timestamp + 300
        })
      );

      // This has to be done after DecreaseLiquidity to collect the tokens we
      // decreased and the fees at the same time.
      nftManager.collect(
        IUniswapV3PositionsNFT.CollectParams({
          tokenId: tokenId,
          recipient: address(this),
          amount0Max: type(uint128).max,
          amount1Max: type(uint128).max
        })
      );

      nftManager.sweepToken(address(token0), 0, address(this));
      nftManager.sweepToken(address(token1), 0, address(this));
      nftManager.burn(tokenId);

      _distributePerformanceFees(
        token0.balanceOf(address(this)) - (_liqAmt0) - (_initToken0),
        token1.balanceOf(address(this)) - (_liqAmt1) - (_initToken1)
      );
    }

    int24 _tickLower;
    int24 _tickUpper;
    int24 _innerTickLower;
    int24 _innerTickUpper;

    if (overWriteTicks) {
      _tickLower = tick_lower;
      _tickUpper = tick_upper;
      _innerTickLower = inner_tick_lower;
      _innerTickUpper = inner_tick_upper;
    } else {
      (_tickLower, _tickUpper, _innerTickLower, _innerTickUpper) = determineTicks();
    }

    _balanceProportion(_tickLower, _tickUpper);
    //Need to do this again after the swap to cover any slippage.
    uint256 _amount0Desired = token0.balanceOf(address(this));
    uint256 _amount1Desired = token1.balanceOf(address(this));

    (_tokenId, , , ) = nftManager.mint(
      IUniswapV3PositionsNFT.MintParams({
        token0: address(token0),
        token1: address(token1),
        fee: pool.fee(),
        tickLower: _tickLower,
        tickUpper: _tickUpper,
        amount0Desired: _amount0Desired,
        amount1Desired: _amount1Desired,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp + 300
      })
    );

    //Record updated information.
    tokenId = _tokenId;
    tick_lower = _tickLower;
    tick_upper = _tickUpper;
    inner_tick_lower = _innerTickLower;
    inner_tick_upper = _innerTickUpper;

    if (tokenId == 0) {
      emit InitialDeposited(_tokenId);
    }

    emit Rebalanced(tokenId, _tickLower, _tickUpper);
  }

  /**
   * @notice Calculates whether the current tick is within the specified range
   * @dev The range is determined by calling the `tick_lower` and `tick_upper` functions
   * @return true if the current tick is within the range, false otherwise
   */
  function inRangeCalc() public view returns (bool) {
    (, int24 currentTick, , , , , ) = pool.slot0();

    return currentTick > inner_tick_lower && currentTick < inner_tick_upper;
  }

  // **** Internal functions ****

  /**
   * @notice  Send the performance fee to the treasury
   * @param   _amount0  amount 0 to be sent towards the treasury
   * @param   _amount1  amount 1 to be sent towards the treasury
   */
  function _distributePerformanceFees(uint256 _amount0, uint256 _amount1) internal {
    if (_amount0 > 0) {
      IERC20(token0).safeTransfer(
        IControllerV7(controller).treasury(),
        (_amount0 * (performanceTreasuryFee)) / (PERFORMANCE_TREASURY_MAX)
      );
    }
    if (_amount1 > 0) {
      IERC20(token1).safeTransfer(
        IControllerV7(controller).treasury(),
        (_amount1 * (performanceTreasuryFee)) / (PERFORMANCE_TREASURY_MAX)
      );
    }
  }

  /// @dev Get imbalanced token
  /// @param amount0Desired The desired amount of token0
  /// @param amount1Desired The desired amount of token1
  /// @param amount0 Amounts of token0 that can be stored in base range
  /// @param amount1 Amounts of token1 that can be stored in base range
  /// @return zeroGreaterOne true if token0 is imbalanced. False if token1 is imbalanced
  function _amountsDirection(
    uint256 amount0Desired,
    uint256 amount1Desired,
    uint256 amount0,
    uint256 amount1
  ) internal pure returns (bool zeroGreaterOne) {
    zeroGreaterOne = (amount0Desired - amount0) * amount1Desired > (amount1Desired - amount1) * amount0Desired
      ? true
      : false;
  }

  function onERC721Received(
    address,
    address,
    uint256,
    bytes memory
  ) public pure returns (bytes4) {
    return this.onERC721Received.selector;
  }

  /**
   * @notice Rebalance assets for liquidity and swap if necessary
   * @param   _tickLower  lower tick
   * @param   _tickUpper  upper tick
   */
  function _balanceProportion(int24 _tickLower, int24 _tickUpper) internal {
    Info memory _cache;

    _cache.amount0Desired = token0.balanceOf(address(this));
    _cache.amount1Desired = token1.balanceOf(address(this));
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

    //Get Max Liquidity for Amounts we own.
    _cache.liquidity = uniswapCalculator.liquidityForAmounts(
      sqrtRatioX96,
      _cache.amount0Desired,
      _cache.amount1Desired,
      _tickLower,
      _tickUpper
    );

    //Get correct amounts of each token for the liquidity we have.
    (_cache.amount0, _cache.amount1) = uniswapCalculator.amountsForLiquidity(
      sqrtRatioX96,
      _cache.liquidity,
      _tickLower,
      _tickUpper
    );

    //Determine Trade Direction
    bool _zeroForOne;
    if (_cache.amount1Desired == 0) {
      _zeroForOne = true;
    } else {
      _zeroForOne = _amountsDirection(_cache.amount0Desired, _cache.amount1Desired, _cache.amount0, _cache.amount1);
    }

    //Determine Amount to swap
    uint256 _amountSpecified = _zeroForOne
      ? ((_cache.amount0Desired - _cache.amount0) / 2)
      : ((_cache.amount1Desired - _cache.amount1) / 2);

    if (_amountSpecified > 0) {
      //Determine Token to swap
      address _inputToken = _zeroForOne ? address(token0) : address(token1);

      IERC20(_inputToken).safeApprove(univ3Router, 0);
      IERC20(_inputToken).safeApprove(univ3Router, _amountSpecified);

      //Swap the token imbalanced
      ISwapRouter(univ3Router).exactInputSingle(
        ISwapRouter.ExactInputSingleParams({
          tokenIn: _inputToken,
          tokenOut: _zeroForOne ? address(token1) : address(token0),
          fee: swapPoolFee,
          recipient: address(this),
          amountIn: _amountSpecified,
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
        })
      );
    }
  }
}

