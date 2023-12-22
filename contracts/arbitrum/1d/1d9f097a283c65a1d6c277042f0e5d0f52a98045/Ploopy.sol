// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IFlashLoanRecipient.sol";
import "./PloopyConstants.sol";

contract Ploopy is IPloopy, PloopyConstants, Ownable, IFlashLoanRecipient, ReentrancyGuard {
  using SafeERC20 for IERC20;
  // add mapping of token addresses to their decimal places
  mapping(IERC20 => uint8) public decimals;
  // add mapping to store the allowed tokens. Mapping provides faster access than array
  mapping(IERC20 => bool) public allowedTokens;
  // add mapping to store lToken contracts
  mapping(IERC20 => ICERC20) private lTokenMapping;

  constructor() {
    // initialize decimals for each token
    decimals[USDC] = 6;
    decimals[USDT] = 6;
    decimals[WBTC] = 8;
    decimals[DAI] = 18;
    decimals[FRAX] = 18;
    decimals[ETH] = 18;
    decimals[ARB] = 18;
    decimals[PLVGLP] = 18;

    // set the allowed tokens in the constructor
    // we can add/remove these with owner functions later
    allowedTokens[USDC] = true;
    allowedTokens[USDT] = true;
    allowedTokens[WBTC] = true;
    allowedTokens[DAI] = true;
    allowedTokens[FRAX] = true;
    allowedTokens[ETH] = true;
    allowedTokens[ARB] = true;
    allowedTokens[PLVGLP] = true;

    // map tokens to lTokens
    lTokenMapping[USDC] = lUSDC;
    lTokenMapping[USDT] = lUSDT;
    lTokenMapping[WBTC] = lWBTC;
    lTokenMapping[DAI] = lDAI;
    lTokenMapping[FRAX] = lFRAX;
    lTokenMapping[ETH] = lETH;
    lTokenMapping[ARB] = lARB;
    lTokenMapping[PLVGLP] = lPLVGLP;

    // approve glp contracts to spend USDC for minting GLP
    USDC.approve(address(REWARD_ROUTER_V2), type(uint256).max);
    USDC.approve(address(GLP), type(uint256).max);
    USDC.approve(address(GLP_MANAGER), type(uint256).max);
    // approve GlpDepositor to spend GLP for minting plvGLP
    sGLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
    GLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
    sGLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
    GLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
    // approve balancer vault
    USDC.approve(address(VAULT), type(uint256).max);
    USDT.approve(address(VAULT), type(uint256).max);
    WBTC.approve(address(VAULT), type(uint256).max);
    DAI.approve(address(VAULT), type(uint256).max);
    FRAX.approve(address(VAULT), type(uint256).max);
    ETH.approve(address(VAULT), type(uint256).max);
    WETH.approve(address(VAULT), type(uint256).max);
    ARB.approve(address(VAULT), type(uint256).max);
    // approve lTokens to be minted using underlying
    PLVGLP.approve(address(lPLVGLP), type(uint256).max);
    USDC.approve(address(lUSDC), type(uint256).max);
    USDT.approve(address(lUSDT), type(uint256).max);
    WBTC.approve(address(lWBTC), type(uint256).max);
    DAI.approve(address(lDAI), type(uint256).max);
    FRAX.approve(address(lFRAX), type(uint256).max);
    ETH.approve(address(lETH), type(uint256).max);
    ARB.approve(address(lARB), type(uint256).max);
    // approve Ploopy to withdraw and deposit to WETH contract
    WETH.approve(address(this), type(uint256).max);
  }

  // declare events
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Loan(uint256 value);
  event BalanceOf(uint256 balanceAmount, uint256 loanAmount);
  event Allowance(uint256 allowance, uint256 loanAmount);
  event UserDataEvent(address indexed from, uint256 tokenAmount, address borrowedToken, uint256 borrowedAmount, address tokenToLoop);
  event plvGLPBalance(uint256 balanceAmount);
  event lTokenBalance(uint256 balanceAmount);
  event Received(address, uint);

  function addToken(IERC20 token) external onlyOwner {
      require(!allowedTokens[token], "token already allowed");
      allowedTokens[token] = true;
  }

  function removeToken(IERC20 token) external onlyOwner {
      require(allowedTokens[token], "token not allowed");
      allowedTokens[token] = false;
  }

  // allows users to loop to a desired leverage, within our pre-set ranges
  function loop(IERC20 _token, uint256 _amount, uint16 _leverage, uint16 _useWalletBalance) external {
    require(allowedTokens[_token], "token not allowed to loop");
    require(tx.origin == msg.sender, "not an EOA");
    require(_amount > 0, "amount must be greater than 0");
    require(_leverage >= DIVISOR && _leverage <= MAX_LEVERAGE, "invalid leverage, range must be between DIVISOR and MAX_LEVERAGE values");

    // if the user wants us to mint using their existing wallet balance (indiciated with 1), then do so.
    // otherwise, read their existing balance and flash loan to increase their position
    if (_useWalletBalance == 1) {
      // transfer tokens to this contract so we can mint in 1 go.
      _token.safeTransferFrom(msg.sender, address(this), _amount);
      emit Transfer(msg.sender, address(this), _amount);
    }
    
    uint256 loanAmount;
    IERC20 _tokenToBorrow;

    if (_token == PLVGLP) {
      uint256 _tokenPriceInEth;
      uint256 _usdcPriceInEth;
      uint256 _computedAmount;

      // plvGLP borrows USDC to loop
      _tokenToBorrow = USDC;
      _tokenPriceInEth = PRICE_ORACLE.getUnderlyingPrice(address(lTokenMapping[_token]));
      _usdcPriceInEth = (PRICE_ORACLE.getUnderlyingPrice(address(lUSDC)) / 1e12);
      _computedAmount = (_amount * (_tokenPriceInEth / _usdcPriceInEth));

      loanAmount = getNotionalLoanAmountIn1e18(
        _computedAmount,
        _leverage
      );
    } else {
      // the rest of the contracts just borrow whatever token is supplied
      _tokenToBorrow = _token;
      loanAmount = getNotionalLoanAmountIn1e18(
        _amount, // we can just send over the exact amount, as we are either looping stables or eth
        _leverage
      );
    }

    if (_tokenToBorrow.balanceOf(address(BALANCER_VAULT)) < loanAmount) revert FAILED('balancer vault token balance < loan');
    emit Loan(loanAmount);
    emit BalanceOf(_tokenToBorrow.balanceOf(address(BALANCER_VAULT)), loanAmount);

    // check approval to spend USDC (for paying back flashloan).
    // possibly can omit to save gas as tx will fail with exceed allowance anyway.
    if (_tokenToBorrow.allowance(msg.sender, address(this)) < loanAmount) revert INVALID_APPROVAL();
    emit Allowance(_tokenToBorrow.allowance(msg.sender, address(this)), loanAmount);

    IERC20[] memory tokens = new IERC20[](1);
    tokens[0] = _tokenToBorrow;

    uint256[] memory loanAmounts = new uint256[](1);
    loanAmounts[0] = loanAmount;

    UserData memory userData = UserData({
      user: msg.sender,
      tokenAmount: _amount,
      borrowedToken: _tokenToBorrow,
      borrowedAmount: loanAmount,
      tokenToLoop: _token
    });
    emit UserDataEvent(msg.sender, _amount, address(_tokenToBorrow), loanAmount, address(_token));

    BALANCER_VAULT.flashLoan(IFlashLoanRecipient(this), tokens, loanAmounts, abi.encode(userData));
  }
  

  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external override nonReentrant {
    if (msg.sender != address(BALANCER_VAULT)) revert UNAUTHORIZED('balancer vault is not the sender');

    // additional checks?

    UserData memory data = abi.decode(userData, (UserData));
    if (data.borrowedAmount != amounts[0] || data.borrowedToken != tokens[0]) revert FAILED('borrowed amounts and/or borrowed tokens do not match initially set values');

    // sanity check: flashloan has no fees
    if (feeAmounts[0] > 0) revert FAILED('balancer fee > 0');

    // account for some plvGLP specific logic
    if (data.tokenToLoop == PLVGLP) {
      // mint GLP. approval needed.
      uint256 glpAmount = REWARD_ROUTER_V2.mintAndStakeGlp(
        address(data.borrowedToken),
        data.borrowedAmount,
        0,
        0
      );
      if (glpAmount == 0) revert FAILED('glp=0');

      // TODO whitelist this contract for plvGLP mint
      // mint plvGLP. approval needed.
      uint256 _oldPlvglpBal = PLVGLP.balanceOf(address(this));
      GLP_DEPOSITOR.deposit(glpAmount);

      // check new balances and confirm we properly minted
      uint256 _newPlvglpBal = PLVGLP.balanceOf(address(this));
      emit plvGLPBalance(_newPlvglpBal);
      require(_newPlvglpBal > _oldPlvglpBal, "glp deposit failed, new balance < old balance");
    }

    // mint our respective token by depositing it into Lodestar's respective lToken contract (approval needed)
    unchecked {
      // lets get eth instead of weth so we can properly mint
      if (data.tokenToLoop == ETH) {
        WETH.withdraw(data.borrowedAmount);
        // mint our eth balance
        lTokenMapping[data.tokenToLoop].mint(address(this).balance);
      } else {
        lTokenMapping[data.tokenToLoop].mint(data.tokenToLoop.balanceOf(address(this)));
      }

      lTokenMapping[data.tokenToLoop].transfer(data.user, lTokenMapping[data.tokenToLoop].balanceOf(address(this)));
      uint256 _finalBal = lTokenMapping[data.tokenToLoop].balanceOf(address(this));

      emit lTokenBalance(_finalBal);
      require(_finalBal == 0, "lToken balance not 0 at the end of loop");
    }

    // call borrowBehalf to borrow tokens on behalf of user
    lTokenMapping[data.tokenToLoop].borrowBehalf(data.borrowedAmount, data.user);

    if (data.tokenToLoop == ETH) {
      WETH.deposit{ value: data.borrowedAmount }();
      // ensure we pay the loan back with weth
      WETH.transferFrom(address(this), msg.sender, data.borrowedAmount);
    } else {
      // repay loan, where msg.sender = vault
      data.tokenToLoop.safeTransferFrom(data.user, msg.sender, data.borrowedAmount);
    }
  }

  function getNotionalLoanAmountIn1e18(
    uint256 _notionalTokenAmountIn1e18,
    uint16 _leverage
  ) private pure returns (uint256) {
    unchecked {
      return ((_leverage - DIVISOR) * _notionalTokenAmountIn1e18) / DIVISOR;
    }
  }

  // we need this in order to receive ether back to the contract
  receive() external payable {
    emit Received(msg.sender, msg.value);
  }
}

