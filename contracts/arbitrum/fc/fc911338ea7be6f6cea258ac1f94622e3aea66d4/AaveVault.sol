//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./IAToken.sol";
import "./IAavePool.sol";
import {WadRayMath} from "./WadRayMath.sol";

contract AaveVault is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using Address for address;
  using WadRayMath for uint256;

  IERC20 public immutable DUSD;
  IERC20 public immutable DAI;
  IERC20 public immutable FLUID;
  IAToken public immutable aArbDAI;
  address public immutable tokenTransferProxy;
  address public immutable augustus;
  IAavePool public immutable aavePool;
  address public fluidTreasury;
  uint256[] public fluidTiers = [0, 1000, 10000, 50000];
  uint256[] public feeTiers = [2000, 1500, 1300, 1000];

  mapping(address => uint256) public daiBalances;
  mapping(address => uint256) public scaledBalances;

  constructor(address _dusd, address _dai, address _fluid, address _aArbDai, address _tokenTransferProxy, address _augustusAddr, address _aavePool, address _fluidTreasury) {
    DUSD = IERC20(_dusd);
    DAI = IERC20(_dai);
    FLUID = IERC20(_fluid);
    aArbDAI = IAToken(_aArbDai);
    tokenTransferProxy = _tokenTransferProxy;
    augustus = _augustusAddr;
    aavePool = IAavePool(_aavePool);
    fluidTreasury = _fluidTreasury;
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
    // IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    // IERC20(token).safeApprove(tokenTransferProxy, amount);

    uint256 originalBalance = aArbDAI.scaledBalanceOf(address(this));
    uint256 originalDaiBalance = DAI.balanceOf(address(aArbDAI));
    callParaswap(swapCalldata);
    uint256 addedAmount = aArbDAI.scaledBalanceOf(address(this)) - originalBalance;
    uint256 addedDaiAmount = DAI.balanceOf(address(aArbDAI)) - originalDaiBalance;

    scaledBalances[msg.sender] = scaledBalances[msg.sender] + addedAmount;
    daiBalances[msg.sender] = daiBalances[msg.sender] + addedDaiAmount;
  }

  function deposit2(address token, uint256 amount, bytes memory swapCalldata) public nonReentrant {
    require(token == address(DUSD) || token == address(DAI), "Not allowed token deposited");
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(token).safeApprove(tokenTransferProxy, amount);

    uint256 originalBalance = aArbDAI.scaledBalanceOf(address(this));
    uint256 originalDaiBalance = DAI.balanceOf(address(aArbDAI));
    callParaswap(swapCalldata);
    uint256 addedAmount = aArbDAI.scaledBalanceOf(address(this)) - originalBalance;
    uint256 addedDaiAmount = DAI.balanceOf(address(aArbDAI)) - originalDaiBalance;

    scaledBalances[msg.sender] = scaledBalances[msg.sender] + addedAmount;
    daiBalances[msg.sender] = daiBalances[msg.sender] + addedDaiAmount;
  }

  function tempDeposit(uint256 amount) public nonReentrant {
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

  function withdraw() public nonReentrant returns(uint256) {
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

    DAI.safeTransfer(msg.sender, amountWithdraw);
    return amountWithdraw;
  }

  function collectFee(uint256 amount, address addr) private returns (uint256) {
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

  function emergencyTransferTokens(address tokenAddress, address to, uint256 amount) public onlyOwner {
    require(tokenAddress != address(DUSD), "Not allowed to withdraw deposited token");
    require(tokenAddress != address(DAI), "Not allowed to withdraw reward token");
    
    IERC20(tokenAddress).safeTransfer(to, amount);
  }

  function emergencyTransferETH(address payable recipient) public onlyOwner {
    Address.sendValue(recipient, address(this).balance);
  }
}

