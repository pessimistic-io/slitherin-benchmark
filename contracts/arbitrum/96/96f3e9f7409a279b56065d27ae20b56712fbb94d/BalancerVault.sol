//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IBalancerVault.sol";
import "./IBalancerHelper.sol";
import "./console.sol";

contract BalancerVaultUpgradable is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using AddressUpgradeable for address;

  uint256 public constant MAX_INT = 2**256 - 1;
  IERC20Upgradeable public DUSD;
  IERC20Upgradeable public DAI;
  IERC20Upgradeable public FLUID;
  IERC20Upgradeable public DUSDDAI_POOL;
  address public fluidTreasury;
  IBalancerVault public balancerVault;
  IBalancerHelper public balancerHelper;
  bytes32 public balancerPoolId;
  uint256[] public fluidTiers;
  uint256[] public feeTiers;

  struct DepositInfo {
    uint256 poolBalance;
    uint256 depositAmount;
    address depositToken;
  }

  mapping(address => DepositInfo) public depositBalances;

  enum ExitKind { EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, EXACT_BPT_IN_FOR_TOKENS_OUT, BPT_IN_FOR_EXACT_TOKENS_OUT }

  struct BalancerSwapOutParam {
    uint256 amount;
    address assetIn;
    address assetOut;
    address recipient;
    bytes32 poolId;
    uint256 maxAmountIn;
  }

  // @notice Emitted after successful Deposit
  // @param token The address of the token deposited
  // @param amount The amount of token that is deposited
  // @param reciever The address that got the Vault shares
  event Deposit(address token, uint256 amount ,address reciever);

  // @notice Emitted after successful Withdraw
  // @param token The address of the token Withdrawn
  // @param amount The amount of token that is Withdrawn
  // @param reciever The address that got the withdrawn tokens
  event Withdraw(address token, uint256 amount, address reciever);

  function initialize(address _dusd, address _dai, address _fluid, address _fluidTreasury, address _balancerVault, address _balancerHelper, bytes32 _balancerPoolId, address _dusdDaiPool) public initializer {
    __Ownable_init();
    DUSD = IERC20Upgradeable(_dusd);
    DAI = IERC20Upgradeable(_dai);
    FLUID = IERC20Upgradeable(_fluid);
    fluidTreasury = _fluidTreasury;
    balancerVault = IBalancerVault(_balancerVault);
    balancerHelper = IBalancerHelper(_balancerHelper);
    balancerPoolId = _balancerPoolId;
    DUSDDAI_POOL = IERC20Upgradeable(_dusdDaiPool);
    fluidTiers = [0, 1000, 10000, 50000, 150000];
    feeTiers = [2000, 1500, 1300, 1200, 1000];
  }

  function setTreasuryAddress(address _fluidTreasury) public onlyOwner {
    fluidTreasury = _fluidTreasury;
  }
  
  function setFeeFluidTier(uint256 _index, uint256 _fluidAmount) public onlyOwner {
    fluidTiers[_index] = _fluidAmount;
  }

  function setFee(uint256 _index, uint256 _fee) public onlyOwner {
    require(_fee <= 10000, "Exceeds maximum fee");

    feeTiers[_index] = _fee;
  }

  // @notice Deposit DUSD or DAI to balancer
  // @param token The token address can only be DUSD or DAI
  // @param amount The amount of token, that you want to deposit
  function deposit(address token, uint256 amount) public nonReentrant {
    require(token == address(DUSD) || token == address(DAI) || token == address(DUSDDAI_POOL), "Not allowed token deposited");
    require(amount > 0, "Not allowed to deposit zero amount");

    DepositInfo storage depositInfo = depositBalances[msg.sender];
    IERC20Upgradeable(token).transferFrom(msg.sender, address(this), amount);
    if(token == address(DUSD) || token == address(DAI)) { // When user deposit DAI or DUSD
      IERC20Upgradeable(token).approve(address(balancerVault), amount);


      address[] memory tokens = new address[](2);
      tokens[0] = address(DAI);
      tokens[1] = address(DUSD);

      uint256[] memory maxAmountsIn = new uint256[](2);
      maxAmountsIn[0] = token == address(DAI) ? amount : 0;
      maxAmountsIn[1] = token == address(DUSD) ? amount : 0;
      
      uint256 originalBalance = DUSDDAI_POOL.balanceOf(address(this));
      balancerJoinPool(tokens, maxAmountsIn, balancerPoolId);
      uint256 bptAmount = DUSDDAI_POOL.balanceOf(address(this)) - originalBalance;

      depositInfo.poolBalance += bptAmount;
      
      if(depositInfo.depositToken == address(0)) { // first deposit
        depositInfo.depositToken = token;
        depositInfo.depositAmount = depositInfo.depositAmount + amount;
      }
      else {
        if(depositInfo.depositToken == token) { // deposit same token
          depositInfo.depositAmount += amount;
        } else { 
          // check if user deposited with other token
          // get DAI or DUSD amount equivalent to BPT
          uint256 newAmount = getTokenAmountFromBPT(depositInfo.depositToken, bptAmount);

          depositInfo.depositAmount += newAmount;
        }
      }
    }
    else if(token == address(DUSDDAI_POOL)) { // When user deposit BPT directly\
      if(depositInfo.depositToken == address(0)) {
        depositInfo.depositToken = address(DAI);
      }

      // get DAI or DUSD amount equivalent to BPT
      uint256 tokenWithdrawalAmount = getTokenAmountFromBPT(depositInfo.depositToken, amount);

      depositInfo.depositAmount += tokenWithdrawalAmount;
      depositInfo.poolBalance = depositInfo.poolBalance + amount;
    }
    emit Deposit(token, amount, msg.sender);
  }
  // @notice Withdraw fixed amount from vault
  // @param token The token address the you want withdrawl in, can only be DUSD or DAI
  // @param amount The amount of token that you want to writhdraw
  // @return amountWithdrawn The amount of toke withdraw from the vault
  function withdraw(address token, uint256 amount) public nonReentrant returns(uint256 amountWithdraw) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token withdrawal");
    
    DepositInfo storage depositInfo = depositBalances[msg.sender];

    require(depositInfo.depositToken != address(0), "Zero Deposits");

    DUSDDAI_POOL.approve(address(balancerVault), depositInfo.poolBalance);

    address[] memory tokens = new address[](2);
    tokens[0] = address(DAI);
    tokens[1] = address(DUSD);

    address depositToken = depositInfo.depositToken;

    uint256[] memory minAmountsOut = new uint256[](2);
    uint256[] memory amountsOut = new uint256[](2);
    amountsOut[0] = token == address(DAI) ? amount : 0;
    amountsOut[1] = token == address(DUSD) ? amount : 0;

    uint256 originalBalance = IERC20Upgradeable(DUSDDAI_POOL).balanceOf(address(this));
    balancerCustomExitPool(tokens, minAmountsOut, balancerPoolId, amountsOut, depositInfo.poolBalance);
    uint256 bptAmount = originalBalance - IERC20Upgradeable(DUSDDAI_POOL).balanceOf(address(this));

    uint256 depositSubAmount = depositInfo.depositAmount * bptAmount / depositInfo.poolBalance;
    uint256 tokenWithdrawalAmount = token == depositInfo.depositToken ? amount : getTokenAmountFromBPT(depositInfo.depositToken, bptAmount);
    depositBalances[msg.sender].depositAmount = depositInfo.depositAmount - depositSubAmount;
    depositBalances[msg.sender].poolBalance = depositInfo.poolBalance - bptAmount;
    
    amountWithdraw = amount;
    {
      // scoping to eliminate, stack too deep error
      uint256 reward;
      if (tokenWithdrawalAmount > depositSubAmount) {
        reward = collectFee(tokenWithdrawalAmount - depositSubAmount, msg.sender);
      }
      
      if(reward > 0) {
        if(token == depositToken) {
          IERC20Upgradeable(token).transfer(fluidTreasury, reward);
          amountWithdraw -= reward;
        } else {
          // swap token to reward amount of depositToken
          amountWithdraw -= balancerSwapOut(BalancerSwapOutParam(
            reward, 
            token, 
            depositToken, 
            fluidTreasury, 
            balancerPoolId, 
            amount
          ));
        }
      }
    }

    IERC20Upgradeable(token).transfer(msg.sender, amountWithdraw);
    emit Withdraw(token, amount, msg.sender);
  }
  
  // @notice Withdraw All the deposit at once
  // @param token The token address the you want withdrawl in, can only be DUSD or DAI
  // @return amountWithdrawn The amount of token to withdraw from the vault
  function withdrawAll(address token) public nonReentrant returns(uint256 amountWithdraw) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token withdrawal");
    DepositInfo storage depositInfo = depositBalances[msg.sender];
    require(depositBalances[msg.sender].depositToken != address(0), "Zero Deposits");

    DUSDDAI_POOL.approve(address(balancerVault), depositInfo.poolBalance);

    address[] memory tokens = new address[](2);
    tokens[0] = address(DAI);
    tokens[1] = address(DUSD);

    uint256[] memory minAmountsOut = new uint256[](2);

    address depositToken = depositInfo.depositToken;
    uint256 tokenIndex = depositToken == address(DAI) ? 0 : 1;

    uint256 originalBalance = IERC20Upgradeable(depositToken).balanceOf(address(this));
    balancerExitPool(tokens, minAmountsOut, balancerPoolId, depositInfo.poolBalance, tokenIndex);
    amountWithdraw = IERC20Upgradeable(depositToken).balanceOf(address(this)) - originalBalance;

    uint256 originalDepositAmount = depositInfo.depositAmount;

    depositInfo.depositToken = address(0);
    depositInfo.depositAmount = 0;
    depositInfo.poolBalance = 0;

    if(amountWithdraw > originalDepositAmount) {
      uint256 reward = amountWithdraw - originalDepositAmount;
      reward = collectFee(reward, msg.sender);
      IERC20Upgradeable(depositToken).transfer(fluidTreasury, reward);
      amountWithdraw -= reward;
    }

    if(token == depositToken) {
      IERC20Upgradeable(token).transfer(msg.sender, amountWithdraw);
    }
    else {
      amountWithdraw = balancerSwapIn(amountWithdraw, depositToken, token, msg.sender, balancerPoolId);
    }

    emit Withdraw(token, amountWithdraw, msg.sender);
  }

 function collectFee(uint256 amount, address addr) private view returns (uint256 feeAmount) {
    uint256 fee;
    uint256 balance = FLUID.balanceOf(addr);
    for (uint256 i = 0; i <= 4; ) {
      if (balance >= fluidTiers[i] * 10**18) {
        fee = feeTiers[i];
      }
      unchecked {
        ++i;
      }
    }
    feeAmount = amount * fee / 10000;
  }

  function balancerJoinPool(address[] memory tokens, uint256[] memory maxAmountsIn, bytes32 poolId) internal {
    bytes memory userData = abi.encode(1, maxAmountsIn, 0); // JoinKind: 1
    balancerVault.joinPool(
      poolId,
      address(this),
      address(this),
      IBalancerVault.JoinPoolRequest(tokens, maxAmountsIn, userData, false)
    );
  }

  // balancer exit pool with bptAmountIn
  function balancerExitPool(address[] memory tokens, uint256[] memory minAmountsOut, bytes32 poolId, uint256 bptAmountIn, uint256 tokenIndex) internal {
    balancerVault.exitPool(
      poolId,
      address(this),
      payable(address(this)),
      IBalancerVault.ExitPoolRequest(tokens, minAmountsOut, abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmountIn, tokenIndex), false)
    );
  }

  // balancer exit pool with custom tokenOut amount
  function balancerCustomExitPool(address[] memory tokens, uint256[] memory minAmountsOut, bytes32 poolId, uint256[] memory amountsOut, uint256 maxBPTAmountIn) internal {
    balancerVault.exitPool(
      poolId,
      address(this),
      payable(address(this)),
      IBalancerVault.ExitPoolRequest(tokens, minAmountsOut, abi.encode(ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT, amountsOut, maxBPTAmountIn), false)
    );
  }

  function userWithdrawalAmount(address _addr, address token) public returns (uint256 tokenWithdrawalAmount) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token");

    tokenWithdrawalAmount = getTokenAmountFromBPT(token, depositBalances[_addr].poolBalance);
  }
  
  /// static calling this function
  function userReward(address _addr, address token) public returns (uint256 profit) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token");
    uint256 bptBalance = depositBalances[_addr].poolBalance;
    uint256 depositAmount = depositBalances[_addr].depositAmount;
    address depositToken = depositBalances[_addr].depositToken;
    uint256 tokenWithdrawalAmount = getTokenAmountFromBPT(depositToken, bptBalance);
    
    if(tokenWithdrawalAmount > depositAmount) {
      profit = tokenWithdrawalAmount - depositAmount;

      if(token == depositToken) return profit;

      uint256 profitInBpt = profit * bptBalance / tokenWithdrawalAmount;
      profit = getTokenAmountFromBPT(token, profitInBpt);
    }
    return profit;
  }

  function getTokenAmountFromBPT(address tokenOut, uint256 bptAmountIn) public returns (uint256) {
    require(tokenOut == address(DUSD) || tokenOut == address(DAI), "Not allowed tokenOut");

    address[] memory tokens = new address[](2);
    tokens[0] = address(DAI);
    tokens[1] = address(DUSD);
    uint256[] memory minAmountsOut = new uint256[](2);
    uint256 tokenIndex = tokenOut == address(DAI) ? 0 : 1;
    uint256 tokenWithdrawalAmount = balancerQueryExit(tokens, minAmountsOut, balancerPoolId, bptAmountIn, tokenIndex); // token index : 0 - dai, 1 - dusd
    return tokenWithdrawalAmount;
  }
  
  function balancerQueryExit(address[] memory tokens, uint256[] memory minAmountsOut, bytes32 poolId, uint256 bptAmountIn, uint256 tokenIndex) internal returns (uint256) {
    uint256 bptIn;
    uint256[] memory amountsOut;
    (bptIn, amountsOut) = balancerHelper.queryExit(
      poolId,
      address(this),
      payable(address(this)),
      IBalancerVault.ExitPoolRequest(tokens, minAmountsOut, abi.encode(ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, bptAmountIn, tokenIndex), false)
    );
    return amountsOut[tokenIndex];
  }

  function balancerSwapIn(uint256 amount, address assetIn, address assetOut, address recipient, bytes32 poolId) internal returns (uint256) {
    IERC20Upgradeable(assetIn).approve(address(balancerVault), amount);
    bytes memory userData;
    uint256 value = balancerVault.swap(
      IBalancerVault.SingleSwap(poolId, IBalancerVault.SwapKind.GIVEN_IN, assetIn, assetOut, amount, userData),
      IBalancerVault.FundManagement(address(this), true, payable(recipient), false),
      0,
      MAX_INT
    );
    return value;
  }

  function balancerSwapOut(BalancerSwapOutParam memory param) internal returns (uint256) {
    IERC20Upgradeable(param.assetIn).approve(address(balancerVault), param.maxAmountIn);
    return balancerVault.swap(
      IBalancerVault.SingleSwap(param.poolId, IBalancerVault.SwapKind.GIVEN_OUT, param.assetIn, param.assetOut, param.amount, ""),
      IBalancerVault.FundManagement(address(this), true, payable(param.recipient), false),
      param.maxAmountIn,
      MAX_INT
    );
  }

  function emergencyTransferTokens(address tokenAddress, address to, uint256 amount) public onlyOwner {
    require(tokenAddress != address(DUSD), "Not allowed to withdraw deposited token");
    require(tokenAddress != address(DAI), "Not allowed to withdraw reward token");
    
    IERC20Upgradeable(tokenAddress).transfer(to, amount);
  }

  function emergencyTransferETH(address payable recipient) public onlyOwner {
    AddressUpgradeable.sendValue(recipient, address(this).balance);
  }
}

