// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IExchangeRouter } from "./IExchangeRouter.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
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
        minMarketTokens: alp.minMarketTokenAmt,
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
      rlp.lpAmt
    );

    // Create withdrawal
    IExchangeRouter.CreateWithdrawalParams memory _cwp =
      IExchangeRouter.CreateWithdrawalParams({
        receiver: address(this),
        callbackContract: self.callback,
        uiFeeReceiver: address(0),
        market: address(self.lpToken),
        longTokenSwapPath: rlp.tokenASwapPath,
        shortTokenSwapPath: rlp.tokenBSwapPath,
        minLongTokenAmount: rlp.minTokenAAmt,
        minShortTokenAmount: rlp.minTokenBAmt,
        shouldUnwrapNativeToken: false,
        executionFee: rlp.executionFee,
        callbackGasLimit: 2000000
      });

    return self.exchangeRouter.createWithdrawal(_cwp);
  }

  /**
    * @dev Swap one token for another token
    * @param self Vault store data
    * @param sp GMXTypes.SwapParams
    * @return amountOut token amount in token decimals
  */
  function swap(
    GMXTypes.Store storage self,
    GMXTypes.SwapParams memory sp
  ) external returns (uint256) {
    // TODO: slippage and fee calculation

    ISwapRouter.ExactInputSingleParams memory _eisp =
      ISwapRouter.ExactInputSingleParams({
        tokenIn: sp.tokenIn,
        tokenOut: sp.tokenOut,
        fee: 3000,
        recipient: address(this),
        deadline: sp.deadline,
        amountIn: sp.amountIn,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
      });

    return self.uniV3Router.exactInputSingle(_eisp);
  }
}

