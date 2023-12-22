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
    fluidTiers = [0, 1000, 10000, 50000];
    feeTiers = [2000, 1500, 1300, 1000];
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

  function deposit(address token, uint256 amount) public nonReentrant {
    require(token == address(DUSD) || token == address(DAI) || token == address(DUSDDAI_POOL), "Not allowed token deposited");
    require(amount > 0, "Not allowed to deposit zero amount");

    if(token == address(DUSD) || token == address(DAI)) { // When user deposit DAI or DUSD

      IERC20Upgradeable(token).transferFrom(msg.sender, address(this), amount);
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
      depositBalances[msg.sender].poolBalance = depositBalances[msg.sender].poolBalance + bptAmount;
      
      if(depositBalances[msg.sender].depositToken == address(0)) { // first deposit
        depositBalances[msg.sender].depositToken = token;
        depositBalances[msg.sender].depositAmount = depositBalances[msg.sender].depositAmount + amount;
      }
      else {
        if(depositBalances[msg.sender].depositToken == token) { // deposit same token
          depositBalances[msg.sender].depositAmount = depositBalances[msg.sender].depositAmount + amount;
        } else { // check if user deposited with other token
          // get DAI or DUSD amount equivalent to BPT
          uint256 newAmount = getTokenAmountFromBPT(depositBalances[msg.sender].depositToken, bptAmount);

          depositBalances[msg.sender].depositAmount = depositBalances[msg.sender].depositAmount + newAmount;
        }
      }
    }
    else if(token == address(DUSDDAI_POOL)) { // When user deposit BPT directly
      IERC20Upgradeable(token).transferFrom(msg.sender, address(this), amount);
      if(depositBalances[msg.sender].depositToken == address(0)) {
        depositBalances[msg.sender].depositToken = address(DAI);
      }

      // get DAI or DUSD amount equivalent to BPT
      uint256 tokenWithdrawalAmount = getTokenAmountFromBPT(depositBalances[msg.sender].depositToken, amount);

      depositBalances[msg.sender].depositAmount = depositBalances[msg.sender].depositAmount + tokenWithdrawalAmount;
      depositBalances[msg.sender].poolBalance = depositBalances[msg.sender].poolBalance + amount;
    }
  }

  function withdraw(address token, uint256 amount) public nonReentrant returns(uint256) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token withdrawal");
    require(depositBalances[msg.sender].depositToken != address(0), "Not enough amount to withdraw");

    address[] memory tokens = new address[](2);
    tokens[0] = address(DAI);
    tokens[1] = address(DUSD);

    address depositToken = depositBalances[msg.sender].depositToken;

    uint256[] memory minAmountsOut = new uint256[](2);
    uint256[] memory amountsOut = new uint256[](2);
    amountsOut[0] = token == address(DAI) ? amount : 0;
    amountsOut[1] = token == address(DUSD) ? amount : 0;

    uint256 originalBalance = IERC20Upgradeable(DUSDDAI_POOL).balanceOf(address(this));
    balancerCustomExitPool(tokens, minAmountsOut, balancerPoolId, amountsOut, depositBalances[msg.sender].poolBalance);
    uint256 bptAmount = originalBalance - IERC20Upgradeable(DUSDDAI_POOL).balanceOf(address(this));

    uint256 depositSubAmount = depositBalances[msg.sender].depositAmount * bptAmount / depositBalances[msg.sender].poolBalance;
    uint256 tokenWithdrawalAmount = token == depositToken ? amount : getTokenAmountFromBPT(depositToken, bptAmount);
    depositBalances[msg.sender].depositAmount = depositBalances[msg.sender].depositAmount - depositSubAmount;
    depositBalances[msg.sender].poolBalance = depositBalances[msg.sender].poolBalance - bptAmount;
    
    uint256 amountWithdraw = amount;
    uint256 reward;
    if (tokenWithdrawalAmount > depositSubAmount) {
      reward = collectFee(tokenWithdrawalAmount - depositSubAmount, msg.sender);
    }
    
    if(reward > 0) {
      if(token == depositToken) {
        IERC20Upgradeable(token).transfer(fluidTreasury, reward);
        amountWithdraw = amountWithdraw - reward;
      } else {
        // swap token to reward amount of depositToken
        amountWithdraw = amountWithdraw - balancerSwapOut(BalancerSwapOutParam(reward, token, depositToken, fluidTreasury, balancerPoolId, amount));
      }
    }

    IERC20Upgradeable(token).transfer(msg.sender, amountWithdraw);
    return amountWithdraw;
  }
  
  function withdrawAll(address token) public nonReentrant returns(uint256) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token withdrawal");
    require(depositBalances[msg.sender].depositToken != address(0), "Not enough amount to withdraw");

    DUSDDAI_POOL.approve(address(balancerVault), depositBalances[msg.sender].poolBalance);

    address[] memory tokens = new address[](2);
    tokens[0] = address(DAI);
    tokens[1] = address(DUSD);

    uint256[] memory minAmountsOut = new uint256[](2);

    address depositToken = depositBalances[msg.sender].depositToken;
    uint256 tokenIndex = depositToken == address(DAI) ? 0 : 1;

    uint256 originalBalance = IERC20Upgradeable(depositToken).balanceOf(address(this));
    balancerExitPool(tokens, minAmountsOut, balancerPoolId, depositBalances[msg.sender].poolBalance, tokenIndex);
    uint256 amountWithdraw = IERC20Upgradeable(depositToken).balanceOf(address(this)) - originalBalance;

    uint256 originalDepositAmount = depositBalances[msg.sender].depositAmount;

    depositBalances[msg.sender].depositToken = address(0);
    depositBalances[msg.sender].depositAmount = 0;
    depositBalances[msg.sender].poolBalance = 0;

    if(amountWithdraw > originalDepositAmount) {
      uint256 reward = amountWithdraw - originalDepositAmount;
      reward = collectFee(reward, msg.sender);
      IERC20Upgradeable(depositToken).transfer(fluidTreasury, reward);
      amountWithdraw = amountWithdraw - reward;
    }

    if(token == depositToken) {
      IERC20Upgradeable(token).transfer(msg.sender, amountWithdraw);
    }
    else {
      amountWithdraw = balancerSwapIn(amountWithdraw, depositToken, token, msg.sender, balancerPoolId);
    }

    return amountWithdraw;
  }

  function collectFee(uint256 amount, address addr) private view returns (uint256) {
    uint256 fee = feeTiers[0];
    uint256 balance = FLUID.balanceOf(addr);
    for (uint256 i = 0; i <= 3; i++) {
      if (balance >= fluidTiers[i] * 10**18) {
        fee = feeTiers[i];
      }
    }
    uint256 feeAmount = amount * fee / 10000;
    return feeAmount;
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

  function userWithdrawalAmount(address _addr) public returns (uint256) {
    uint256 tokenWithdrawalAmount = getTokenAmountFromBPT(depositBalances[_addr].depositToken, depositBalances[_addr].poolBalance);
    return tokenWithdrawalAmount;
  }
  
  function userReward(address _addr) public returns (uint256) {
    uint256 tokenWithdrawalAmount = getTokenAmountFromBPT(depositBalances[_addr].depositToken, depositBalances[_addr].poolBalance);
    
    if(tokenWithdrawalAmount > depositBalances[_addr].depositAmount)
      return tokenWithdrawalAmount - depositBalances[_addr].depositAmount;
    return 0;
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
    bytes memory userData = "";
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

