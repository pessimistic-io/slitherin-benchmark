// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IWNT } from "./IWNT.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";

contract GMXTest {
  using SafeERC20 for IERC20;

  struct AddLiquidityParams {
    address payable user;
    // Amount of tokenA to add liquidity
    uint256 tokenAAmt;
    // Amount of tokenB to add liquidity
    uint256 tokenBAmt;
    // Slippage tolerance for adding liquidity; e.g. 3 = 0.03%
    uint256 slippage;
    // Execution fee sent to GMX for adding liquidity
    uint256 executionFee;
    uint256 callbackGaslimit;
    bool unwrap;
  }

  AddLiquidityParams public _alp;
  bytes32 public depositKey;
  bool public callbackCalled;
  uint256 public actualExecutionFee;


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

  function addLiquidity(
    AddLiquidityParams memory alp
  ) payable external returns (bytes32) {

    IERC20(tokenA).safeTransferFrom(msg.sender, address(this), alp.tokenAAmt);
    IERC20(tokenB).safeTransferFrom(msg.sender, address(this), alp.tokenBAmt);
    actualExecutionFee = msg.value;

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
        shouldUnwrapNativeToken: alp.unwrap,
        executionFee: alp.executionFee,
        callbackGasLimit: alp.callbackGaslimit
      });

    depositKey = IExchangeRouter(exchangeRouter).createDeposit(_cdp);
  }

  function postDeposit() external {
    // uint256 balance = IWNT(WNT).balanceOf(address(this));
    IWNT(WNT).withdraw(IWNT(WNT).balanceOf(address(this)));
    (bool success, ) = payable(_alp.user).call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    callbackCalled = true;

    // IERC20(tokenA).safeTransfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));
    // IERC20(tokenB).safeTransfer(msg.sender, IERC20(tokenB).balanceOf(address(this)));
    // IERC20(lpToken).safeTransfer(msg.sender, IERC20(lpToken).balanceOf(address(this)));
  }

  function resetVault() external {
    IWNT(WNT).withdraw(IWNT(WNT).balanceOf(address(this)));
    (bool success, ) = msg.sender.call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    IERC20(tokenA).safeTransfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));
    IERC20(tokenB).safeTransfer(msg.sender, IERC20(tokenB).balanceOf(address(this)));
    IERC20(lpToken).safeTransfer(msg.sender, IERC20(lpToken).balanceOf(address(this)));

    callbackCalled = false;
  }

  function resetVault2() external {
    IERC20(tokenA).safeTransfer(msg.sender, IERC20(tokenA).balanceOf(address(this)));
    IERC20(tokenB).safeTransfer(msg.sender, IERC20(tokenB).balanceOf(address(this)));
    IERC20(lpToken).safeTransfer(msg.sender, IERC20(lpToken).balanceOf(address(this)));

    callbackCalled = false;
  }

  receive() external payable {
    // require(msg.sender == WNT, "msg.sender != WNT");
  }
}

