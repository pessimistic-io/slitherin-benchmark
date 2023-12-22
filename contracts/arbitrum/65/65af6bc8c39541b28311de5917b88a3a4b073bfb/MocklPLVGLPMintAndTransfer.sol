// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./PloopyConstants.sol";

contract MocklPLVGLPMintAndTransfer is IPloopy, PloopyConstants, Ownable, ReentrancyGuard {
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

    // mint lPLVGLP by depositing plvGLP. Approval needed.
    unchecked {
      // mint lplvGLP
      lPLVGLP.mint(PLVGLP.balanceOf(address(this)));

      // pull our most up to date lplvGLP balance
      uint256 newlPlvglpBal = lPLVGLP.balanceOf(address(this));
      emit lPLVGLPBalanceChange(newlPlvglpBal);

      // transfer lPLVGLP minted to user
      lPLVGLP.transfer(msg.sender, newlPlvglpBal);
      emit Transfer(address(this), msg.sender, newlPlvglpBal);
    }
  }
}

