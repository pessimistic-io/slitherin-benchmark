// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

error Strategy_InvalidOwner(address owner);
error Strategy_InsufficientAmount();
error Strategy_TokensAndAmountsLengthAreDifferent();

contract Strategy is ReentrancyGuard {
  using SafeERC20 for IERC20;

  address public immutable owner;
  address public immutable USDT;

  address public immutable paraswapAddress;
  address public immutable tokenTransferContract;

  uint16 public immutable tradePercentage;

  uint256 public totalActiveInvestment;
  mapping(address => uint256) public balance;

  event Deposit(address indexed user, address token, uint256 amount);
  event Swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
  event WithdrawSingleToken(address indexed user, address token, uint256 amount);
  event Withdraw(address indexed user, address[] tokensIn, uint256[] amountsIn, address tokenOut, uint256 amountOut);

  modifier onlyOwner() {
    if (msg.sender != owner && msg.sender != address(this)) revert Strategy_InvalidOwner(msg.sender);
    _;
  }

  constructor(address owner_, address usdt_, address paraswapAddress_, address tokenTransferContract_, uint16 tradePercentage_) {
    owner = owner_;
    USDT = usdt_;
    paraswapAddress = paraswapAddress_;
    tokenTransferContract = tokenTransferContract_;
    tradePercentage = tradePercentage_;
  }

  function _approve(address spender_, address token_, uint256 amount_) private {
    IERC20(token_).approve(spender_, 0);
    IERC20(token_).approve(spender_, amount_);
  }

  function deposit(address token_, uint256 amount_) public {
    IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);

    if (token_ == USDT) totalActiveInvestment += amount_;
    balance[token_] += amount_;

    emit Deposit(msg.sender, token_, amount_);
  }

  function swap(address tokenIn_, address tokenOut_, uint256 amount_, bytes calldata data_) public nonReentrant onlyOwner returns (uint256 amountOut) {
    balance[tokenIn_] -= amount_;
    uint256 tokenOutBalance = IERC20(tokenOut_).balanceOf(address(this));

    _approve(tokenTransferContract, tokenIn_, amount_);
    (bool success, ) = paraswapAddress.call(data_);
    if (!success) revert();

    amountOut = IERC20(tokenOut_).balanceOf(address(this)) - tokenOutBalance;
    balance[tokenOut_] += amountOut;

    emit Swap(tokenIn_, amount_, tokenOut_, amountOut);
  }

  function withdrawSingleToken(address user_, address token_, uint256 amount_) public nonReentrant onlyOwner {
    if (amount_ > balance[token_]) revert Strategy_InsufficientAmount();

    IERC20(token_).safeTransfer(user_, amount_);

    if (token_ == USDT) totalActiveInvestment -= amount_;
    balance[token_] -= amount_;

    emit WithdrawSingleToken(user_, token_, amount_);
  }

  function withdraw(address user_, address[] memory tokensIn_, uint256[] memory amountsIn_, address tokenOut_, bytes[] calldata datas_) public onlyOwner {
    if (tokensIn_.length != amountsIn_.length) revert Strategy_TokensAndAmountsLengthAreDifferent();

    uint256 totalAmountOut;
    for (uint16 i; i < tokensIn_.length; ++i) {
      if (amountsIn_[i] > balance[tokensIn_[i]]) revert Strategy_InsufficientAmount();

      if (tokensIn_[i] != USDT) {
        totalAmountOut += swap(tokensIn_[i], tokenOut_, amountsIn_[i], datas_[i]);
      } else {
        totalActiveInvestment -= amountsIn_[i];
        totalAmountOut += amountsIn_[i];
      }
    }
    IERC20(tokenOut_).safeTransfer(user_, totalAmountOut);

    emit Withdraw(user_, tokensIn_, amountsIn_, tokenOut_, totalAmountOut);
  }
}

