// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

// Contracts
import "./Ownable.sol";
import { SafeERC20 } from "./SafeERC20.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IStakingRewards } from "./IStakingRewards.sol";
import { IUniswapV2Router01 } from "./IUniswapV2Router01.sol";

contract YieldMint is Ownable {
  using SafeERC20 for IERC20;

  address public NFTContract;
  address public dpx;
  address public rdpx;
  address public weth;
  address public LP;
  address public stakingRewards;
  address public uniswapV2Router01;
  uint256 public maxSupply;
  uint256 public maxLpDeposits;
  uint256 public NFTsForSale;
  bool public paused = false;
  bool public depositPeriod = false;
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

  /*==== ERRORS & EVENTS ====*/

  event DepositLP(address user, uint256 amountLP);
  event DepositEth(address user, uint256 amountEth);
  event Withdraw(address user, uint256 amount);
  event endDepositPeriod(uint256 blockTimeStamp);
  event endFarmingPeriod(uint256 blockTimeStamp);
  event Mint(address user, uint256 amount);

  constructor(
    address _NFTContract,
    address _dpx,
    address _rdpx,
    address _weth,
    address _lp,
    address _stakingRewards,
    address _uniswapV2Router01,
    uint256 _maxSupply,
    uint256 _maxLpDeposits,
    uint256 _NFTsForSale
  ) {
    require(_NFTContract != address(0), "Address can't be zero address");
    require(_dpx != address(0), "Address can't be zero address");
    require(_rdpx != address(0), "Address can't be zero address");
    require(_weth != address(0), "Address can't be zero address");
    require(_lp != address(0), "Address can't be zero address");
    require(_stakingRewards != address(0), "Address can't be zero address");
    require(_uniswapV2Router01 != address(0), "Address can't be zero address");
    require(_maxSupply != 0, "Max supply can't be zero");
    require(_maxLpDeposits != 0, "Max Lp deposits can't be zero");
    require(_NFTsForSale != 0, "NFTs for sale can't be zero");
    NFTContract = _NFTContract;
    dpx = _dpx;
    rdpx = _rdpx;
    weth = _weth;
    LP = _lp;
    stakingRewards = _stakingRewards;
    uniswapV2Router01 = _uniswapV2Router01;
    maxSupply = _maxSupply;
    maxLpDeposits = _maxLpDeposits;
    NFTsForSale = _NFTsForSale;

    // Max approve to stakingRewards
    IERC20(LP).safeApprove(stakingRewards, type(uint256).max);

    // Max approve to uniswapV2Router01
    IERC20(rdpx).safeApprove(uniswapV2Router01, type(uint256).max);
    IERC20(weth).safeApprove(uniswapV2Router01, type(uint256).max);
  }

  // Recieve function
  receive() external payable {}

  //only owner

  /// @notice admin can mint NFTs
  /// @dev Can only be called by governance
  function adminMint(uint256 amount) external onlyOwner {
    require(!paused, "Contract is paused");
    for (uint256 i = 0; i < amount; i++) {
      // Mint NFT
      IERC721(NFTContract).mint(msg.sender);
    }
  }

  /// @notice admin can set max LP deposit
  /// @dev Can only be called by governance
  function setMaxLpDeposit(uint256 amount) external onlyOwner {
    require(!paused, "Contract is paused");
    maxLpDeposits = amount;
  }

  /// @notice admin can pause/unpause the contract
  /// @param _state boolean to pause or unpause the contract
  /// @dev Can only be called by governance
  function pause(bool _state) external onlyOwner {
    uint256 balance = IStakingRewards(stakingRewards).balanceOf(address(this));
    if (balance > 0) {
      IStakingRewards(stakingRewards).withdraw(balance);
      IStakingRewards(stakingRewards).getReward(2);
    }
    paused = _state;
  }

  /// @notice emergency withdraw all
  /// @dev Can only be called by governance
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

  function startDeposits() external onlyOwner {
    require(!depositPeriod, "Deposit period is already started");
    require(!paused, "Contract is paused");
    depositPeriod = true;
  }

  /// @notice ends deposit period
  /// @dev Can only be called by governance
  function endDeposits() external onlyOwner {
    require(!paused, "Contract is paused");
    require(!farmingPeriod, "Deposits have been closed");
    require(depositPeriod, "Deposits have been closed");
    depositPeriod = false;
    farmingPeriod = true;
    if (IERC20(LP).balanceOf(address(this)) > 0) {
      IStakingRewards(stakingRewards).stake(
        IERC20(LP).balanceOf(address(this))
      );
    }

    mintPrice = totalDeposits / NFTsForSale;

    emit endDepositPeriod(block.timestamp);
  }

  /// @notice ends farming period
  /// @dev Can only be called by governance
  function endFarming() external onlyOwner returns (uint256, uint256) {
    require(!paused, "Contract is paused");
    require(farmingPeriod, "Farming is not active");

    farmingPeriod = false;
    uint256 balance = IStakingRewards(stakingRewards).balanceOf(address(this));
    IStakingRewards(stakingRewards).withdraw(balance);
    IStakingRewards(stakingRewards).getReward(2);
    dpxRewards = IERC20(dpx).balanceOf(address(this));
    rdpxRewards = IERC20(rdpx).balanceOf(address(this));

    emit endFarmingPeriod(block.timestamp);
    return (dpxRewards, rdpxRewards);
  }

  /// @notice admin claims rewards
  /// @param amountDpx amount of DPX rewards to claim
  /// @param amountRdpx amount of RDPX rewards to claim
  /// @dev Can only be called by governance
  function claimAdminRewards(uint256 amountDpx, uint256 amountRdpx)
    external
    onlyOwner
  {
    require(!paused, "Contract is paused");
    require(!farmingPeriod, "Farming has not ended");
    require(!depositPeriod, "Deposits have not been closed");
    IERC20(dpx).safeTransfer(msg.sender, amountDpx);
    IERC20(rdpx).safeTransfer(msg.sender, amountRdpx);
  }

  // public

  /// @notice user deposits LP
  /// @param amount amount of LP deposited
  /// @param userAddress address of user
  function depositLP(uint256 amount, address userAddress)
    external
    returns (bool)
  {
    require(!paused, "Contract is paused");
    require(amount > 0, "amount 0");
    require(!farmingPeriod, "Deposits have been closed");
    require(depositPeriod, "Deposits have been closed");
    require(
      totalDeposits + amount <= maxLpDeposits,
      "deposit amount exceeds max LP deposits"
    );
    IERC20(LP).safeTransferFrom(msg.sender, address(this), amount);

    IStakingRewards(stakingRewards).stake(amount);

    _deposit(amount, userAddress);

    emit DepositLP(userAddress, amount);

    return true;
  }

  /// @notice user Deposits ETH
  /// @param userAddress address of user
  function depositWeth(address userAddress) external payable returns (uint256) {
    require(!paused, "Contract is paused");
    require(!farmingPeriod, "Deposits have been closed");
    require(depositPeriod, "Deposits have been closed");

    // Zap eth to DPX/WETH LP
    (
      uint256 remainingEth,
      uint256 remainingRdpx,
      uint256 liquidityAdded
    ) = _zap(weth, rdpx, msg.value);
    require(
      totalDeposits + liquidityAdded <= maxLpDeposits,
      "deposit amount exceeds max LP deposits"
    );

    if (remainingRdpx > 0) {
      IERC20(rdpx).safeTransfer(msg.sender, remainingRdpx);
    }
    if (remainingEth > 0) {
      payable(msg.sender).transfer(remainingEth);
    }

    IStakingRewards(stakingRewards).stake(liquidityAdded);

    _deposit(liquidityAdded, userAddress);

    emit DepositEth(userAddress, liquidityAdded);
    return (liquidityAdded);
  }

  function _deposit(uint256 amount, address userAddress) internal {
    usersDeposit[userAddress] += amount;
    totalDeposits += amount;
  }

  /// @notice user withdraws their LP tokens
  function withdraw() external returns (bool) {
    require(!paused, "Contract is paused");
    require(!farmingPeriod, "Farming has not ended");
    require(!depositPeriod, "Deposits have not been closed");
    require(usersDeposit[msg.sender] > 0, "no deposits");

    uint256 userDeposit = usersDeposit[msg.sender];
    usersDeposit[msg.sender] = 0;
    uint256 extraAmount = userDeposit % mintPrice;
    if (extraAmount > 0) {
      uint256 userDpxRewards = (dpxRewards * extraAmount) / totalDeposits;
      uint256 userRdpxRewards = (rdpxRewards * extraAmount) / totalDeposits;
      IERC20(dpx).safeTransfer(msg.sender, userDpxRewards);
      IERC20(rdpx).safeTransfer(msg.sender, userRdpxRewards);
    }
    IERC20(LP).safeTransfer(msg.sender, userDeposit);

    emit Withdraw(msg.sender, userDeposit);
    return true;
  }

  /// @notice user mints NFT's
  function claimMint() external {
    require(!paused, "Contract is paused");
    require(!depositPeriod, "Deposits have not been closed");
    require(!didUserMint[msg.sender], "User has already claimed mint");
    require(
      usersDeposit[msg.sender] >= mintPrice && usersDeposit[msg.sender] > 0,
      "User has not deposited enough LP"
    );

    uint256 userDeposit = usersDeposit[msg.sender];
    uint256 amount = userDeposit / mintPrice;
    require(
      amount + IERC721(NFTContract).totalSupply() < maxSupply,
      "mint limit reached"
    );

    if (amount > 0) {
      for (uint256 i = 0; i < amount; i++) {
        // Mint NFT
        IERC721(NFTContract).mint(msg.sender);
      }
    }
    didUserMint[msg.sender] = true;

    emit Mint(msg.sender, amount);
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
      uint256 remainingRdpx,
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
    remainingRdpx = _from == rdpx
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

