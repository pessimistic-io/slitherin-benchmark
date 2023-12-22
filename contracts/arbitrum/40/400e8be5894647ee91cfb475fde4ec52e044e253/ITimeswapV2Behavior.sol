// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {IERC1155} from "./IERC1155.sol";
import {IERC20} from "./IERC20.sol";

import {FeesPosition} from "./FeesPosition.sol";

import {IMulticall} from "./IMulticall.sol";

interface ITimeswapV2Behavior is IERC1155, IERC20, IMulticall {
  struct Pool {
    uint256 shortId;
    uint256 long0Id;
    uint256 long1Id;
    uint256 liquidityId;
    mapping(address => FeesPosition) feesPositions;
  }

  struct PositionParam {
    address token;
    uint256 strike;
    uint256 maturity;
    PositionType positionType;
  }

  enum PositionType {
    Short,
    Long0,
    Long1,
    Liquidity
  }

  function timeswapV2Token() external view returns (address);

  function timeswapV2LendGivenPrincipal() external view returns (address);

  function timeswapV2CloseLendGivenPosition() external view returns (address);

  function timeswapV2Withdraw() external view returns (address);

  function timeswapV2BorrowGivenPrincipal() external view returns (address);

  function timeswapV2CloseBorrowGivenPosition() external view returns (address);

  function positionId(
    address token,
    uint256 strike,
    uint256 maturity,
    PositionType positionType
  ) external pure returns (uint256 id);

  function positionParams(uint256 id) external view returns (PositionParam memory positionParam);

  function initialize() external;

  struct LendGivenPrincipalParam {
    address token;
    uint256 strike;
    uint256 maturity;
    address to;
    bool isToken0;
    uint256 tokenAmount;
    uint256 minPositionAmount;
    uint256 deadline;
    bytes erc1155Data;
  }

  function lendGivenPrincipal(LendGivenPrincipalParam calldata param) external returns (uint256 positionAmount);

  struct CloseLendGivenPositionParam {
    address token;
    uint256 strike;
    uint256 maturity;
    address token0To;
    address token1To;
    bool preferToken0;
    uint256 positionAmount;
    uint256 minToken0Amount;
    uint256 minToken1Amount;
    uint256 deadline;
  }

  function closeLendGivenPosition(
    CloseLendGivenPositionParam calldata param
  ) external returns (uint256 token0Amount, uint256 token1Amount);

  struct WithdrawParam {
    address token;
    uint256 strike;
    uint256 maturity;
    address token0To;
    address token1To;
    uint256 positionAmount;
    uint256 minToken0Amount;
    uint256 minToken1Amount;
    uint256 deadline;
  }

  function withdraw(WithdrawParam calldata param) external returns (uint256 token0Amount, uint256 token1Amount);

  struct BorrowGivenPrincipalParam {
    address token;
    uint256 strike;
    uint256 maturity;
    address tokenTo;
    address longTo;
    bool isToken0;
    bool isLong0;
    uint256 tokenAmount;
    uint256 maxPositionAmount;
    uint256 deadline;
    bytes erc1155Data;
  }

  function borrowGivenPrincipal(BorrowGivenPrincipalParam calldata param) external returns (uint256 positionAmount);

  struct CloseBorrowGivenPositionParam {
    address token;
    uint256 strike;
    uint256 maturity;
    address to;
    bool isToken0;
    bool isLong0;
    uint256 positionAmount;
    uint256 maxTokenAmount;
    uint256 deadline;
  }

  function closeBorrowGivenPosition(
    CloseBorrowGivenPositionParam calldata param
  ) external returns (uint256 tokenAmount);
}

