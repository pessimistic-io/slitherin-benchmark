// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
pragma experimental ABIEncoderV2;

import "./IControllerV7.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IUniswapV3Pool.sol";
import "./ISwapRouter.sol";
import "./IUniswapCalculator.sol";
import "./IWeth.sol";
import "./IStrategyRebalanceStakerUniV3.sol";

contract UniV3Vault is ERC20Upgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  address public wNative;
  address public constant univ3Router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

  address public governance;
  address public timelock;
  address public controller;

  bool public paused;

  IUniswapV3Pool public pool;

  IERC20Upgradeable public token0;
  IERC20Upgradeable public token1;
  IUniswapCalculator public uniswapCalculator;
  int8 public controllerType;

  // Cache struct for calculations
  struct Info {
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0;
    uint256 amount1;
    uint128 liquidity;
  }

  event VaultPaused(uint256 block, uint256 timestamp);

  function __UniswapVault_init(
    string memory _name,
    string memory _symbol,
    address _pool,
    address _governance,
    address _timelock,
    address _controller,
    address _iUniswapCalculator,
    address _wNative
  ) public initializer {
    __ERC20_init_unchained(_name, _symbol);
    __Ownable_init();
    pool = IUniswapV3Pool(_pool);
    token0 = IERC20Upgradeable(pool.token0());
    token1 = IERC20Upgradeable(pool.token1());

    governance = _governance;
    timelock = _timelock;
    controller = _controller;
    paused = false;
    uniswapCalculator = IUniswapCalculator(_iUniswapCalculator);
    wNative = _wNative;
  }

  /**
   * @notice  Total liquidity
   * @return  uint256  returns amount of liquidity
   */
  function totalLiquidity() public view returns (uint256) {
    return liquidityOfThis() + (IControllerV7(controller).liquidityOf(address(pool)));
  }

  /**
   * @notice  How much liquidity the protocol holds
   * @return  uint256  the amount of liquidity for amount
   */
  function liquidityOfThis() public view returns (uint256) {
    uint256 _balance0 = token0.balanceOf(address(this));
    uint256 _balance1 = token1.balanceOf(address(this));

    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    return
      uint256(
        uniswapCalculator.liquidityForAmounts(sqrtRatioX96, _balance0, _balance1, getLowerTick(), getUpperTick())
      );
  }

  /**
   * @notice  Gets the current upper tick of pool
   * @return  int24  returns the upper tick of the pool
   */
  function getUpperTick() public view returns (int24) {
    return IControllerV7(controller).getUpperTick(address(pool));
  }

  /**
   * @notice  Gets the current lower tick of pool
   * @return  int24  returns the lower tick of the pool
   */
  function getLowerTick() public view returns (int24) {
    return IControllerV7(controller).getLowerTick(address(pool));
  }

  /**
   * @notice  Governance address of the pool
   * @param   _governance  address of new governance
   */
  function setGovernance(address _governance) public {
    require(msg.sender == governance, "!governance");
    governance = _governance;
  }

  /**
   * @notice  Timelock address of the pool
   * @param   _timelock  address of new timelock
   */
  function setTimelock(address _timelock) public {
    require(msg.sender == timelock, "!timelock");
    timelock = _timelock;
  }

  /**
   * @notice  Controller address for data fetching
   * @param   _controller  address of the new controller
   */
  function setController(address _controller) public {
    require(msg.sender == timelock, "!timelock");
    controller = _controller;
  }

  /**
   * @notice  Controller address for data fetching
   * @param   _controlType controlType
   */
  function setControllerType(int8 _controlType) public {
    require(msg.sender == governance, "!governance");
    require(controllerType == 0, "!set");
    controllerType = _controlType;
  }

  /**
   * @notice  Updates the boolean to start/stop the pool
   * @param   _paused  Boolean
   */
  function setPaused(bool _paused) external {
    require(msg.sender == governance, "!governance");
    paused = _paused;
    emit VaultPaused(block.number, block.timestamp);
  }

  /**
   * @notice  transfer assets for earning
   */
  function earn() public {
    require(liquidityOfThis() > 0, "no liquidity here");

    uint256 balance0 = token0.balanceOf(address(this));
    uint256 balance1 = token1.balanceOf(address(this));

    token0.safeTransfer(controller, balance0);
    token1.safeTransfer(controller, balance1);

    IControllerV7(controller).earn(address(pool), balance0, balance1);
  }

  /**
   * @notice  Deposits assets into the protocol
   * @param   token0Amount  Amount of token0
   * @param   token1Amount  Amount of token0
   */
  function deposit(uint256 token0Amount, uint256 token1Amount) external payable nonReentrant whenNotPaused {
    IStrategyRebalanceStakerUniV3(address(IControllerV7(controller).strategies(address(pool)))).harvest();
    bool _maticUsed;
    (token0Amount, token1Amount, _maticUsed) = _convertMatic(token0Amount, token1Amount);

    _deposit(token0Amount, token1Amount);

    uint256 _liquidity = _refundUnused(_maticUsed);

    uint256 shares = 0;
    if (totalSupply() == 0) {
      shares = _liquidity;
    } else {
      shares = (_liquidity * (totalSupply())) / (IControllerV7(controller).liquidityOf(address(pool)));
    }

    _mint(msg.sender, shares);

    earn();
  }

  /**
   * @notice  Get propotion of assets
   * @return  uint256  proportionate amount for liquidity
   */
  function getProportion() public view returns (uint256) {
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    (uint256 a1, uint256 a2) = uniswapCalculator.amountsForLiquidity(
      sqrtRatioX96,
      1e18,
      getLowerTick(),
      getUpperTick()
    );
    return (a2 * (10**18)) / a1;
  }

  /**
   * @notice  Withdraw all assets
   */
  function withdrawAll() external {
    withdraw(balanceOf(msg.sender));
  }

  /**
   * @notice  Withdraw asssets proportionate to calculation
   * @param   _shares  amount of shares
   */
  function withdraw(uint256 _shares) public nonReentrant whenNotPaused {
    uint256 r = (totalLiquidity() * (_shares)) / (totalSupply());
    (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
    (uint256 _expectA0, uint256 _expectA1) = uniswapCalculator.amountsForLiquidity(
      sqrtRatioX96,
      uint128(r),
      getLowerTick(),
      getUpperTick()
    );
    _burn(msg.sender, _shares);
    // Check balance
    uint256[2] memory _balances = [token0.balanceOf(address(this)), token1.balanceOf(address(this))];
    uint256 b = liquidityOfThis();

    if (b < r) {
      uint256 _withdraw = r - (b);
      (uint256 _a0, uint256 _a1) = IControllerV7(controller).withdraw(address(pool), _withdraw);
      _expectA0 = _balances[0] + (_a0);
      _expectA1 = _balances[1] + (_a1);
    }

    token0.safeTransfer(msg.sender, _expectA0);
    token1.safeTransfer(msg.sender, _expectA1);
  }

  /**
   * @notice  Get Ratio of liquidity
   * @return  uint256  returns the ratio of share
   */
  function getRatio() public view returns (uint256) {
    if (totalSupply() == 0) return 0;
    return (totalLiquidity() * (1e18)) / (totalSupply());
  }

  /**
   * @notice  Deposits the token amount into the protocol
   * @param   token0Amount  Amount of token0
   * @param   token1Amount  Amount of token1
   */
  function _deposit(uint256 token0Amount, uint256 token1Amount) internal {
    if (!(token0.balanceOf(address(this)) >= token0Amount) && (token0Amount != 0))
      token0.safeTransferFrom(msg.sender, address(this), token0Amount);

    if (!(token1.balanceOf(address(this)) >= token1Amount) && (token1Amount != 0))
      token1.safeTransferFrom(msg.sender, address(this), token1Amount);

    _balanceProportion(getLowerTick(), getUpperTick());
  }

  /**
   * @notice  Wrap matic to wNative and put it as token amount
   * @param   token0Amount  Amount of token0 if matic
   * @param   token1Amount  Amount of token1 if matic
   * @return  uint256  Amount of token0 (is > 0 if wNative is token0)
   * @return  uint256  Amount of token1 (is > 0 if wNative is token1)
   * @return  bool  True if matic has been used
   */
  function _convertMatic(uint256 token0Amount, uint256 token1Amount)
    internal
    returns (
      uint256,
      uint256,
      bool
    )
  {
    bool _maticUsed = false;
    uint256 _matic = msg.value;
    if (_matic > 0) {
      IWETH(wNative).deposit{value: _matic}();

      if (address(token0) == wNative) {
        token0Amount = _matic;
        _maticUsed = true;
      } else if (address(token1) == wNative) {
        token1Amount = _matic;
        _maticUsed = true;
      }
    }
    return (token0Amount, token1Amount, _maticUsed);
  }

  /**
   * @notice  Refunds matic to user by unwrapping wNative to matic
   * @param   _refund  amount to withdraw
   */
  function _refundMatic(uint256 _refund) internal {
    IWETH(wNative).withdraw(_refund);
    (bool sent, bytes memory data) = (msg.sender).call{value: _refund}("");
    require(sent, "Failed to refund Matic");
  }

  /**
   * @notice  Refund unused assets back to user
   * @param   _maticUsed  If matic has been used, unwrap & send
   * @return  uint256 liquidityamount from 0 and 1 asset
   */
  function _refundUnused(bool _maticUsed) internal returns (uint256) {
    Info memory _cache;
    _cache.amount0Desired = token0.balanceOf(address(this));
    _cache.amount1Desired = token1.balanceOf(address(this));

    (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
    uint160 sqrtRatioAX96 = uniswapCalculator.getSqrtRatioAtTick(getLowerTick());
    uint160 sqrtRatioBX96 = uniswapCalculator.getSqrtRatioAtTick(getUpperTick());

    _cache.liquidity = uint128(
      uniswapCalculator.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, _cache.amount0Desired) +
        (uniswapCalculator.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, _cache.amount1Desired))
    );

    (_cache.amount0, _cache.amount1) = uniswapCalculator.getAmountsForLiquidity(
      sqrtPriceX96,
      sqrtRatioAX96,
      sqrtRatioBX96,
      _cache.liquidity
    );

    if (_cache.amount0Desired > _cache.amount0)
      if ((address(token0) == address(wNative)) && _maticUsed) _refundMatic(_cache.amount0Desired - (_cache.amount0));
      else {
        token0.safeTransfer(msg.sender, _cache.amount0Desired - (_cache.amount0));
      }

    if (_cache.amount1Desired > _cache.amount1)
      if ((address(token1) == address(wNative)) && _maticUsed) _refundMatic(_cache.amount1Desired - (_cache.amount1));
      else {
        token1.safeTransfer(msg.sender, _cache.amount1Desired - (_cache.amount1));
      }
    return _cache.liquidity;
  }

  /**
   * @notice  Balances the proportions of the protocol
   * @param   _tickLower  lower ticker
   * @param   _tickUpper  upper ticket
   */
  function _balanceProportion(int24 _tickLower, int24 _tickUpper) internal {
    Info memory _cache;

    _cache.amount0Desired = token0.balanceOf(address(this));
    _cache.amount1Desired = token1.balanceOf(address(this));

    (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
    uint160 sqrtRatioAX96 = uniswapCalculator.getSqrtRatioAtTick(_tickLower);
    uint160 sqrtRatioBX96 = uniswapCalculator.getSqrtRatioAtTick(_tickUpper);

    _cache.liquidity = uint128(
      uniswapCalculator.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, _cache.amount0Desired) +
        (uniswapCalculator.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, _cache.amount1Desired))
    );

    (_cache.amount0, _cache.amount1) = uniswapCalculator.getAmountsForLiquidity(
      sqrtPriceX96,
      sqrtRatioAX96,
      sqrtRatioBX96,
      _cache.liquidity
    );

    //Determine Trade Direction
    bool _zeroForOne = _cache.amount0Desired > _cache.amount0 ? true : false;

    //Determine Amount to swap
    uint256 _amountSpecified = _zeroForOne
      ? (_cache.amount0Desired - (_cache.amount0))
      : (_cache.amount1Desired - (_cache.amount1));

    if (_amountSpecified > 0) {
      //Determine Token to swap
      address _inputToken = _zeroForOne ? address(token0) : address(token1);

      IERC20Upgradeable(_inputToken).safeApprove(univ3Router, 0);
      IERC20Upgradeable(_inputToken).safeApprove(univ3Router, _amountSpecified);

      //Swap the token imbalanced
      ISwapRouter(univ3Router).exactInputSingle(
        ISwapRouter.ExactInputSingleParams({
          tokenIn: _inputToken,
          tokenOut: _zeroForOne ? address(token1) : address(token0),
          fee: pool.fee(),
          recipient: address(this),
          amountIn: _amountSpecified,
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
        })
      );
    }
  }

  /**
   * @notice  If not paused modifier
   */
  modifier whenNotPaused() {
    require(paused == false, "paused");
    _;
  }

  /**
   * @notice  Receive ERC721 assets
   * @return  bytes4  returns ERC721 selector
   */
  function onERC721Received(
    address,
    address,
    uint256,
    bytes memory
  ) public pure returns (bytes4) {
    return this.onERC721Received.selector;
  }

  fallback() external payable {}

  receive() external payable {}
}

