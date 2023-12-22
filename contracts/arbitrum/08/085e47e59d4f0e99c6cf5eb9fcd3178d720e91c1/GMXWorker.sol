// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";
import { GMXTypes } from "./GMXTypes.sol";

library GMXWorker {

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Add strategy's tokens for liquidity and receive LP tokens
    * @param self Vault store data
    * @param alp GMXTypes.AddLiquidityParams
    * @return depositKey Hashed key of created deposit in bytes32
  */
  function addLiquidity(
    GMXTypes.Store storage self,
    GMXTypes.AddLiquidityParams memory alp
  ) external returns (bytes32) {
    // Send native token for execution fee
    self.exchangeRouter.sendWnt{ value: alp.executionFee }(
      self.depositVault,
      alp.executionFee
    );

    // Send tokens
    self.exchangeRouter.sendTokens(
      address(self.tokenA),
      self.depositVault,
      alp.tokenAAmt
    );

    self.exchangeRouter.sendTokens(
      address(self.tokenB),
      self.depositVault,
      alp.tokenBAmt
    );

    // TODO calculate slippage in minMarketTokens
    // alp.slippage

    // Create deposit
    IExchangeRouter.CreateDepositParams memory _cdp =
      IExchangeRouter.CreateDepositParams({
        receiver: address(this),
        callbackContract: self.callback,
        uiFeeReceiver: address(0), // TODO uiFeeReceiver?
        market: address(self.lpToken),
        initialLongToken: address(self.tokenA),
        initialShortToken: address(self.tokenB),
        longTokenSwapPath: new address[](0),
        shortTokenSwapPath: new address[](0),
        minMarketTokens: 0,
        shouldUnwrapNativeToken: false,
        executionFee: alp.executionFee,
        callbackGasLimit: 2000000
      });

    return self.exchangeRouter.createDeposit(_cdp);
  }

  /**
    * @dev Remove liquidity of strategy's LP token and receive underlying tokens
    * @param self Vault store data
    * @param rlp GMXTypes.RemoveLiquidityParams
    * @return withdrawKey Hashed key of created withdraw in bytes32
  */
  function removeLiquidity(
    GMXTypes.Store storage self,
    GMXTypes.RemoveLiquidityParams memory rlp
  ) external returns (bytes32) {
    // Send native token for execution fee
    self.exchangeRouter.sendWnt{value: rlp.executionFee }(
      self.withdrawalVault,
      rlp.executionFee
    );

    // Send GM LP tokens
    self.exchangeRouter.sendTokens(
      address(self.lpToken),
      self.withdrawalVault,
      rlp.lpTokenAmt
    );

    // TODO address slippage
    // TODO address slippage in minLongTokenAmount/minShortTokenAmount

    // Create withdrawal
    IExchangeRouter.CreateWithdrawalParams memory _cwp =
      IExchangeRouter.CreateWithdrawalParams({
        receiver: address(this),
        callbackContract: self.callback,
        uiFeeReceiver: address(0),
        market: address(self.lpToken),
        longTokenSwapPath: new address[](0),
        shortTokenSwapPath: new address[](0),
        minLongTokenAmount: 0,
        minShortTokenAmount: 0,
        shouldUnwrapNativeToken: false,
        executionFee: rlp.executionFee,
        callbackGasLimit: 2000000
      });

    return self.exchangeRouter.createWithdrawal(_cwp);
  }

  /**
    * @dev Swap one token for another token
    * @param self Vault store data
    * @param sp GMXTypes.SwapParams struct
    * @return swapKey Key hash of order created
  */
  function swap(
    GMXTypes.Store storage self,
    GMXTypes.SwapParams memory sp
  ) external returns (bytes32) {
    // Send native token for execution fee
    self.exchangeRouter.sendWnt{value: sp.executionFee}(
      self.orderVault,
      sp.executionFee
    );

    // Send tokens
    self.exchangeRouter.sendTokens(
      sp.tokenFrom,
      self.orderVault,
      sp.tokenFromAmt
    );

    address[] memory _swapPath = new address[](1);
    _swapPath[0] = address(self.lpToken);

    IExchangeRouter.CreateOrderParamsAddresses memory _addresses;
    _addresses.receiver = address(this);
    _addresses.initialCollateralToken = sp.tokenFrom;
    _addresses.callbackContract = self.callback;
    _addresses.market = address(0);
    _addresses.swapPath = _swapPath;
    _addresses.uiFeeReceiver = address(0);

    IExchangeRouter.CreateOrderParamsNumbers memory _numbers;
    _numbers.sizeDeltaUsd = 0;
    _numbers.initialCollateralDeltaAmount = 0;
    _numbers.triggerPrice = 0;
    _numbers.acceptablePrice = 0;
    _numbers.executionFee = sp.executionFee;
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
    return self.exchangeRouter.createOrder(_params);

    // Note that keeper is needed to continue the swap once GMX keeper has fulfilled it
  }
}

