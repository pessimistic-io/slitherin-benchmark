// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IWNT } from "./IWNT.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";

contract GMXTest {
  using SafeERC20 for IERC20;

  struct AddLiquidityParams {
    // Address of user that is withdrawing
    address payable user;
    // Amount of tokenA to add liquidity
    uint256 tokenAAmt;
    // Amount of tokenB to add liquidity
    uint256 tokenBAmt;
    // Execution fee sent to GMX for adding liquidity
    uint256 executionFee;
  }

  struct WithdrawCache {
    // Address of user that is withdrawing
    address payable user;
    // WithdrawParams
    WithdrawParams withdrawParams;
  }

  struct WithdrawParams {
    // Amount of lp token
    uint256 lpAmt;
    // Address of token to withdraw to; could be tokenA, tokenB or lpToken
    address token;
    // Execution fee sent to GMX for removing liquidity
    uint256 executionFee;
    // SwapParams Swap for repay parameters
    SwapParams swapParams;
  }

  struct SwapParams {
    // Execution fee sent to GMX for swap orders
    uint256 executionFee;
  }

  AddLiquidityParams public _alp;
  WithdrawCache public _wc;

  bytes32 public depositKey;
  bytes32 public withdrawKey;
  bytes32 public orderKey;

  bool public callbackCalled;
  bool public callbackCalled2;

  uint256 public actualExecutionFee;
  bool public refundReceived;
  address public refunder;


  address public WNT = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public tokenA = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public tokenB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
  address public lpToken = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
  address public exchangeRouter = 0x3B070aA6847bd0fB56eFAdB351f49BBb7619dbc2;
  address public router = 0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6;
  address public depositVault = 0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;
  address public withdrawalVault = 0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55;
  address public orderVault = 0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5;
  address public callback;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  constructor() {
    IERC20(tokenA).approve(router, type(uint256).max);
    IERC20(tokenB).approve(router, type(uint256).max);
    IERC20(lpToken).approve(router, type(uint256).max);

    // IERC20(tokenA).approve(exchangeRouter, type(uint256).max);
    // IERC20(tokenB).approve(exchangeRouter, type(uint256).max);
    // IERC20(lpToken).approve(exchangeRouter, type(uint256).max);

    IERC20(tokenA).approve(depositVault, type(uint256).max);
    IERC20(tokenB).approve(depositVault, type(uint256).max);

    IERC20(lpToken).approve(withdrawalVault, type(uint256).max);

    IERC20(tokenA).approve(orderVault, type(uint256).max);
    IERC20(tokenB).approve(orderVault, type(uint256).max);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function updateCallback(address _callback) external {
    callback = _callback;
  }

  function viewAlp() external view returns (AddLiquidityParams memory) {
    return _alp;
  }

  function viewWC() external view returns (WithdrawCache memory) {
    return _wc;
  }

  function addLiquidity(
    AddLiquidityParams memory alp
  ) payable external returns (bytes32) {

    IERC20(tokenA).safeTransferFrom(msg.sender, address(this), alp.tokenAAmt);
    IERC20(tokenB).safeTransferFrom(msg.sender, address(this), alp.tokenBAmt);
    actualExecutionFee = msg.value;

    _alp.user = payable(msg.sender);
    _alp = alp;

    // Send native token for execution fee
    IExchangeRouter(exchangeRouter).sendWnt{ value: alp.executionFee }(
      depositVault,
      alp.executionFee
    );

    // Send tokens
    IExchangeRouter(exchangeRouter).sendTokens(
      tokenA,
      depositVault,
      alp.tokenAAmt
    );

    IExchangeRouter(exchangeRouter).sendTokens(
      tokenB,
      depositVault,
      alp.tokenBAmt
    );

    // TODO calculate slippage in minMarketTokens
    // alp.slippage

    // Create deposit
    IExchangeRouter.CreateDepositParams memory _cdp =
      IExchangeRouter.CreateDepositParams({
        receiver: address(this),
        callbackContract: callback,
        uiFeeReceiver: address(0), // TODO uiFeeReceiver?
        market: lpToken,
        initialLongToken: tokenA,
        initialShortToken: tokenB,
        longTokenSwapPath: new address[](0),
        shortTokenSwapPath: new address[](0),
        minMarketTokens: 0,
        shouldUnwrapNativeToken: false,
        executionFee: alp.executionFee,
        callbackGasLimit: 2000000
      });

    depositKey = IExchangeRouter(exchangeRouter).createDeposit(_cdp);

    // IWNT(WNT).withdraw(IWNT(WNT).balanceOf(address(this)));
    // (bool success, ) = payable(_alp.user).call{value: address(this).balance}("");
    // require(success, "Transfer failed.");
  }

  function postDeposit() external {
    callbackCalled = true;
  }

  function removeLiquidity(
    WithdrawParams memory wp
  ) payable external returns (bytes32) {

    callbackCalled = false;

    IERC20(lpToken).safeTransferFrom(msg.sender, address(this), wp.lpAmt);

    _wc.user = payable(msg.sender);
    _wc.withdrawParams = wp;


    // Send native token for execution fee
    IExchangeRouter(exchangeRouter).sendWnt{ value: wp.executionFee }(
      withdrawalVault,
      wp.executionFee
    );

    // Send tokens
    IExchangeRouter(exchangeRouter).sendTokens(
      lpToken,
      withdrawalVault,
      wp.lpAmt
    );

    // TODO calculate slippage in minMarketTokens
    // alp.slippage

    // Create deposit
    IExchangeRouter.CreateWithdrawalParams memory _cwp =
      IExchangeRouter.CreateWithdrawalParams({
        receiver: address(this),
        callbackContract: callback,
        uiFeeReceiver: address(0),
        market: lpToken,
        longTokenSwapPath: new address[](0),
        shortTokenSwapPath: new address[](0),
        minLongTokenAmount: 0,
        minShortTokenAmount: 0,
        shouldUnwrapNativeToken: false,
        executionFee: wp.executionFee,
        callbackGasLimit: 2000000
      });

    withdrawKey = IExchangeRouter(exchangeRouter).createWithdrawal(_cwp);
  }

  function postWithdraw() external {
    callbackCalled = true;

    // Send native token for execution fee
    IExchangeRouter(exchangeRouter).sendWnt{value: _wc.withdrawParams.swapParams.executionFee}(
      orderVault,
      _wc.withdrawParams.swapParams.executionFee
    );

    address _tokenOut;
    if (_wc.withdrawParams.token == tokenA) {
      _tokenOut = tokenB;
    }
    if (_wc.withdrawParams.token == tokenB) {
      _tokenOut = tokenA;
    }

    // Send tokens
    IExchangeRouter(exchangeRouter).sendTokens(
      _tokenOut,
      orderVault,
      IERC20(_tokenOut).balanceOf(address(this))
    );

    address[] memory _swapPath = new address[](1);
    _swapPath[0] = lpToken;

    IExchangeRouter.CreateOrderParamsAddresses memory _addresses;
    _addresses.receiver = address(this);
    _addresses.initialCollateralToken = _tokenOut;
    _addresses.callbackContract = callback;
    _addresses.market = address(0);
    _addresses.swapPath = _swapPath;
    _addresses.uiFeeReceiver = address(0);

    IExchangeRouter.CreateOrderParamsNumbers memory _numbers;
    _numbers.sizeDeltaUsd = 0;
    _numbers.initialCollateralDeltaAmount = 0;
    _numbers.triggerPrice = 0;
    _numbers.acceptablePrice = 0;
    _numbers.executionFee = _wc.withdrawParams.swapParams.executionFee;
    _numbers.callbackGasLimit = 2000000;
    _numbers.minOutputAmount = 0; // TODO

    IExchangeRouter.CreateOrderParams memory _params =
      IExchangeRouter.CreateOrderParams({
        addresses: _addresses,
        numbers: _numbers,
        orderType: IExchangeRouter.OrderType.MarketSwap,
        decreasePositionSwapType: IExchangeRouter.DecreasePositionSwapType.NoSwap,
        isLong: false,
        shouldUnwrapNativeToken: false,
        referralCode: bytes32(0)
      });

    // Returns bytes32 orderKey
    orderKey = IExchangeRouter(exchangeRouter).createOrder(_params);
  }

  function postSwap() external {
    callbackCalled2 = true;
    IERC20(_wc.withdrawParams.token).safeTransfer(_wc.user, IERC20(_wc.withdrawParams.token).balanceOf(address(this)));
  }

  function resetVault() external {
    IWNT(WNT).withdraw(IWNT(WNT).balanceOf(address(this)));
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    IERC20(tokenA).safeTransfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));
    IERC20(tokenB).safeTransfer(msg.sender, IERC20(tokenB).balanceOf(address(this)));
    IERC20(lpToken).safeTransfer(msg.sender, IERC20(lpToken).balanceOf(address(this)));

    callbackCalled = false;
    callbackCalled2 = false;
  }

  receive() external payable {
    refunder = msg.sender;
    refundReceived = true;

    if (
      msg.sender == depositVault ||
      msg.sender == withdrawalVault ||
      msg.sender == orderVault
    ) {
      IWNT(WNT).withdraw(IWNT(WNT).balanceOf(address(this)));
      (bool success, ) = payable(_alp.user).call{value: address(this).balance}("");
      require(success, "Transfer failed.");
    }
  }
}

