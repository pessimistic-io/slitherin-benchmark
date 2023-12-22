// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IWNT } from "./IWNT.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";
import { ISwapRouter } from "./ISwapRouter.sol";

contract GMXTest {
  using SafeERC20 for IERC20;

  struct DepositCache {
    // Address of user that is withdrawing
    address payable user;
    // WithdrawParams
    DepositParams depositParams;
  }

  struct DepositParams {
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
    SwapParams swapParams;
  }

  struct WithdrawParams {
    // Amount of lp token
    uint256 lpAmt;
    // Execution fee sent to GMX for removing liquidity
    uint256 executionFee;
  }

  struct SwapParams {
    // Amount of lp token
    address tokenFrom;
    // Address of token to withdraw to; could be tokenA, tokenB or lpToken
    address tokenTo;
    // SwapParams Swap for repay parameters
    uint256 executionFee;
  }

  DepositCache public _dc;
  WithdrawCache public _wc;
  IExchangeRouter.CreateOrderParams public cop;

  bytes32 public depositKey;
  bytes32 public withdrawKey;
  bytes32 public orderKey;

  bool public callbackCalled;
  bool public swapCalled;
  bool public callbackCalled2;

  address public tokenOutToReceive;
  uint256 public tokenOutToReceiveAmt;
  uint256 public swapParamsExecutionFee;

  uint256 public refundAmtReceived;
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
  address public univ3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

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

    address[] memory _swapPath = new address[](1);
    _swapPath[0] = lpToken;

    IExchangeRouter.CreateOrderParamsAddresses memory _addresses;
    _addresses.receiver = address(this);
    _addresses.initialCollateralToken = address(0);
    _addresses.callbackContract = callback;
    _addresses.market = address(0);
    _addresses.swapPath = _swapPath;
    _addresses.uiFeeReceiver = address(0);

    IExchangeRouter.CreateOrderParamsNumbers memory _numbers;
    _numbers.sizeDeltaUsd = 0;
    _numbers.initialCollateralDeltaAmount = 0;
    _numbers.triggerPrice = 0;
    _numbers.acceptablePrice = 0;
    _numbers.executionFee = 0;
    _numbers.callbackGasLimit = 2000000;
    _numbers.minOutputAmount = 0; // TODO

    IExchangeRouter.CreateOrderParams memory _cop =
      IExchangeRouter.CreateOrderParams({
        addresses: _addresses,
        numbers: _numbers,
        orderType: IExchangeRouter.OrderType.MarketSwap,
        decreasePositionSwapType: IExchangeRouter.DecreasePositionSwapType.NoSwap,
        isLong: false,
        shouldUnwrapNativeToken: false,
        referralCode: bytes32(0)
      });

    cop = _cop;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  function updateCallback(address _callback) external {
    callback = _callback;
  }

  function dc() external view returns (DepositCache memory) {
    return _dc;
  }

  function wc() external view returns (WithdrawCache memory) {
    return _wc;
  }

  function addLiquidity(
    DepositParams memory dp
  ) payable external {

    callbackCalled = false;

    IERC20(tokenA).safeTransferFrom(msg.sender, address(this), dp.tokenAAmt);
    IERC20(tokenB).safeTransferFrom(msg.sender, address(this), dp.tokenBAmt);
    // actualExecutionFee = msg.value;

    _dc.user = payable(msg.sender);
    _dc.depositParams = dp;

    // Send native token for execution fee
    IExchangeRouter(exchangeRouter).sendWnt{ value: dp.executionFee }(
      depositVault,
      dp.executionFee
    );

    // Send tokens
    IExchangeRouter(exchangeRouter).sendTokens(
      tokenA,
      depositVault,
      dp.tokenAAmt
    );

    IExchangeRouter(exchangeRouter).sendTokens(
      tokenB,
      depositVault,
      dp.tokenBAmt
    );

    // TODO calculate slippage in minMarketTokens
    // dp.slippage

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
        executionFee: dp.executionFee,
        callbackGasLimit: 2000000
      });

    depositKey = IExchangeRouter(exchangeRouter).createDeposit(_cdp);
  }

  function postDeposit() external {
    callbackCalled = true;
    IERC20(lpToken).safeTransfer(_dc.user, IERC20(lpToken).balanceOf(address(this)));
  }

  function removeLiquidity(
    WithdrawParams memory wp,
    SwapParams memory sp
  ) payable external {

    callbackCalled = false;

    IERC20(lpToken).safeTransferFrom(msg.sender, address(this), wp.lpAmt);

    _wc.user = payable(msg.sender);
    _wc.withdrawParams = wp;
    _wc.swapParams = sp;


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
    // dp.slippage

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

    swap();
  }

  function swap() payable public {
    swapCalled = true;

    IERC20(_wc.swapParams.tokenFrom).approve(
      univ3Router,
      IERC20(_wc.swapParams.tokenFrom).balanceOf(address(this))
    );

    // Using univ3
    ISwapRouter.ExactInputSingleParams memory _eisp = ISwapRouter
      .ExactInputSingleParams({
          tokenIn: _wc.swapParams.tokenFrom,
          tokenOut: _wc.swapParams.tokenTo,
          fee: 3000,
          recipient: _wc.user,
          deadline: block.timestamp,
          amountIn: IERC20(_wc.swapParams.tokenFrom).balanceOf(address(this)),
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
      });

    ISwapRouter(univ3Router).exactInputSingle(_eisp);

    // Using GMX
    // Send native token for execution fee
    // IExchangeRouter(exchangeRouter).sendWnt{value: _wc.swapParams.executionFee}(
    //   orderVault,
    //   _wc.swapParams.executionFee
    // );

    // // Send tokens
    // IExchangeRouter(exchangeRouter).sendTokens(
    //   _wc.swapParams.tokenFrom,
    //   orderVault,
    //   IERC20(_wc.swapParams.tokenFrom).balanceOf(address(this))
    // );

    // cop.addresses.initialCollateralToken = _wc.swapParams.tokenFrom;
    // cop.numbers.executionFee = _wc.swapParams.executionFee;

    // // Returns bytes32 orderKey
    // orderKey = IExchangeRouter(exchangeRouter).createOrder(cop);
  }


  function postSwap() external {
    callbackCalled2 = true;
    IERC20(_wc.swapParams.tokenTo).safeTransfer(
      _wc.user,
      IERC20(_wc.swapParams.tokenTo).balanceOf(address(this))
    );
  }

  function resetVault() external {
    IWNT(WNT).withdraw(IWNT(WNT).balanceOf(address(this)));
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    IERC20(tokenA).safeTransfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));
    IERC20(tokenB).safeTransfer(msg.sender, IERC20(tokenB).balanceOf(address(this)));
    IERC20(lpToken).safeTransfer(msg.sender, IERC20(lpToken).balanceOf(address(this)));

    callbackCalled = false;
    swapCalled = false;
    callbackCalled2 = false;
  }

  receive() external payable {
    // refunder = msg.sender;
    // refundAmtReceived = msg.value;

    if (msg.sender == depositVault) {
      (bool success, ) = payable(_dc.user).call{value: msg.value}("");
      require(success, "Transfer failed.");
    } else if (msg.sender == withdrawalVault) {
      (bool success, ) = payable(_wc.user).call{value: msg.value}("");
      require(success, "Transfer failed.");
    } else if (msg.sender == orderVault) {
      (bool success, ) = payable(_wc.user).call{value: msg.value}("");
      require(success, "Transfer failed.");
    }

    // if (
    //   msg.sender == depositVault ||
    //   msg.sender == withdrawalVault ||
    //   msg.sender == orderVault
    // ) {
    //   // TODO can't withdraw everything if we need it for swap too
    //   (bool success, ) = payable(_dc.user).call{value: address(this).balance}("");
    //   require(success, "Transfer failed.");
    // }
  }
}

