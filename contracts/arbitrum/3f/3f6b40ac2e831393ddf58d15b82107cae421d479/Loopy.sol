// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable2Step.sol";
import "./SafeERC20.sol";
import "./IFlashLoanRecipient.sol";
import "./LoopyConstants.sol";

contract Loopy is ILoopy, LoopyConstants, Ownable2Step, IFlashLoanRecipient, ReentrancyGuard {
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
    decimals[ARB] = 18;
    decimals[PLVGLP] = 18;

    // set the allowed tokens in the constructor
    // we can add/remove these with owner functions later
    allowedTokens[USDC] = true;
    allowedTokens[USDT] = true;
    allowedTokens[WBTC] = true;
    allowedTokens[DAI] = true;
    allowedTokens[FRAX] = true;
    allowedTokens[ARB] = true;
    allowedTokens[PLVGLP] = true;

    // map tokens to lTokens
    lTokenMapping[USDC] = lUSDC;
    lTokenMapping[USDT] = lUSDT;
    lTokenMapping[WBTC] = lWBTC;
    lTokenMapping[DAI] = lDAI;
    lTokenMapping[FRAX] = lFRAX;
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
    ARB.approve(address(VAULT), type(uint256).max);
    // approve lTokens to be minted using underlying
    PLVGLP.approve(address(lPLVGLP), type(uint256).max);
    USDC.approve(address(lUSDC), type(uint256).max);
    USDT.approve(address(lUSDT), type(uint256).max);
    WBTC.approve(address(lWBTC), type(uint256).max);
    DAI.approve(address(lDAI), type(uint256).max);
    FRAX.approve(address(lFRAX), type(uint256).max);
    ARB.approve(address(lARB), type(uint256).max);
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
  event BalancerFeeAmount(uint256 amount);

  function addToken(IERC20 tokenAddress, uint8 tokenDecimals, ICERC20 lTokenAddress) external onlyOwner {
      require(!allowedTokens[tokenAddress], "token already allowed");
      allowedTokens[tokenAddress] = true;

      // create our IERC20 object and map it accordingly
      ICERC20 _lTokenSymbol = ICERC20(lTokenAddress);
      decimals[tokenAddress] = tokenDecimals;
      lTokenMapping[tokenAddress] = _lTokenSymbol;

      // approve balance vault and the lToken market to be able to spend the newly added underlying
      tokenAddress.approve(address(VAULT), type(uint256).max);
      tokenAddress.approve(address(_lTokenSymbol), type(uint256).max);
  }

  function removeToken(IERC20 tokenAddress) external onlyOwner {
      require(allowedTokens[tokenAddress], "token not allowed");
      allowedTokens[tokenAddress] = false;

      // nullify, essentially, existing records
      delete decimals[tokenAddress];
      delete lTokenMapping[tokenAddress];
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
        _amount, // we can just send over the exact amount
        _leverage
      );
    }

    // factor in any balancer fees into the overall loan amount we wish to borrow
    uint256 currentBalancerFeeAmount = BALANCER_PROTOCOL_FEES_COLLECTOR.getFlashLoanFeePercentage();
    uint256 loanAmountFactoringInFeeAmount = loanAmount + currentBalancerFeeAmount;

    if (_tokenToBorrow.balanceOf(address(BALANCER_VAULT)) < loanAmountFactoringInFeeAmount) revert FAILED('balancer vault token balance < loan');
    emit Loan(loanAmountFactoringInFeeAmount);
    emit BalanceOf(_tokenToBorrow.balanceOf(address(BALANCER_VAULT)), loanAmountFactoringInFeeAmount);

    IERC20[] memory tokens = new IERC20[](1);
    tokens[0] = _tokenToBorrow;

    uint256[] memory loanAmounts = new uint256[](1);
    loanAmounts[0] = loanAmountFactoringInFeeAmount;

    UserData memory userData = UserData({
      user: msg.sender,
      tokenAmount: _amount,
      borrowedToken: _tokenToBorrow,
      borrowedAmount: loanAmountFactoringInFeeAmount,
      tokenToLoop: _token
    });
    emit UserDataEvent(msg.sender, _amount, address(_tokenToBorrow), loanAmountFactoringInFeeAmount, address(_token));

    BALANCER_VAULT.flashLoan(IFlashLoanRecipient(this), tokens, loanAmounts, abi.encode(userData));
  }
  

  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external override nonReentrant {
    if (msg.sender != address(BALANCER_VAULT)) revert UNAUTHORIZED('balancer vault is not the sender');

    UserData memory data = abi.decode(userData, (UserData));

    // ensure the transaction is user originated
    if (tx.origin != data.user) revert UNAUTHORIZED('user did not originate transaction');

    // ensure we borrowed the proper amounts
    if (data.borrowedAmount != amounts[0] || data.borrowedToken != tokens[0]) revert FAILED('borrowed amounts and/or borrowed tokens do not match initially set values');

    // sanity check: emit whenever the fee for balancer is greater than 0 for tracking purposes
    if (feeAmounts[0] > 0) {
      emit BalancerFeeAmount(feeAmounts[0]);
    }

    // account for some plvGLP specific logic
    if (data.tokenToLoop == PLVGLP) {

      uint256 nominalSlippage = 1e16; // 1% slippage tolerance
      uint256 glpPrice = getGLPPrice(); // returns in 1e18
      uint256 minumumExpectedUSDCSwapAmount = ((data.borrowedAmount) * (1e18 - nominalSlippage)) / 1e18;
      uint256 minimumExpectedGlpSwapAmount = glpPrice * minumumExpectedUSDCSwapAmount;

      // mint GLP. approval needed
      uint256 glpAmount = REWARD_ROUTER_V2.mintAndStakeGlp(
        address(data.borrowedToken), // the token to buy GLP with
        data.borrowedAmount, // the amount of token to use for the purchase
        0, // the minimum acceptable USD value of the GLP purchased
        minimumExpectedGlpSwapAmount // the minimum acceptible GLP amount
      );
      if (glpAmount == 0) revert FAILED('glp=0');
      if (glpAmount < minimumExpectedGlpSwapAmount) revert FAILED('glp amount returned less than minumum expected swap amount');

      // TODO whitelist this contract for plvGLP mint
      // mint plvGLP. approval needed
      uint256 _oldPlvglpBal = PLVGLP.balanceOf(address(this));
      GLP_DEPOSITOR.deposit(glpAmount);

      // check new balances and confirm we properly minted
      uint256 _newPlvglpBal = PLVGLP.balanceOf(address(this));
      emit plvGLPBalance(_newPlvglpBal);
      require(_newPlvglpBal > _oldPlvglpBal, "glp deposit failed, new balance < old balance");
    }

    uint256 _finalBal;

    // mint our respective token by depositing it into Lodestar's respective lToken contract (approval needed)
    unchecked {
      lTokenMapping[data.tokenToLoop].mint(data.tokenToLoop.balanceOf(address(this)));
      lTokenMapping[data.tokenToLoop].transfer(data.user, lTokenMapping[data.tokenToLoop].balanceOf(address(this)));
      _finalBal = lTokenMapping[data.tokenToLoop].balanceOf(address(this));

      emit lTokenBalance(_finalBal);
      require(_finalBal == 0, "lToken balance not 0 at the end of loop");
    }

    if (data.tokenToLoop == PLVGLP) {
      // plvGLP requires us to repay the loan with USDC
      lUSDC.borrowBehalf(data.borrowedAmount, data.user);
      USDC.safeTransferFrom(data.user, msg.sender, data.borrowedAmount);
    } else {
      // call borrowBehalf to borrow tokens on behalf of user
      lTokenMapping[data.tokenToLoop].borrowBehalf(data.borrowedAmount, data.user);
      // repay loan, where msg.sender = vault
      data.tokenToLoop.safeTransferFrom(data.user, msg.sender, data.borrowedAmount);
    }
  }

  function getGLPPrice() internal view returns (uint256) {
    uint256 price = PLVGLP_ORACLE.getGLPPrice();
    require(price > 0, "invalid glp price returned");

    // price = div_(price, Exp({mantissa: getPriceFromChainlink(ethUsdAggregator)}));

    //glp oracle returns price scaled to 18 decimals, no need to extend here
    return price;
  }

  function getNotionalLoanAmountIn1e18(
    uint256 _notionalTokenAmountIn1e18,
    uint16 _leverage
  ) private pure returns (uint256) {
    unchecked {
      return ((_leverage - DIVISOR) * _notionalTokenAmountIn1e18) / DIVISOR;
    }
  }

}

