// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {Error} from "./Error.sol";
import {Math} from "./Math.sol";
import {StrikeConversion} from "./StrikeConversion.sol";

import {ITimeswapV2Option} from "./ITimeswapV2Option.sol";

import {OptionFactoryLibrary} from "./OptionFactory.sol";

import {TimeswapV2OptionMintParam} from "./structs_Param.sol";
import {TimeswapV2OptionMintCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2OptionMint} from "./enums_Transaction.sol";
import {TimeswapV2OptionPosition} from "./structs_Position.sol";

import {TimeswapV2PoolMintParam} from "./v2-pool_contracts_structs_Param.sol";
import {TimeswapV2PoolMintChoiceCallbackParam, TimeswapV2PoolMintCallbackParam, TimeswapV2PoolAddFeesCallbackParam} from "./structs_CallbackParam.sol";

import {TimeswapV2PoolMint} from "./enums_Transaction.sol";

import {ITimeswapV2Pool} from "./ITimeswapV2Pool.sol";

import {PoolFactoryLibrary} from "./PoolFactory.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";

import {TimeswapV2TokenMintParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2TokenMintCallbackParam} from "./contracts_structs_CallbackParam.sol";

import {ITimeswapV2LiquidityToken} from "./ITimeswapV2LiquidityToken.sol";

import {TimeswapV2LiquidityTokenMintParam} from "./v2-token_contracts_structs_Param.sol";
import {TimeswapV2LiquidityTokenMintCallbackParam} from "./contracts_structs_CallbackParam.sol";

import {ITimeswapV2PeripheryAddLiquidityGivenPrincipal} from "./ITimeswapV2PeripheryAddLiquidityGivenPrincipal.sol";

import {TimeswapV2PeripheryAddLiquidityGivenPrincipalParam} from "./structs_Param.sol";
import {TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam, TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam} from "./InternalParam.sol";

import {Verify} from "./Verify.sol";

/// @title Abstract contract which specifies functions that are required for liquidity provision which are to be inherited for a specific DEX/Aggregator implementation
abstract contract TimeswapV2PeripheryAddLiquidityGivenPrincipal is ITimeswapV2PeripheryAddLiquidityGivenPrincipal {
  using Math for uint256;

  /* ===== MODEL ===== */

  /// @inheritdoc ITimeswapV2PeripheryAddLiquidityGivenPrincipal
  address public immutable override optionFactory;
  /// @inheritdoc ITimeswapV2PeripheryAddLiquidityGivenPrincipal
  address public immutable override poolFactory;
  /// @inheritdoc ITimeswapV2PeripheryAddLiquidityGivenPrincipal
  address public immutable override tokens;
  /// @inheritdoc ITimeswapV2PeripheryAddLiquidityGivenPrincipal
  address public immutable override liquidityTokens;

  /* ===== INIT ===== */

  constructor(
    address chosenOptionFactory,
    address chosenPoolFactory,
    address chosenTokens,
    address chosenLiquidityTokens
  ) {
    optionFactory = chosenOptionFactory;
    poolFactory = chosenPoolFactory;
    tokens = chosenTokens;
    liquidityTokens = chosenLiquidityTokens;
  }

  /// @notice the abstract implementation for addLiquidity function
  /// @param param params for  addLiquidity as mentioned in the TimeswapV2PeripheryAddLiquidityGivenPrincipalParam struct
  /// @return liquidityAmount amount of liquidity in the pool
  /// @return excessLong0Amount amount os excessLong0Amount while liquidity was minted if any
  /// @return excessLong1Amount amount os excessLong1Amount while liquidity was minted if any
  /// @return excessShortAmount amount os shortAmount while liquidity was minted if any
  /// @return data data passed as bytes in the param
  function addLiquidityGivenPrincipal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalParam memory param
  )
    internal
    returns (
      uint160 liquidityAmount,
      uint256 excessLong0Amount,
      uint256 excessLong1Amount,
      uint256 excessShortAmount,
      bytes memory data
    )
  {
    (, address poolPair) = PoolFactoryLibrary.getWithCheck(optionFactory, poolFactory, param.token0, param.token1);

    data = abi.encode(
      param.token0,
      param.token1,
      param.liquidityTo,
      param.token0Amount,
      param.token1Amount,
      param.data
    );

    // Mint liquidity token given the amount of principal to be deposited
    // Calling this function, the next logic goes to timeswapV2PoolMintChoiceCallback function
    (liquidityAmount, , , , data) = ITimeswapV2Pool(poolPair).mint(
      TimeswapV2PoolMintParam({
        strike: param.strike,
        maturity: param.maturity,
        to: address(this),
        transaction: TimeswapV2PoolMint.GivenLarger,
        delta: StrikeConversion.combine(param.token0Amount, param.token1Amount, param.strike, false),
        data: data
      })
    );

    (excessLong0Amount, excessLong1Amount, excessShortAmount, data) = abi.decode(
      data,
      (uint256, uint256, uint256, bytes)
    );

    // Wraps the liquidity token to ERC1155 standard
    // Calling this function, the next logic goes to timeswapV2LiquidityTokenMintCallback function
    ITimeswapV2LiquidityToken(liquidityTokens).mint(
      TimeswapV2LiquidityTokenMintParam({
        token0: param.token0,
        token1: param.token1,
        strike: param.strike,
        maturity: param.maturity,
        to: param.liquidityTo,
        liquidityAmount: liquidityAmount,
        data: bytes(""),
        erc1155Data: param.erc1155Data
      })
    );

    // If there is any excess option positions, wraps them to ERC1155 standard
    if (excessLong0Amount != 0 || excessLong1Amount != 0 || excessShortAmount != 0)
      ITimeswapV2Token(tokens).mint(
        TimeswapV2TokenMintParam({
          token0: param.token0,
          token1: param.token1,
          strike: param.strike,
          maturity: param.maturity,
          long0To: param.liquidityTo,
          long1To: param.liquidityTo,
          shortTo: param.liquidityTo,
          long0Amount: excessLong0Amount,
          long1Amount: excessLong1Amount,
          shortAmount: excessShortAmount,
          data: bytes("")
        })
      );
  }

  /// @notice the abstract implementation for TimeswapV2PoolMintChoiceCallback
  /// @param param params for mintChoiceCallBack from TimeswapV2Pool
  /// @return long0Amount long0AMount chosen to be minted
  /// @return long1Amount chosen to be minted
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PoolMintChoiceCallback(
    TimeswapV2PoolMintChoiceCallbackParam calldata param
  ) external override returns (uint256 long0Amount, uint256 long1Amount, bytes memory data) {
    address token0;
    address token1;
    address liquidityTo;
    uint256 token0Amount;
    uint256 token1Amount;
    (token0, token1, liquidityTo, token0Amount, token1Amount, data) = abi.decode(
      param.data,
      (address, address, address, uint256, uint256, bytes)
    );

    Verify.timeswapV2Pool(optionFactory, poolFactory, token0, token1);

    // We will mint equivalent amount of long and short, but the pool require different ratio of long and short
    // Determine here that after depositing long and short into the pool, if we will get some excess long or excess short
    bool isShortExcess = param.shortAmount < param.longAmount;
    if (isShortExcess) {
      // Since all the long minted will be deposited, there is no choice on how much long0 and long1 to be deposited, all will be deposited
      long0Amount = token0Amount;
      long1Amount = token1Amount;
    } else {
      // Since not all the long minted will be deposited, ask the inheritor contract to decide how much of long0 and long1 will be deposited
      (long0Amount, long1Amount, data) = timeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternal(
        TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam({
          token0: token0,
          token1: token1,
          strike: param.strike,
          maturity: param.maturity,
          token0Amount: token0Amount,
          token1Amount: token1Amount,
          liquidityAmount: param.liquidityAmount,
          tokenAmount: param.longAmount,
          data: data
        })
      );

      // Checks that the decision from the inheritor contract fits the limit of the number of long0 and long1 minted
      Error.checkEnough(token0Amount, long0Amount);
      Error.checkEnough(token1Amount, long1Amount);
    }

    data = abi.encode(
      CacheForTimeswapV2PoolMintCallback(token0, token1, isShortExcess, token0Amount, token1Amount),
      data
    );

    // the next logic goes to timeswapV2PoolMintCallback function
  }

  // We need to cache the information into a struct to avoid stack too deep error
  struct CacheForTimeswapV2PoolMintCallback {
    address token0;
    address token1;
    bool isShortExcess;
    uint256 token0Amount;
    uint256 token1Amount;
  }

  /// @notice the abstract implementation for TimeswapV2PoolMintCallback
  /// @param param params for mintCallBack from TimeswapV2Pool
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PoolMintCallback(
    TimeswapV2PoolMintCallbackParam calldata param
  ) external override returns (bytes memory data) {
    CacheForTimeswapV2PoolMintCallback memory cache;
    (cache, data) = abi.decode(param.data, (CacheForTimeswapV2PoolMintCallback, bytes));

    address optionPair = Verify.timeswapV2Pool(optionFactory, poolFactory, cache.token0, cache.token1);

    data = abi.encode(cache.token0, cache.token1, param.liquidityAmount, data);

    // We now mint the long and short positions
    // If short excess, this means the full long minted can be transferred directly to the pool
    // If long excess, this means the full short minted can be transferred directly to the pool
    // Any long or short position minted, where the full amount is not required by the pool, will be transferred to this contract
    // Calling this function, the next logic goes to timeswapV2OptionMintCallback function
    uint256 shortAmountMinted;
    (, , shortAmountMinted, data) = ITimeswapV2Option(optionPair).mint(
      TimeswapV2OptionMintParam({
        strike: param.strike,
        maturity: param.maturity,
        long0To: cache.isShortExcess ? msg.sender : address(this),
        long1To: cache.isShortExcess ? msg.sender : address(this),
        shortTo: cache.isShortExcess ? address(this) : msg.sender,
        transaction: TimeswapV2OptionMint.GivenTokensAndLongs,
        amount0: cache.token0Amount,
        amount1: cache.token1Amount,
        data: data
      })
    );

    uint256 excessLong0Amount;
    uint256 excessLong1Amount;
    uint256 excessShortAmount;
    if (cache.isShortExcess) {
      // The full short positiion minted is transferred to this contract
      // We only need a portion of it transferred to the pool
      // The remaining short portion is the excess short amount
      ITimeswapV2Option(optionPair).transferPosition(
        param.strike,
        param.maturity,
        msg.sender,
        TimeswapV2OptionPosition.Short,
        param.shortAmount
      );

      excessShortAmount = shortAmountMinted.unsafeSub(param.shortAmount);
    } else {
      // The full long position minted is transferred to this contract
      // We only need a portion of it transferred to the pool
      // The remaining long portion is the excess long0 amount and excess long1 amount
      excessLong0Amount = cache.token0Amount;
      excessLong1Amount = cache.token1Amount;
      if (param.long0Amount != 0) {
        ITimeswapV2Option(optionPair).transferPosition(
          param.strike,
          param.maturity,
          msg.sender,
          TimeswapV2OptionPosition.Long0,
          param.long0Amount
        );

        excessLong0Amount = excessLong0Amount.unsafeSub(param.long0Amount);
      }

      if (param.long1Amount != 0) {
        ITimeswapV2Option(optionPair).transferPosition(
          param.strike,
          param.maturity,
          msg.sender,
          TimeswapV2OptionPosition.Long1,
          param.long1Amount
        );

        excessLong1Amount = excessLong1Amount.unsafeSub(param.long1Amount);
      }
    }

    data = abi.encode(excessLong0Amount, excessLong1Amount, excessShortAmount, data);

    // The next logic goes back to after we call the timeswapV2Pool mint function
  }

  /// @notice the abstract implementation for TimeswapV2OptionMintCallback
  /// @param param params for mintCallBack from TimeswapV2Option
  /// @return data data passed in bytes in the param passed back
  function timeswapV2OptionMintCallback(
    TimeswapV2OptionMintCallbackParam memory param
  ) external override returns (bytes memory data) {
    address token0;
    address token1;
    uint256 liquidityAmount;
    (token0, token1, liquidityAmount, data) = abi.decode(param.data, (address, address, uint256, bytes));

    Verify.timeswapV2Option(optionFactory, token0, token1);

    // Ask the inheritor contract to transfer the required ERC20 tokens to the option pair contract
    data = timeswapV2PeripheryAddLiquidityGivenPrincipalInternal(
      TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam({
        optionPair: msg.sender,
        token0: token0,
        token1: token1,
        strike: param.strike,
        maturity: param.maturity,
        token0Amount: param.token0AndLong0Amount,
        token1Amount: param.token1AndLong1Amount,
        liquidityAmount: liquidityAmount,
        data: data
      })
    );
  }

  /// @notice the abstract implementation for TimeswapV2LiquidityTokenMintCallback
  /// @param param params for mintCallBack from TimeswapV2LiquidityToken
  /// @return data data passed in bytes in the param passed back
  function timeswapV2LiquidityTokenMintCallback(
    TimeswapV2LiquidityTokenMintCallbackParam calldata param
  ) external override returns (bytes memory data) {
    Verify.timeswapV2LiquidityToken(liquidityTokens);

    (, address poolPair) = PoolFactoryLibrary.get(optionFactory, poolFactory, param.token0, param.token1);

    // Transfer the liquidity to the ERC1155 wrapper contract
    ITimeswapV2Pool(poolPair).transferLiquidity(param.strike, param.maturity, msg.sender, param.liquidityAmount);

    data = bytes("");

    // The logic goes back to after we call the timeswapV2LiquidityToken mint function
  }

  /// @notice the abstract implementation for TimeswapV2TokenMintCallback
  /// @param param params for mintCallBack from TimeswapV2Token
  /// @return data data passed in bytes in the param passed back
  function timeswapV2TokenMintCallback(
    TimeswapV2TokenMintCallbackParam calldata param
  ) external returns (bytes memory data) {
    Verify.timeswapV2Token(tokens);

    address optionPair = OptionFactoryLibrary.get(optionFactory, param.token0, param.token1);

    // Transfer the long0, long1, and short position to the ERC1155 wrapper contract
    if (param.long0Amount != 0)
      ITimeswapV2Option(optionPair).transferPosition(
        param.strike,
        param.maturity,
        msg.sender,
        TimeswapV2OptionPosition.Long0,
        param.long0Amount
      );

    if (param.long1Amount != 0)
      ITimeswapV2Option(optionPair).transferPosition(
        param.strike,
        param.maturity,
        msg.sender,
        TimeswapV2OptionPosition.Long1,
        param.long1Amount
      );

    if (param.shortAmount != 0)
      ITimeswapV2Option(optionPair).transferPosition(
        param.strike,
        param.maturity,
        msg.sender,
        TimeswapV2OptionPosition.Short,
        param.shortAmount
      );

    data = bytes("");

    // The logic goes back to after we call the timeswapV2Token mint function
  }

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2AddLiquidity
  /// @notice will only be called if there is excess long
  /// @param param params for calling the implementation specfic addLiquidity to be overriden
  /// @return token0Amount amount of token0 to be deposited into the pool
  /// @return token1Amount amount of token1 to be deposited into the pool
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalChoiceInternalParam memory param
  ) internal virtual returns (uint256 token0Amount, uint256 token1Amount, bytes memory data);

  /// @notice the implementation which is to be overriden for DEX/Aggregator specific logic for TimeswapV2AddLiquidity
  /// @param param params for calling the implementation specfic addLiquidity to be overriden
  /// @return data data passed in bytes in the param passed back
  function timeswapV2PeripheryAddLiquidityGivenPrincipalInternal(
    TimeswapV2PeripheryAddLiquidityGivenPrincipalInternalParam memory param
  ) internal virtual returns (bytes memory data);
}

