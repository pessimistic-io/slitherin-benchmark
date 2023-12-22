// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IFlashLoanRecipient.sol";
import "./PloopyConstants.sol";

contract Ploopy is IPloopy, PloopyConstants, Ownable, IFlashLoanRecipient, ReentrancyGuard {
  constructor() {
    // approve rewardRouter to spend USDC for minting GLP
    USDC.approve(address(REWARD_ROUTER_V2), type(uint256).max);
    USDC.approve(address(GLP), type(uint256).max);
    USDC.approve(address(VAULT), type(uint256).max);
    USDC.approve(address(GLP_MANAGER), type(uint256).max);
    // approve GlpDepositor to spend GLP for minting plvGLP
    sGLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
    GLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
    sGLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
    GLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
    // approve lPLVGLP to spend plvGLP to mint lPLVGLP
    PLVGLP.approve(address(lPLVGLP), type(uint256).max);
  }

  // Declare events
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Loan(uint256 value);
  event BalanceOf(uint256 balanceAmount, uint256 loanAmount);
  event Allowance(uint256 allowance, uint256 loanAmount);
  event UserDataEvent(address indexed from, uint256 plvGlpAmount, string indexed borrowedToken, uint256 borrowedAmount);
  event PLVGLPBalanceChange(uint256 priorBalanceAmount, uint256 newBalanceAmount);
  event lPLVGLPBalanceChange(uint256 newBalanceAmount);

  function loop(uint256 _plvGlpAmount, uint16 _leverage) external {
    require(tx.origin == msg.sender, "Not an EOA");
    require(_plvGlpAmount > 0, "Amount must be greater than 0");
    require(_leverage >= DIVISOR && _leverage <= MAX_LEVERAGE, "Invalid leverage");

    // Transfer plvGLP to this contract so we can mint in 1 go.
    PLVGLP.transferFrom(msg.sender, address(this), _plvGlpAmount);

    uint256 loanAmount = getNotionalLoanAmountIn1e18(
      _plvGlpAmount * PRICE_ORACLE.getPlvGLPPrice(),
      _leverage
    ) / 1e12; //usdc is 6 decimals
    emit Loan(loanAmount);

    if (USDC.balanceOf(address(BALANCER_VAULT)) < loanAmount) revert FAILED('usdc<loan');
    emit BalanceOf(USDC.balanceOf(address(BALANCER_VAULT)), loanAmount);

    // check approval to spend USDC (for paying back flashloan).
    // Possibly can omit to save gas as tx will fail with exceed allowance anyway.
    if (USDC.allowance(msg.sender, address(this)) < loanAmount) revert INVALID_APPROVAL();
    emit Allowance(USDC.allowance(msg.sender, address(this)), loanAmount);

    IERC20[] memory tokens = new IERC20[](1);
    tokens[0] = USDC;

    uint256[] memory loanAmounts = new uint256[](1);
    loanAmounts[0] = loanAmount;

    UserData memory userData = UserData({
      user: msg.sender,
      plvGlpAmount: _plvGlpAmount,
      borrowedToken: USDC,
      borrowedAmount: loanAmount
    });
    emit UserDataEvent(msg.sender, _plvGlpAmount, 'USDC', loanAmount);

    BALANCER_VAULT.flashLoan(IFlashLoanRecipient(this), tokens, loanAmounts, abi.encode(userData));
  }

  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external override nonReentrant {
    if (msg.sender != address(BALANCER_VAULT)) revert UNAUTHORIZED('!vault');

    // additional checks?

    UserData memory data = abi.decode(userData, (UserData));
    if (data.borrowedAmount != amounts[0] || data.borrowedToken != tokens[0]) revert FAILED('!chk');

    // sanity check: flashloan has no fees
    if (feeAmounts[0] > 0) revert FAILED('fee>0');

    // mint GLP. Approval needed.
    uint256 glpAmount = REWARD_ROUTER_V2.mintAndStakeGlp(
      address(data.borrowedToken),
      data.borrowedAmount,
      0,
      0
    );
    if (glpAmount == 0) revert FAILED('glp=0');

    // TODO whitelist this contract for plvGLP mint
    // mint plvGLP. Approval needed.
    // uint256 _oldPlvglpBal = PLVGLP.balanceOf(address(this));
    // GLP_DEPOSITOR.deposit(glpAmount);

    // // check new balances and confirm we properly minted
    // uint256 _newPlvglpBal = PLVGLP.balanceOf(address(this));
    // require(_newPlvglpBal > _oldPlvglpBal, "GLP deposit failed");
    // emit PLVGLPBalanceChange(_oldPlvglpBal, _newPlvglpBal);

    // mint lPLVGLP by depositing plvGLP. Approval needed.
    unchecked {
      // mint lplvGLP
      lPLVGLP.mint(PLVGLP.balanceOf(address(this)));

      // pull our most up to date lplvGLP balance
      uint256 newlPlvglpBal = lPLVGLP.balanceOf(address(this));
      emit lPLVGLPBalanceChange(newlPlvglpBal);

      // transfer lPLVGLP minted to user
      lPLVGLP.transfer(data.user, newlPlvglpBal);
      emit Transfer(msg.sender, data.user, newlPlvglpBal);
    }

    // call borrowBehalf to borrow USDC on behalf of user
    // lUSDC.borrowBehalf(data.borrowedAmount, data.user);

    // repay loan: msg.sender = vault
    USDC.transferFrom(data.user, msg.sender, data.borrowedAmount);
  }

  function getNotionalLoanAmountIn1e18(
    uint256 _notionalGlpAmountIn1e18,
    uint16 _leverage
  ) private pure returns (uint256) {
    unchecked {
      return ((_leverage - DIVISOR) * _notionalGlpAmountIn1e18) / DIVISOR;
    }
  }
}

