// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.8;

import {IERC1155Enumerable} from "./IERC1155Enumerable.sol";

import {TimeswapV2LiquidityTokenPosition} from "./structs_Position.sol";
import {TimeswapV2LiquidityTokenMintParam, TimeswapV2LiquidityTokenBurnParam, TimeswapV2LiquidityTokenCollectParam} from "./structs_Param.sol";

/// @title An interface for TS-V2 liquidity token system
interface ITimeswapV2LiquidityToken is IERC1155Enumerable {
  error NotApprovedToTransferFees();

  /// @dev Returns the option factory address.
  /// @return optionFactory The option factory address.
  function optionFactory() external view returns (address);

  /// @dev Returns the pool factory address.
  /// @return poolFactory The pool factory address.
  function poolFactory() external view returns (address);

  /// @dev Returns the position Balance of the owner
  /// @param owner The owner of the token
  /// @param position The liquidity position
  function positionOf(
    address owner,
    TimeswapV2LiquidityTokenPosition calldata position
  ) external view returns (uint256 amount);

  /// @dev Returns the fee and short returned growth of the pool
  /// @param position The liquidity position
  /// @return long0FeeGrowth The long0 fee growth
  /// @return long1FeeGrowth The long1 fee growth
  /// @return shortFeeGrowth The short fee growth
  /// @return shortReturnedGrowth The short returned growth
  function feesEarnedAndShortReturnedGrowth(
    TimeswapV2LiquidityTokenPosition calldata position
  )
    external
    view
    returns (uint256 long0FeeGrowth, uint256 long1FeeGrowth, uint256 shortFeeGrowth, uint256 shortReturnedGrowth);

  /// @dev Returns the fee and short returned growth of the pool
  /// @param position The liquidity position
  /// @param durationForward The time duration forward
  /// @return long0FeeGrowth The long0 fee growth
  /// @return long1FeeGrowth The long1 fee growth
  /// @return shortFeeGrowth The short fee growth
  /// @return shortReturnedGrowth The short returned growth
  function feesEarnedAndShortReturnedGrowth(
    TimeswapV2LiquidityTokenPosition calldata position,
    uint96 durationForward
  )
    external
    view
    returns (uint256 long0FeeGrowth, uint256 long1FeeGrowth, uint256 shortFeeGrowth, uint256 shortReturnedGrowth);

  /// @param owner The address to query the fees earned and short returned of.
  /// @param position The liquidity token position.
  /// @return long0Fees The amount of long0 fees owned by the given address.
  /// @return long1Fees The amount of long1 fees owned by the given address.
  /// @return shortFees The amount of short fees owned by the given address.
  /// @return shortReturned The amount of short returned owned by the given address.
  function feesEarnedAndShortReturnedOf(
    address owner,
    TimeswapV2LiquidityTokenPosition calldata position
  ) external view returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees, uint256 shortReturned);

  /// @param owner The address to query the fees earned and short returned of.
  /// @param position The liquidity token position.
  /// @param durationForward The time duration forward
  /// @return long0Fees The amount of long0 fees owned by the given address.
  /// @return long1Fees The amount of long1 fees owned by the given address.
  /// @return shortFees The amount of short fees owned by the given address.
  /// @return shortReturned The amount of short returned owned by the given address.
  function feesEarnedAndShortReturnedOf(
    address owner,
    TimeswapV2LiquidityTokenPosition calldata position,
    uint96 durationForward
  ) external view returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees, uint256 shortReturned);

  /// @dev Transfers position token TimeswapV2Token from `from` to `to`
  /// @param from The address to transfer position token from
  /// @param to The address to transfer position token to
  /// @param position The TimeswapV2Token Position to transfer
  /// @param liquidityAmount The amount of TimeswapV2Token Position to transfer
  /// @param erc1155Data Aribtrary custom data for erc1155 transfer
  function transferTokenPositionFrom(
    address from,
    address to,
    TimeswapV2LiquidityTokenPosition calldata position,
    uint160 liquidityAmount,
    bytes calldata erc1155Data
  ) external;

  /// @dev mints TimeswapV2LiquidityToken as per the liqudityAmount
  /// @param param The TimeswapV2LiquidityTokenMintParam
  /// @return data Arbitrary data
  function mint(TimeswapV2LiquidityTokenMintParam calldata param) external returns (bytes memory data);

  /// @dev burns TimeswapV2LiquidityToken as per the liqudityAmount
  /// @param param The TimeswapV2LiquidityTokenBurnParam
  /// @return data Arbitrary data
  function burn(TimeswapV2LiquidityTokenBurnParam calldata param) external returns (bytes memory data);

  /// @dev collects fees as per the fees desired
  /// @param param The TimeswapV2LiquidityTokenBurnParam
  /// @return long0Fees Fees for long0
  /// @return long1Fees Fees for long1
  /// @return shortFees Fees for short
  /// @return shortReturned Short Returned
  function collect(
    TimeswapV2LiquidityTokenCollectParam calldata param
  )
    external
    returns (uint256 long0Fees, uint256 long1Fees, uint256 shortFees, uint256 shortReturned, bytes memory data);
}

