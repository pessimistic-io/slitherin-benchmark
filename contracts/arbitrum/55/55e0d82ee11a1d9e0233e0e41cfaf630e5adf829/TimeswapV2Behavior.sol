// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.8;

import {ERC1155} from "./ERC1155.sol";
import {IERC1155} from "./IERC1155.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

import {ITimeswapV2Token} from "./ITimeswapV2Token.sol";
import {FeesPositionLibrary, FeesPosition} from "./FeesPosition.sol";
import {TimeswapV2LiquidityTokenPosition} from "./structs_Position.sol";

import {ITimeswapV2PeripheryNoDexLendGivenPrincipal} from "./ITimeswapV2PeripheryNoDexLendGivenPrincipal.sol";
import {ITimeswapV2PeripheryNoDexCloseLendGivenPosition} from "./ITimeswapV2PeripheryNoDexCloseLendGivenPosition.sol";
import {ITimeswapV2PeripheryNoDexWithdraw} from "./ITimeswapV2PeripheryNoDexWithdraw.sol";
import {ITimeswapV2PeripheryNoDexBorrowGivenPrincipal} from "./ITimeswapV2PeripheryNoDexBorrowGivenPrincipal.sol";
import {ITimeswapV2PeripheryNoDexCloseBorrowGivenPosition} from "./ITimeswapV2PeripheryNoDexCloseBorrowGivenPosition.sol";
import {TimeswapV2PeripheryNoDexLendGivenPrincipalParam, TimeswapV2PeripheryNoDexCloseLendGivenPositionParam, TimeswapV2PeripheryNoDexWithdrawParam, TimeswapV2PeripheryNoDexBorrowGivenPrincipalParam, TimeswapV2PeripheryNoDexCloseBorrowGivenPositionParam} from "./structs_Param.sol";

import {ITimeswapV2Behavior} from "./ITimeswapV2Behavior.sol";

abstract contract TimeswapV2Behavior is ITimeswapV2Behavior, ERC1155, ERC20, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using FeesPositionLibrary for FeesPosition;

  address public immutable override timeswapV2Token;

  address public immutable override timeswapV2LendGivenPrincipal;
  address public immutable override timeswapV2CloseLendGivenPosition;
  address public immutable override timeswapV2Withdraw;
  address public immutable override timeswapV2BorrowGivenPrincipal;
  address public immutable override timeswapV2CloseBorrowGivenPosition;

  mapping(uint256 => PositionParam) private _positionParams;

  /// todo update the constructor
  constructor(
    address _timeswapV2Token,
    address _timeswapV2LendGivenPrincipal,
    address _timeswapV2CloseLendGivenPosition,
    address _timeswapV2Withdraw,
    address _timeswapV2BorrowGivenPrincipal,
    address _timeswapV2CloseBorrowGivenPosition
  ) {
    timeswapV2Token = _timeswapV2Token;
    timeswapV2LendGivenPrincipal = _timeswapV2LendGivenPrincipal;
    timeswapV2CloseLendGivenPosition = _timeswapV2CloseLendGivenPosition;
    timeswapV2Withdraw = _timeswapV2Withdraw;
    timeswapV2BorrowGivenPrincipal = _timeswapV2BorrowGivenPrincipal;
    timeswapV2CloseBorrowGivenPosition = _timeswapV2CloseBorrowGivenPosition;
  }

  function initialize() external override {
    IERC20(address(this)).approve(timeswapV2LendGivenPrincipal, type(uint256).max);
    IERC20(address(this)).approve(timeswapV2BorrowGivenPrincipal, type(uint256).max);
    IERC20(address(this)).approve(timeswapV2CloseBorrowGivenPosition, type(uint256).max);
    IERC1155(timeswapV2Token).setApprovalForAll(timeswapV2CloseLendGivenPosition, true);
    IERC1155(timeswapV2Token).setApprovalForAll(timeswapV2CloseBorrowGivenPosition, true);
    IERC1155(timeswapV2Token).setApprovalForAll(timeswapV2Withdraw, true);
  }

  function positionId(
    address token,
    uint256 strike,
    uint256 maturity,
    PositionType positionType
  ) public pure override returns (uint256 id) {
    id = uint256(keccak256(abi.encodePacked(token, strike, maturity, positionType)));
  }

  function positionParams(uint256 id) public view override returns (PositionParam memory positionParam) {
    positionParam = _positionParams[id];
  }

  function onERC1155Received(address, address, uint256, uint256, bytes memory) external view returns (bytes4) {
    if (msg.sender == timeswapV2Token) return this.onERC1155Received.selector;
    revert();
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes memory
  ) external view returns (bytes4) {
    if (msg.sender == timeswapV2Token) return this.onERC1155BatchReceived.selector;
    revert();
  }

  function lendGivenPrincipal(
    LendGivenPrincipalParam calldata param
  ) external override nonReentrant returns (uint256 positionAmount) {
    if (_check(param.token, param.isToken0)) {
      _mint(address(this), param.tokenAmount);
    } else {
      IERC20(param.token).safeTransferFrom(msg.sender, address(this), param.tokenAmount);
      _approveIfNeeded(param.token, timeswapV2LendGivenPrincipal, param.tokenAmount);
    }

    TimeswapV2PeripheryNoDexLendGivenPrincipalParam memory callParam;
    callParam.token0 = address(this) < param.token ? address(this) : param.token;
    callParam.token1 = address(this) > param.token ? address(this) : param.token;
    callParam.strike = param.strike;
    callParam.maturity = param.maturity;
    callParam.to = address(this);
    callParam.isToken0 = param.isToken0;
    callParam.tokenAmount = param.tokenAmount;
    callParam.minReturnAmount = param.minPositionAmount;
    callParam.deadline = param.deadline;
    positionAmount = ITimeswapV2PeripheryNoDexLendGivenPrincipal(timeswapV2LendGivenPrincipal).lendGivenPrincipal(
      callParam
    );

    uint256 id = positionId(param.token, param.strike, param.maturity, PositionType.Short);
    PositionParam storage positionParam = _positionParams[id];
    if (positionParam.token == address(0)) {
      positionParam.token = param.token;
      positionParam.strike = param.strike;
      positionParam.maturity = param.maturity;
      positionParam.positionType = PositionType.Short;
    }

    if (_check(param.token, param.isToken0)) _mintRequirement(param.tokenAmount);

    _mint(param.to, id, positionAmount, param.erc1155Data);
  }

  function closeLendGivenPosition(
    CloseLendGivenPositionParam calldata param
  ) external override nonReentrant returns (uint256 token0Amount, uint256 token1Amount) {
    TimeswapV2PeripheryNoDexCloseLendGivenPositionParam memory callParam;
    callParam.token0 = address(this) < param.token ? address(this) : param.token;
    callParam.token1 = address(this) > param.token ? address(this) : param.token;
    callParam.strike = param.strike;
    callParam.maturity = param.maturity;
    callParam.to = address(this);
    callParam.isToken0 = param.preferToken0;
    callParam.positionAmount = param.positionAmount;
    callParam.minToken0Amount = param.minToken0Amount;
    callParam.minToken1Amount = param.minToken1Amount;
    callParam.deadline = param.deadline;
    (token0Amount, token1Amount) = ITimeswapV2PeripheryNoDexCloseLendGivenPosition(timeswapV2CloseLendGivenPosition)
      .closeLendGivenPosition(callParam);

    uint256 id = positionId(param.token, param.strike, param.maturity, PositionType.Short);
    // uint256 id = uint256(keccak256(abi.encodePacked(param.token, param.strike, param.maturity, PositionType.Short)));

    _burn(msg.sender, id, param.positionAmount);

    if (token0Amount != 0) {
      if (address(this) < param.token) _burnRequirement(param.token0To, token0Amount);
      else IERC20(param.token).safeTransfer(param.token0To, token0Amount);
    }

    if (token1Amount != 0) {
      if (address(this) > param.token) _burnRequirement(param.token1To, token1Amount);
      else IERC20(param.token).safeTransfer(param.token1To, token1Amount);
    }
  }

  function withdraw(
    WithdrawParam calldata param
  ) external override nonReentrant returns (uint256 token0Amount, uint256 token1Amount) {
    TimeswapV2PeripheryNoDexWithdrawParam memory callParam;
    callParam.token0 = address(this) < param.token ? address(this) : param.token;
    callParam.token1 = address(this) > param.token ? address(this) : param.token;
    callParam.strike = param.strike;
    callParam.maturity = param.maturity;
    callParam.to = address(this);
    callParam.positionAmount = param.positionAmount;
    callParam.minToken0Amount = param.minToken0Amount;
    callParam.minToken1Amount = param.minToken1Amount;
    callParam.deadline = param.deadline;
    (token0Amount, token1Amount) = ITimeswapV2PeripheryNoDexWithdraw(timeswapV2Withdraw).withdraw(callParam);

    uint256 id = positionId(param.token, param.strike, param.maturity, PositionType.Short);
    // uint256 id = uint256(keccak256(abi.encodePacked(param.token, param.strike, param.maturity, PositionType.Short)));

    _burn(msg.sender, id, param.positionAmount);

    if (token0Amount != 0) {
      if (address(this) < param.token) _burnRequirement(param.to, token0Amount);
      else IERC20(param.token).safeTransfer(param.to, token0Amount);
    }

    if (token1Amount != 0) {
      if (address(this) > param.token) _burnRequirement(param.to, token1Amount);
      else IERC20(param.token).safeTransfer(param.to, token1Amount);
    }
  }

  function borrowGivenPrincipal(
    BorrowGivenPrincipalParam calldata param
  ) external override nonReentrant returns (uint256 positionAmount) {
    if (param.isLong0 == param.isToken0) {
      if (_check(param.token, param.isLong0)) {
        _mint(address(this), param.maxPositionAmount - param.tokenAmount);
      } else {
        IERC20(param.token).safeTransferFrom(msg.sender, address(this), param.maxPositionAmount - param.tokenAmount);
        _approveIfNeeded(param.token, timeswapV2BorrowGivenPrincipal, param.maxPositionAmount - param.tokenAmount);
      }
    } else {
      if (_check(param.token, param.isLong0)) {
        _mint(address(this), param.maxPositionAmount);
      } else {
        IERC20(param.token).safeTransferFrom(msg.sender, address(this), param.maxPositionAmount);
        _approveIfNeeded(param.token, timeswapV2BorrowGivenPrincipal, param.maxPositionAmount);
      }
    }

    TimeswapV2PeripheryNoDexBorrowGivenPrincipalParam memory callParam;
    callParam.token0 = address(this) < param.token ? address(this) : param.token;
    callParam.token1 = address(this) > param.token ? address(this) : param.token;
    callParam.strike = param.strike;
    callParam.maturity = param.maturity;
    callParam.tokenTo = address(this);
    callParam.longTo = address(this);
    callParam.isToken0 = param.isToken0;
    callParam.isLong0 = param.isLong0;
    callParam.tokenAmount = param.tokenAmount;
    callParam.maxPositionAmount = param.maxPositionAmount;
    callParam.deadline = param.deadline;
    positionAmount = ITimeswapV2PeripheryNoDexBorrowGivenPrincipal(timeswapV2BorrowGivenPrincipal).borrowGivenPrincipal(
      callParam
    );

    if (_check(param.token, param.isLong0)) _burn(address(this), param.maxPositionAmount - positionAmount);
    else IERC20(param.token).safeTransfer(msg.sender, param.maxPositionAmount - positionAmount);

    if (param.isLong0 == param.isToken0) {
      if (_check(param.token, param.isLong0)) _mintRequirement(positionAmount - param.tokenAmount);
    } else {
      if (_check(param.token, param.isLong0)) _mintRequirement(positionAmount);

      if (_check(param.token, param.isToken0)) _burnRequirement(param.tokenTo, param.tokenAmount);
      else IERC20(param.token).safeTransfer(param.tokenTo, param.tokenAmount);
    }

    uint256 id = positionId(
      param.token,
      param.strike,
      param.maturity,
      param.isLong0 ? PositionType.Long0 : PositionType.Long1
    );

    PositionParam storage positionParam = _positionParams[id];
    if (positionParam.token == address(0)) {
      positionParam.token = param.token;
      positionParam.strike = param.strike;
      positionParam.maturity = param.maturity;
      positionParam.positionType = param.isLong0 ? PositionType.Long0 : PositionType.Long1;
    }

    _mint(param.longTo, id, positionAmount, param.erc1155Data);
  }

  function closeBorrowGivenPosition(
    CloseBorrowGivenPositionParam calldata param
  ) external override nonReentrant returns (uint256 tokenAmount) {
    if (param.isLong0 != param.isToken0) {
      if (_check(param.token, param.isToken0)) {
        _mint(address(this), param.maxTokenAmount);
      } else {
        IERC20(param.token).safeTransferFrom(msg.sender, address(this), param.maxTokenAmount);
        _approveIfNeeded(param.token, timeswapV2CloseBorrowGivenPosition, param.maxTokenAmount);
      }
    }

    TimeswapV2PeripheryNoDexCloseBorrowGivenPositionParam memory callParam;
    callParam.token0 = address(this) < param.token ? address(this) : param.token;
    callParam.token1 = address(this) > param.token ? address(this) : param.token;
    callParam.strike = param.strike;
    callParam.maturity = param.maturity;
    callParam.to = address(this);
    callParam.isToken0 = param.isToken0;
    callParam.isLong0 = param.isLong0;
    callParam.positionAmount = param.positionAmount;
    callParam.maxTokenAmount = param.maxTokenAmount;
    callParam.deadline = param.deadline;
    tokenAmount = ITimeswapV2PeripheryNoDexCloseBorrowGivenPosition(timeswapV2CloseBorrowGivenPosition)
      .closeBorrowGivenPosition(callParam);

    uint256 id = positionId(
      param.token,
      param.strike,
      param.maturity,
      param.isLong0 ? PositionType.Long0 : PositionType.Long1
    );

    _burn(msg.sender, id, param.positionAmount);

    if (param.isLong0 == param.isToken0) {
      if (_check(param.token, param.isLong0)) _burnRequirement(param.to, param.positionAmount - tokenAmount);
      else IERC20(param.token).safeTransfer(param.to, param.positionAmount - tokenAmount);
    } else {
      if (_check(param.token, param.isToken0)) {
        _burn(address(this), param.maxTokenAmount - tokenAmount);
        _mintRequirement(tokenAmount);
        IERC20(param.token).safeTransfer(param.to, param.positionAmount);
      } else {
        IERC20(param.token).safeTransfer(msg.sender, param.maxTokenAmount - tokenAmount);
        _burnRequirement(param.to, param.positionAmount);
        _burn(address(this), param.positionAmount); // required?
      }
    }
    harvest(param.token, param.strike, param.maturity, param.to);
  }

  function harvest(address token, uint256 strike, uint256 maturity, address to) public virtual returns (uint256 amount);

  function _mintRequirement(uint256 tokenAmount) internal virtual;

  function _burnRequirement(address to, uint256 tokenAmount) internal virtual;

  function _check(address otherToken, bool isZero) private view returns (bool) {
    return (isZero && (address(this) < otherToken)) || (!isZero && (address(this) > otherToken));
  }

  function _approveIfNeeded(address otherToken, address spender, uint256 amount) private {
    uint256 allowance = IERC20(otherToken).allowance(address(this), spender);
    if (allowance < amount) IERC20(otherToken).approve(spender, type(uint256).max);
  }
}

