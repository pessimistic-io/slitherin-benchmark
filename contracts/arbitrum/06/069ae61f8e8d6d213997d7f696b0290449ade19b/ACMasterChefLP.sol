// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./IERC20.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";

import "./AutoCompoundVault.sol";

interface IFarm {
  function deposit(
    address _for,
    address _stakeToken,
    uint256 _amount
  ) external;

  function withdraw(
    address _for,
    address _stakeToken,
    uint256 _amount
  ) external;

  function userInfo(address _stakeToken, address _user) external view returns (uint256, uint256);

  function emergencyWithdraw(address _for, address _stakeToken) external;
}

/**
 * @title AutoCompound MasterChef
 * @notice vault for auto-compounding LPs on pools using a standard MasterChef contract
 * @author YieldWolf
 */
contract ACMasterChefLP is AutoCompoundVault {
  IUniswapV2Router02 public immutable liquidityRouter; // router used for adding liquidity to the LP token
  IERC20 public immutable token0; // first token of the lp
  IERC20 public immutable token1; // second token of the lp

  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _pid,
    address[6] memory _addresses,
    IUniswapV2Router02 _liquidityRouter
  ) ERC20(_name, _symbol) AutoCompoundVault(_pid, _addresses) {
    token0 = IERC20(IUniswapV2Pair(_addresses[1]).token0());
    token1 = IERC20(IUniswapV2Pair(_addresses[1]).token1());
    liquidityRouter = _liquidityRouter;
    token0.approve(address(liquidityRouter), type(uint256).max);
    token1.approve(address(liquidityRouter), type(uint256).max);
  }

  function _earnToStake(uint256 _earnAmount) internal override {
    uint256 halfEarnAmount = _earnAmount / 2;
    if (earnToken != token0) {
      _safeSwap(halfEarnAmount, address(earnToken), address(token0));
    }
    if (earnToken != token1) {
      _safeSwap(halfEarnAmount, address(earnToken), address(token1));
    }
    uint256 token0Amt = token0.balanceOf(address(this));
    uint256 token1Amt = token1.balanceOf(address(this));
    liquidityRouter.addLiquidity(
      address(token0),
      address(token1),
      token0Amt,
      token1Amt,
      1,
      1,
      address(this),
      block.timestamp
    );
  }

  function _farmDeposit(uint256 amount) internal override {
    IFarm(masterChef).deposit(address(this), address(stakeToken), amount);
  }

  function _farmWithdraw(uint256 amount) internal override {
    IFarm(masterChef).withdraw(address(this), address(stakeToken), amount);
  }

  function _farmEmergencyWithdraw() internal override {
    IFarm(masterChef).emergencyWithdraw(address(this), address(stakeToken));
  }

  function _totalStaked() internal view override returns (uint256 amount) {
    (amount, ) = IFarm(masterChef).userInfo(address(stakeToken), address(this));
  }

  function _addAllawences() internal override {
    IERC20(stakeToken).approve(masterChef, type(uint256).max);
    token0.approve(address(liquidityRouter), type(uint256).max);
    token1.approve(address(liquidityRouter), type(uint256).max);
  }

  function _removeAllawences() internal override {
    IERC20(stakeToken).approve(masterChef, 0);
    token0.approve(address(liquidityRouter), 0);
    token1.approve(address(liquidityRouter), 0);
  }
}

