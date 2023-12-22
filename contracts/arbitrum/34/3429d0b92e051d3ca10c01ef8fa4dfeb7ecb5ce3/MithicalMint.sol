// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

// Contracts
import "./Ownable.sol";
import { SafeERC20 } from "./SafeERC20.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IMithicalNFT } from "./IMithicalNFT.sol";
import { IStakingRewards } from "./IStakingRewards.sol";
import { IUniswapV2Router01 } from "./IUniswapV2Router01.sol";

contract MithicalMint is Ownable {
  using SafeERC20 for IERC20;

  address public mithicalNFTContract;
  address public dpx;
  address public rdpx;
  address public weth;
  address public dpxWethLP;
  address public stakingRewards;
  address public uniswapV2Router01;
  uint256 public maxSupply = 1000;
  uint256 public maxLpDeposits = 2437500000000000000000;
  bool public paused = false;
  bool public depositPeriod = true;
  bool public farmingPeriod = false;
  uint256 public totalDeposits;
  uint256 public dpxRewards;
  uint256 public rdpxRewards;
  uint256 public mintPrice;

  /// @notice user Deposits
  /// @dev mapping (user => deposit)
  mapping(address => uint256) public usersDeposit;

  /// @notice didUserMint
  /// @dev mapping (user => didUserMint)
  mapping(address => bool) public didUserMint;

  constructor(
    address _mithicalNFTContract,
    address _dpx,
    address _rdpx,
    address _weth,
    address _lp,
    address _stakingRewards,
    address _uniswapV2Router01
  ) {
    require(
      _mithicalNFTContract != address(0),
      "Address can't be zero address"
    );
    require(_dpx != address(0), "Address can't be zero address");
    require(_rdpx != address(0), "Address can't be zero address");
    require(_weth != address(0), "Address can't be zero address");
    require(_lp != address(0), "Address can't be zero address");
    require(_stakingRewards != address(0), "Address can't be zero address");
    require(_uniswapV2Router01 != address(0), "Address can't be zero address");
    mithicalNFTContract = _mithicalNFTContract;
    dpx = _dpx;
    rdpx = _rdpx;
    weth = _weth;
    dpxWethLP = _lp;
    stakingRewards = _stakingRewards;
    uniswapV2Router01 = _uniswapV2Router01;

    // Max approve to stakingRewards
    IERC20(dpxWethLP).safeApprove(stakingRewards, type(uint256).max);

    // Max approve to uniswapV2Router01
    IERC20(dpx).safeApprove(uniswapV2Router01, type(uint256).max);
    IERC20(weth).safeApprove(uniswapV2Router01, type(uint256).max);
  }

  // Recieve function
  receive() external payable {}

  //only owner

  function adminMint(uint256 amount) external onlyOwner {
    require(!paused, "Contract is paused");
    require(!farmingPeriod, "Farming period is active");
    require(!depositPeriod, "Deposit period is active");
    IMithicalNFT(mithicalNFTContract).minterMint(msg.sender, amount);
  }

  function pause(bool _state) external onlyOwner {
    uint256 balance = IStakingRewards(stakingRewards).balanceOf(address(this));
    if (balance > 0) {
      IStakingRewards(stakingRewards).withdraw(balance);
      IStakingRewards(stakingRewards).getReward(2);
    }
    paused = _state;
  }

  function emergencyWithdraw(address[] calldata addressArray)
    external
    onlyOwner
  {
    require(paused, "Contract is not paused");
    for (uint256 i = 0; i < addressArray.length; i++) {
      IERC20(addressArray[i]).safeTransfer(
        msg.sender,
        IERC20(addressArray[i]).balanceOf(address(this))
      );
    }
    uint256 ethBalance = address(this).balance;
    if (ethBalance > 0) {
      payable(msg.sender).transfer(ethBalance);
    }
  }

  function endDeposits() external onlyOwner {
    require(!paused, "MithicalNFT is paused");
    require(!farmingPeriod, "Deposits have been closed");
    require(depositPeriod, "Deposits have been closed");
    depositPeriod = false;
    farmingPeriod = true;
    if (IERC20(dpxWethLP).balanceOf(address(this)) > 0) {
      IStakingRewards(stakingRewards).stake(
        IERC20(dpxWethLP).balanceOf(address(this))
      );
    }
    mintPrice = totalDeposits / 975;
  }

  function endFarming() external onlyOwner returns (uint256, uint256) {
    require(!paused, "MithicalNFT is paused");
    require(farmingPeriod, "Farming is not active");

    farmingPeriod = false;
    uint256 balance = IStakingRewards(stakingRewards).balanceOf(address(this));
    IStakingRewards(stakingRewards).withdraw(balance);
    IStakingRewards(stakingRewards).getReward(2);
    dpxRewards = IERC20(dpx).balanceOf(address(this));
    rdpxRewards = IERC20(rdpx).balanceOf(address(this));
    return (dpxRewards, rdpxRewards);
  }

  function claimAdminRewards(uint256 amountDpx, uint256 amountRdpx)
    external
    onlyOwner
  {
    require(!paused, "MithicalNFT is paused");
    require(!farmingPeriod, "Farming has not ended");
    require(!depositPeriod, "Deposits have not been closed");
    IERC20(dpx).safeTransfer(msg.sender, amountDpx);
    IERC20(rdpx).safeTransfer(msg.sender, amountRdpx);
  }

  // public

  function depositLP(uint256 amount) external returns (bool) {
    require(!paused, "MithicalNFT is paused");
    require(amount > 0, "amount 0");
    require(!farmingPeriod, "Deposits have been closed");
    require(depositPeriod, "Deposits have been closed");
    require(
      totalDeposits + amount <= maxLpDeposits,
      "deposit amount exceeds max LP deposits"
    );

    IERC20(dpxWethLP).safeTransferFrom(msg.sender, address(this), amount);

    IStakingRewards(stakingRewards).stake(amount);

    _deposit(amount);

    return true;
  }

  function depositWeth() external payable returns (uint256) {
    require(!paused, "MithicalNFT is paused");
    require(!farmingPeriod, "Deposits have been closed");
    require(depositPeriod, "Deposits have been closed");

    // Zap eth to DPX/WETH LP
    (uint256 remainingEth, uint256 remainingDpx, uint256 liquidityAdded) = _zap(
      weth,
      dpx,
      msg.value
    );
    require(
      totalDeposits + liquidityAdded <= maxLpDeposits,
      "deposit amount exceeds max LP deposits"
    );

    if (remainingDpx > 0) {
      IERC20(dpx).safeTransfer(msg.sender, remainingDpx);
    }
    if (remainingEth > 0) {
      payable(msg.sender).transfer(remainingEth);
    }

    IStakingRewards(stakingRewards).stake(liquidityAdded);

    _deposit(liquidityAdded);
    return (liquidityAdded);
  }

  function _deposit(uint256 amount) internal {
    usersDeposit[msg.sender] += amount;
    totalDeposits += amount;
  }

  function withdraw() external returns (bool) {
    require(!paused, "MithicalNFT is paused");
    require(!farmingPeriod, "Farming has not ended");
    require(!depositPeriod, "Deposits have not been closed");

    uint256 userDeposit = usersDeposit[msg.sender];
    usersDeposit[msg.sender] = 0;
    uint256 extraAmount = userDeposit % mintPrice;
    if (extraAmount > 0) {
      uint256 userDpxRewards = (dpxRewards * extraAmount) / totalDeposits;
      uint256 userRdpxRewards = (rdpxRewards * extraAmount) / totalDeposits;
      IERC20(dpx).safeTransfer(msg.sender, userDpxRewards);
      IERC20(rdpx).safeTransfer(msg.sender, userRdpxRewards);
    }
    IERC20(dpxWethLP).safeTransfer(msg.sender, userDeposit);
    return true;
  }

  function claimMint() external {
    require(!paused, "MithicalNFT is paused");
    require(!depositPeriod, "Deposits have not been closed");
    require(!didUserMint[msg.sender], "User has already claimed mint");

    uint256 userDeposit = usersDeposit[msg.sender];
    uint256 amount = userDeposit / mintPrice;
    if (amount > 0) {
      IMithicalNFT(mithicalNFTContract).minterMint(msg.sender, amount);
    }
    didUserMint[msg.sender] = true;
  }

  function balanceOf(address account) external view returns (uint256) {
    return usersDeposit[account];
  }

  /**
   * @notice Zaps any asset into its respective liquidity pool
   * @param _from address of token to zap from
   * @param _to address of token to zap to
   * @param _amountToZap amount of token to zap from
   */
  function _zap(
    address _from,
    address _to,
    uint256 _amountToZap
  )
    private
    returns (
      uint256 remainingWeth,
      uint256 remainingDpx,
      uint256 liquidityAdded
    )
  {
    IUniswapV2Router01 router = IUniswapV2Router01(uniswapV2Router01);

    // Amount of tokens received from swapping ETH to DPX
    uint256 tokensReceivedAfterSwap = router.swapExactETHForTokens{
      value: _amountToZap / 2
    }(0, getPath(_from, _to), address(this), block.timestamp)[1];

    // Variables to store amount of tokens that were added which is later used to calculate the remaining amounts
    uint256 tokenAAmountAdded;
    uint256 tokenBAmountAdded;

    // Add liquidity
    (tokenAAmountAdded, tokenBAmountAdded, liquidityAdded) = router
      .addLiquidityETH{ value: _amountToZap / 2 }(
      _to,
      tokensReceivedAfterSwap,
      0,
      0,
      address(this),
      block.timestamp
    );

    // Remaining WETH tokens after adding liquidity
    remainingWeth = _from == weth
      ? _amountToZap / 2 - tokenBAmountAdded
      : tokensReceivedAfterSwap - tokenAAmountAdded;

    // Remaining DPX tokens after adding liquidity
    remainingDpx = _from == dpx
      ? _amountToZap / 2 - tokenBAmountAdded
      : tokensReceivedAfterSwap - tokenAAmountAdded;
  }

  /// @notice returns path which used in router's swap
  /// @param _tokenA token to swap from
  /// @param _tokenB token to from to
  function getPath(address _tokenA, address _tokenB)
    public
    pure
    returns (address[] memory path)
  {
    path = new address[](2);
    path[0] = _tokenA;
    path[1] = _tokenB;
  }
}

