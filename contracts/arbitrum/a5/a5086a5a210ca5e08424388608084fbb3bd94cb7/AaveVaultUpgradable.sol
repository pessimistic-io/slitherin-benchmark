//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IAToken.sol";
import "./IAavePool.sol";
import "./IBalancerVault.sol";
import {WadRayMath} from "./WadRayMath.sol";

contract AaveVaultUpgradable is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using WadRayMath for uint256;

  uint256 public constant MAX_INT = 2**256 - 1;
  IERC20Upgradeable public DUSD;
  IERC20Upgradeable public DAI;
  IERC20Upgradeable public FLUID;
  IAToken public aArbDAI;
  address public tokenTransferProxy;
  address public augustus;
  IAavePool public aavePool;
  address public fluidTreasury;
  IBalancerVault public balancerVault;
  bytes32 public balancerPoolId;
  uint256[] public fluidTiers;
  uint256[] public feeTiers;

  mapping(address => uint256) public daiBalances;
  mapping(address => uint256) public scaledBalances;

  function initialize(address _dusd, address _dai, address _fluid, address _aArbDai, address _tokenTransferProxy, address _augustusAddr, address _aavePool, address _fluidTreasury, address _balancerVault, bytes32 _balancerPoolId) public initializer {
    __Ownable_init();
    DUSD = IERC20Upgradeable(_dusd);
    DAI = IERC20Upgradeable(_dai);
    FLUID = IERC20Upgradeable(_fluid);
    aArbDAI = IAToken(_aArbDai);
    tokenTransferProxy = _tokenTransferProxy;
    augustus = _augustusAddr;
    aavePool = IAavePool(_aavePool);
    fluidTreasury = _fluidTreasury;
    balancerVault = IBalancerVault(_balancerVault);
    balancerPoolId = _balancerPoolId;
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

  function deposit(address token, uint256 amount, bytes memory swapCalldata) public nonReentrant {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token deposited");
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    IERC20Upgradeable(token).safeApprove(tokenTransferProxy, amount);

    uint256 originalBalance = aArbDAI.scaledBalanceOf(address(this));
    uint256 originalDaiBalance = DAI.balanceOf(address(aArbDAI));
    callParaswap(swapCalldata);
    uint256 addedAmount = aArbDAI.scaledBalanceOf(address(this)) - originalBalance;
    uint256 addedDaiAmount = DAI.balanceOf(address(aArbDAI)) - originalDaiBalance;

    scaledBalances[msg.sender] = scaledBalances[msg.sender] + addedAmount;
    daiBalances[msg.sender] = daiBalances[msg.sender] + addedDaiAmount;
  }

  function depositDai(uint256 amount) public nonReentrant {
    uint256 originalBalance = aArbDAI.scaledBalanceOf(address(this));
    DAI.safeTransferFrom(msg.sender, address(this), amount);
    DAI.approve(address(aavePool), amount);
    aavePool.deposit(address(DAI), amount, address(this), 0);
    uint256 addedAmount = aArbDAI.scaledBalanceOf(address(this)) - originalBalance;
    
    scaledBalances[msg.sender] = scaledBalances[msg.sender] + addedAmount;
    daiBalances[msg.sender] = daiBalances[msg.sender] + amount;
  }

  function userBalance(address _addr) public view returns(uint256) {
    DataTypes.ReserveData memory reserve = aavePool.getReserveData(address(DAI));
    uint256 balance = scaledBalances[_addr].rayMul(reserve.liquidityIndex);
    return balance;
  }

  function withdraw(address token, uint256 amount) public nonReentrant returns(uint256) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token deposited");

    uint256 amountInDai = token == address(DAI)? amount : getDaiAmountFromDUSD(amount);
    
    uint256 aDaiBalance = aArbDAI.scaledBalanceOf(address(this));
    uint256 amountWithdraw = aavePool.withdraw(address(DAI), amountInDai, address(this));
    uint256 subAmount = aDaiBalance - aArbDAI.scaledBalanceOf(address(this));
    
    require(scaledBalances[msg.sender] >= subAmount, "Exceeds max withdrawal amount");
    uint256 daiSubAmount = daiBalances[msg.sender] * subAmount / scaledBalances[msg.sender];
    scaledBalances[msg.sender] = scaledBalances[msg.sender] - subAmount;
    daiBalances[msg.sender] = daiBalances[msg.sender] - daiSubAmount;

    if(amountWithdraw > daiSubAmount) {
      uint256 reward = amountWithdraw - daiSubAmount;
      reward = collectFee(reward, msg.sender);
      DAI.safeTransfer(fluidTreasury, reward);
      amountWithdraw = amountWithdraw - reward;
    }

    if (token == address(DAI)) {
      DAI.safeTransfer(msg.sender, amountWithdraw);
    }
    else if (token == address(DUSD)) {
      amountWithdraw = balancerSwap(amountWithdraw, address(DAI), address(DUSD), msg.sender, balancerPoolId);
    }

    return amountWithdraw;
  }

  function withdrawAll(address token) public nonReentrant returns(uint256) {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token deposited");

    DataTypes.ReserveData memory reserve = aavePool.getReserveData(address(DAI));
    uint256 balance = scaledBalances[msg.sender].rayMul(reserve.liquidityIndex);
    
    uint256 aDaiBalance = aArbDAI.scaledBalanceOf(address(this));
    uint256 amountWithdraw = aavePool.withdraw(address(DAI), balance, address(this));
    uint256 subAmount = aDaiBalance - aArbDAI.scaledBalanceOf(address(this));
    
    scaledBalances[msg.sender] = scaledBalances[msg.sender] - subAmount;
    uint256 originalDaiBalance = daiBalances[msg.sender];
    daiBalances[msg.sender] = 0;

    if(amountWithdraw > originalDaiBalance) {
      uint256 reward = amountWithdraw - originalDaiBalance;
      reward = collectFee(reward, msg.sender);
      DAI.safeTransfer(fluidTreasury, reward);
      amountWithdraw = amountWithdraw - reward;
    }

    if (token == address(DAI)) {
      DAI.safeTransfer(msg.sender, amountWithdraw);
    }
    else if (token == address(DUSD)) {
      amountWithdraw = balancerSwap(amountWithdraw, address(DAI), address(DUSD), msg.sender, balancerPoolId);
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

  function callParaswap(bytes memory swapCalldata) internal {
    (bool success,) = augustus.call(swapCalldata);

    if (!success) {
      // Copy revert reason from call
      assembly {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
      }
    }
  }
  
  function getDaiAmountFromDUSD(uint256 amount) public returns (uint256) {
    IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](1);
    swaps[0] = IBalancerVault.BatchSwapStep(balancerPoolId, 0, 1, amount, "");
    address[] memory tokens = new address[](2);
    tokens[0] = address(DAI);
    tokens[1] = address(DUSD);

    int256[] memory assetDeltas = new int256[](2);
    assetDeltas = balancerVault.queryBatchSwap(
      IBalancerVault.SwapKind.GIVEN_OUT,
      swaps,
      tokens,
      IBalancerVault.FundManagement(address(this), true, payable(address(this)), false)
    );
    return uint256(assetDeltas[0]);
  }

  function balancerSwap(uint256 amount, address assetIn, address assetOut, address recipient, bytes32 poolId) internal returns (uint256) {
    IERC20Upgradeable(assetIn).safeApprove(address(balancerVault), amount);
    bytes memory userData = "";
    uint256 value = balancerVault.swap(
      IBalancerVault.SingleSwap(poolId, IBalancerVault.SwapKind.GIVEN_IN, assetIn, assetOut, amount, userData),
      IBalancerVault.FundManagement(address(this), true, payable(recipient), false),
      0,
      MAX_INT
    );
    return value;
  }

  function emergencyTransferTokens(address tokenAddress, address to, uint256 amount) public onlyOwner {
    require(tokenAddress != address(DUSD), "Not allowed to withdraw deposited token");
    require(tokenAddress != address(DAI), "Not allowed to withdraw reward token");
    
    IERC20Upgradeable(tokenAddress).safeTransfer(to, amount);
  }

  function emergencyTransferETH(address payable recipient) public onlyOwner {
    AddressUpgradeable.sendValue(recipient, address(this).balance);
  }
}

