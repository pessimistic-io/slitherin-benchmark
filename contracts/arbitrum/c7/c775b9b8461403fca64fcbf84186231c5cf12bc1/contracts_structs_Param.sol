// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

/// @dev The parameter for calling the collect protocol fees function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param token0To The receiver of any token0 ERC20 tokens.
/// @param token1To The receiver of any token1 ERC20 tokens.
/// @param excessLong0To The receiver of any excess long0 ERC1155 tokens.
/// @param excessLong1To The receiver of any excess long1 ERC1155 tokens.
/// @param excessShortTo The receiver of any excess short ERC1155 tokens.
/// @param long0Requested The maximum amount of long0 fees.
/// @param long1Requested The maximum amount of long1 fees.
/// @param shortRequested The maximum amount of short fees.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryCollectProtocolFeesParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address token0To;
  address token1To;
  address excessLong0To;
  address excessLong1To;
  address excessShortTo;
  uint256 long0Requested;
  uint256 long1Requested;
  uint256 shortRequested;
  bytes data;
}

/// @dev The parameter for calling the add liquidity function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param liquidityTo The receiver of the liquidity position ERC1155 tokens.
/// @param token0Amount The amount of token0 ERC20 tokens to deposit.
/// @param token1Amount The amount of token1 ERC20 tokens to deposit.
/// @param data The bytes data passed to callback.
/// @param erc1155Data The bytes data passed to the receiver of liquidity position ERC1155 tokens.
struct TimeswapV2PeripheryAddLiquidityGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address liquidityTo;
  uint256 token0Amount;
  uint256 token1Amount;
  bytes data;
  bytes erc1155Data;
}

/// @dev The parameter for calling the remove liquidity function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param token0To The receiver of any token0 ERC20 tokens.
/// @param token1To The receiver of any token1 ERC20 tokens.
/// @param liquidityAmount The amount of liquidity ERC1155 tokens to burn.
/// @param excessLong0Amount The amount of long0 ERC1155 tokens to include in matching long and short positions.
/// @param excessLong1Amount The amount of long1 ERC1155 tokens to include in matching long and short positions.
/// @param excessShortAmount The amount of short ERC1155 tokens to include in matching long and short positions.
struct TimeswapV2PeripheryRemoveLiquidityGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address token0To;
  address token1To;
  uint160 liquidityAmount;
  uint256 excessLong0Amount;
  uint256 excessLong1Amount;
  uint256 excessShortAmount;
  bytes data;
}

/// @dev A struct describing how much fees and short returned are withdrawn from the pool.
/// @param long0Fees The number of long0 fees withdrwan from the pool.
/// @param long1Fees The number of long1 fees withdrwan from the pool.
/// @param shortFees The number of short fees withdrwan from the pool.
/// @param shortReturned The number of short returned withdrwan from the pool.
struct FeesAndReturnedDelta {
  uint256 long0Fees;
  uint256 long1Fees;
  uint256 shortFees;
  uint256 shortReturned;
}

/// @dev A struct describing how much long and short position are removed or added.
/// @param isRemoveLong0 True if long0 excess is removed from the user.
/// @param isRemoveLong1 True if long1 excess is removed from the user.
/// @param isRemoveShort True if short excess is removed from the user.
/// @param long0Amount The number of excess long0 is removed or added.
/// @param long1Amount The number of excess long1 is removed or added.
/// @param shortAmount The number of excess short is removed or added.
struct ExcessDelta {
  bool isRemoveLong0;
  bool isRemoveLong1;
  bool isRemoveShort;
  uint256 long0Amount;
  uint256 long1Amount;
  uint256 shortAmount;
}

/// @dev The parameter for calling the collect function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param token0To The receiver of any token0 ERC20 tokens.
/// @param token1To The receiver of any token1 ERC20 tokens.
/// @param excessShortAmount The amount of short ERC1155 tokens to burn.
struct TimeswapV2PeripheryCollectParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address token0To;
  address token1To;
  uint256 excessShortAmount;
}

/// @dev The parameter for calling the lend given principal function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param to The receiver of short position.
/// @param token0Amount The amount of token0 ERC20 tokens to deposit.
/// @param token1Amount The amount of token1 ERC20 tokens to deposit.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryLendGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  uint256 token0Amount;
  uint256 token1Amount;
  bytes data;
}

/// @dev The parameter for calling the close borrow given position function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param to The receiver of the ERC20 tokens.
/// @param isLong0 True if the caller wants to close long0 positions, false if the caller wants to close long1 positions.
/// @param positionAmount The amount of chosen long positions to close.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryCloseBorrowGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address to;
  bool isLong0;
  uint256 positionAmount;
  bytes data;
}

/// @dev The parameter for calling the borrow given principal function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param tokenTo The receiver of the ERC20 tokens.
/// @param longTo The receiver of the long ERC1155 positions.
/// @param isLong0 True if the caller wants to receive long0 positions, false if the caller wants to receive long1 positions.
/// @param token0Amount The amount of token0 ERC20 to borrow.
/// @param token1Amount The amount of token1 ERC20 to borrow.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryBorrowGivenPrincipalParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  address longTo;
  bool isLong0;
  uint256 token0Amount;
  uint256 token1Amount;
  bytes data;
}

/// @dev The parameter for calling the borrow given position function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param tokenTo The receiver of the ERC20 tokens.
/// @param longTo The receiver of the long ERC1155 positions.
/// @param isLong0 True if the caller wants to receive long0 positions, false if the caller wants to receive long1 positions.
/// @param positionAmount The amount of long position to receive.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryBorrowGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  address longTo;
  bool isLong0;
  uint256 positionAmount;
  bytes data;
}

/// @dev The parameter for calling the close lend given position function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param token0To The receiver of any token0 ERC20 tokens.
/// @param token1To The receiver of any token1 ERC20 tokens.
/// @param positionAmount The amount of long position to receive.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryCloseLendGivenPositionParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address token0To;
  address token1To;
  uint256 positionAmount;
  bytes data;
}

/// @dev The parameter for calling the rebalance function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param tokenTo The receiver of the ERC20 tokens.
/// @param excessShortTo The receiver of any excess short ERC1155 tokens.
/// @param isLong0ToLong1 True if transforming long0 position to long1 position, false if transforming long1 position to long0 position.
/// @param givenLong0 True if the amount is in long0 position, false if the amount is in long1 position.
/// @param tokenAmount The amount of token amount given isLong0ToLong1 and givenLong0.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryRebalanceParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  address excessShortTo;
  bool isLong0ToLong1;
  bool givenLong0;
  uint256 tokenAmount;
  bytes data;
}

/// @dev The parameter for calling the redeem function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param token0To The receiver of any token0 ERC20 tokens.
/// @param token1To The receiver of any token1 ERC20 tokens.
/// @param token0AndLong0Amount The amount of token0 to receive and long0 to burn.
/// @param token1AndLong1Amount The amount of token1 to receive and long1 to burn.
struct TimeswapV2PeripheryRedeemParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address token0To;
  address token1To;
  uint256 token0AndLong0Amount;
  uint256 token1AndLong1Amount;
}

/// @dev The parameter for calling the transform function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param tokenTo The receiver of the ERC20 tokens.
/// @param longTo The receiver of the ERC1155 long positions.
/// @param isLong0ToLong1 True if transforming long0 position to long1 position, false if transforming long1 position to long0 position.
/// @param positionAmount The amount of long amount given isLong0ToLong1 and givenLong0.
/// @param data The bytes data passed to callback.
struct TimeswapV2PeripheryTransformParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address tokenTo;
  address longTo;
  bool isLong0ToLong1;
  uint256 positionAmount;
  bytes data;
}

/// @dev The parameter for calling the withdraw function.
/// @param token0 The address of the smaller size ERC20 contract.
/// @param token1 The address of the larger size ERC20 contract.
/// @param strike The strike price of the position in UQ128.128.
/// @param maturity The maturity of the position in seconds.
/// @param token0To The receiver of any token0 ERC20 tokens.
/// @param token1To The receiver of any token1 ERC20 tokens.
/// @param positionAmount The amount of short ERC1155 tokens to burn.
struct TimeswapV2PeripheryWithdrawParam {
  address token0;
  address token1;
  uint256 strike;
  uint256 maturity;
  address token0To;
  address token1To;
  uint256 positionAmount;
}

