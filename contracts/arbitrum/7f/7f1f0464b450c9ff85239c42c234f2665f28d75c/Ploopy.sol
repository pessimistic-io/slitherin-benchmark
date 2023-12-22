// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IFlashLoanRecipient.sol";
import "./PloopyConstants.sol";

contract Ploopy is IPloopy, PloopyConstants, Ownable, IFlashLoanRecipient, ReentrancyGuard {
  // Add mapping of token addresses to their decimal places
  mapping(IERC20 => uint8) public decimals;
  // Add mapping to store the allowed tokens. Mapping provides faster access than array
  mapping(IERC20 => bool) public allowedTokens;
  // Add mapping to store lToken contracts
  mapping(IERC20 => ICERC20) private lTokenMapping;

  constructor() {
    // Initialize decimals for each token
    decimals[USDC] = 6;
    // decimals[USDT] = 6;
    // decimals[WBTC] = 8;
    // decimals[DAI] = 18;
    // decimals[ETH] = 18;
    // decimals[ARB] = 18;
    // decimals[DPX] = 18;
    // decimals[MAGIC] = 18;
    decimals[PLVGLP] = 18;

    // Set the allowed tokens in the constructor, we can add/remove these with owner functions later
    allowedTokens[USDC] = true;
    // allowedTokens[USDT] = true;
    // allowedTokens[WBTC] = true;
    // allowedTokens[DAI] = true;
    // allowedTokens[ETH] = true;
    // allowedTokens[ARB] = true;
    // allowedTokens[DPX] = true;
    // allowedTokens[MAGIC] = true;
    allowedTokens[PLVGLP] = true;

    // Map tokens to lTokens
    lTokenMapping[USDC] = lUSDC;
    lTokenMapping[PLVGLP] = lPLVGLP;

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
    // approve lTokens to be minted using underlying
    PLVGLP.approve(address(lPLVGLP), type(uint256).max);
    USDC.approve(address(lUSDC), type(uint256).max);
  }

  // Declare events
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Loan(uint256 value);
  event BalanceOf(uint256 balanceAmount, uint256 loanAmount);
  event Allowance(uint256 allowance, uint256 loanAmount);
  event UserDataEvent(address indexed from, uint256 tokenAmount, address borrowedToken, uint256 borrowedAmount, address tokenToLoop);
  event plvGLPBalance(uint256 balanceAmount);
  event lTokenBalance(uint256 balanceAmount);

  // Function to add a token to the list of allowed tokens
  function addToken(IERC20 token) external onlyOwner {
      require(!allowedTokens[token], "Token already allowed");
      allowedTokens[token] = true;
  }

  // Function to remove a token from the list of allowed tokens
  function removeToken(IERC20 token) external onlyOwner {
      require(allowedTokens[token], "Token not allowed");
      allowedTokens[token] = false;
  }
  // The juice. Allows users to loop to a desired leverage, within our ranges
  function loop(IERC20 _token, uint256 _amount, uint16 _leverage) external {
    require(allowedTokens[_token], "Token not allowed to loop");
    require(tx.origin == msg.sender, "Not an EOA");
    require(_amount > 0, "Amount must be greater than 0");
    require(_leverage >= DIVISOR && _leverage <= MAX_LEVERAGE, "Invalid leverage, range must be between DIVISOR and MAX_LEVERAGE values");

    // Transfer tokens to this contract so we can mint in 1 go.
    // PLVGLP.transferFrom(msg.sender, address(this), _plvGlpAmount);
    _token.transferFrom(msg.sender, address(this), _amount);
    emit Transfer(msg.sender, address(this), _amount);

    // TODO: need to get getUnderlyingPrice() function working for our PriceOracleProxyETH contract we are testing with
    
    uint256 loanAmount;
    IERC20 _tokenToBorrow;
    if (_token == PLVGLP) {
      // plvGLP borrows USDC to loop
      _tokenToBorrow = USDC;
      loanAmount = getNotionalLoanAmountIn1e18(
      _amount * PRICE_ORACLE.getUnderlyingPrice(address(_token)),
        _leverage
      ) / 1e12; //usdc is 6 decimals  
      // if a user is looping any of the other allowed tokens, we can just flashloan to make the process much easier
    } else {
      // The rest of the contracts just borrow whatever token is supplied, for now
      _tokenToBorrow = _token;
      loanAmount = getNotionalLoanAmountIn1e18(
        _amount * PRICE_ORACLE.getUnderlyingPrice(address(_token)),
        _leverage
      ) / (1e18 - decimals[_tokenToBorrow]); //account for the respective decimals
    }
    if (_tokenToBorrow.balanceOf(address(BALANCER_VAULT)) < loanAmount) revert FAILED('balance vault token balance<loan');
    emit Loan(loanAmount);
    emit BalanceOf(_tokenToBorrow.balanceOf(address(BALANCER_VAULT)), loanAmount);

    // check approval to spend USDC (for paying back flashloan).
    // Possibly can omit to save gas as tx will fail with exceed allowance anyway.
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

    // Now that we have all of the respective user data, its time to flash loan
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

    // account for some plvGLP specific logic
    if (data.tokenToLoop == PLVGLP) {
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
      uint256 _oldPlvglpBal = PLVGLP.balanceOf(address(this));
      GLP_DEPOSITOR.deposit(glpAmount);

      // check new balances and confirm we properly minted
      uint256 _newPlvglpBal = PLVGLP.balanceOf(address(this));
      emit plvGLPBalance(_newPlvglpBal);
      require(_newPlvglpBal > _oldPlvglpBal, "GLP deposit failed");
    }

    // mint our respective token by depositing it into Lodestar's respective lToken contract.
    // approval needed.
    unchecked {
      lTokenMapping[data.tokenToLoop].mint(data.tokenToLoop.balanceOf(address(this)));
      // lPLVGLP.mint(PLVGLP.balanceOf(address(this)));

      // transfer lPLVGLP minted to user
      lTokenMapping[data.tokenToLoop].transfer(data.user, lTokenMapping[data.tokenToLoop].balanceOf(address(this)));

      // ensure we have no remaining lPLVGLP left over
      uint256 _finalBal = lTokenMapping[data.tokenToLoop].balanceOf(address(this));
      emit lTokenBalance(_finalBal);
      require(_finalBal == 0, "lToken balance not 0 at the end of loop");
    }

    // call borrowBehalf to borrow USDC on behalf of user
    lTokenMapping[data.tokenToLoop].borrowBehalf(data.borrowedAmount, data.user);

    // repay loan: msg.sender = vault
    data.tokenToLoop.transferFrom(data.user, msg.sender, data.borrowedAmount);
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

