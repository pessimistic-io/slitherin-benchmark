// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20.sol";
import "./SafeERC20.sol";

contract Crowdsale {
  using SafeERC20 for IERC20;
  /**
   * Event for token purchase/claim logging
   * @param purchaser who paid for the tokens
   * @param amount amount of USDC deposited
   */
  event TokensPurchased(address indexed purchaser, uint256 amount);
  event TokensClaimed(address indexed purchaser, uint256 amount);
  
  
  IERC20 public token;
  uint public crowdsaleTokenCap;
  uint public tokensPerUSDC;
  uint public startDate;
  uint public endDate;
  address public owner;  
  bool public isPaused;
  
  mapping(address => uint) public contributions;
  mapping(address => bool) public hasClaimed;

  uint public totalContributions;
  // hard cap: $1.5m
  uint public constant hardcap = 1_500_000e6; 

  // Arbitrum bridged USDC
  IERC20 constant USDCe = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

  modifier onlyOwner {
    require(msg.sender == owner, "Not Owner");
    _;
  }


  constructor(
    address _token,
    uint _startDate,
    uint _endDate
  ){
    require(_token != address(0), "Invalid token");
    // crowdsale cannot last more than 1 month
    require(_startDate > block.timestamp && _endDate < _startDate + 2592000, "Invalid dates");
    token = IERC20(_token);
    startDate = _startDate;
    endDate = _endDate;
    owner = msg.sender;
    isPaused = true;
  }
  
  /////////// ADMIN FUNCTIONS
  
  /// @notice Deposit tokens to be sold in crowdsale
  /// @notice tokenAmount Additional amount of tokens sold
  /// @dev Wouldnt work with low decimals tokens but our token has 18 decimals
  function initSale(uint tokenAmount) public onlyOwner {
    require(block.timestamp < endDate, "Sale already ended");
    token.safeTransferFrom(msg.sender, address(this), tokenAmount);
    crowdsaleTokenCap = token.balanceOf(address(this));
    tokensPerUSDC = crowdsaleTokenCap / hardcap;
    isPaused = false;
  }
  
  /// @notice Pause sale
  function pauseSale(bool _isPaused) public onlyOwner {
    isPaused = _isPaused;
  }
  
  /// @notice Owner can withdraw all funds after the crowdsale has ended
  function withdrawFunds() public onlyOwner  {
    require(block.timestamp > endDate, "TGE ongoing");
    USDCe.safeTransfer(owner, USDCe.balanceOf(address(this)));
    uint amountBought = tokensPerUSDC * totalContributions;
    // return unsold tokens to admin for burn
    if (amountBought < crowdsaleTokenCap) token.safeTransfer(msg.sender, crowdsaleTokenCap - amountBought);
  }
  
  
  
  /////////// USER FUNCTIONS
  
  /// @notice Buy crowdsale token with USDC
  /// @param amount USDC deposited
  /// @return tokenAmount amount of tokens bought
  function deposit(uint amount) public returns (uint tokenAmount){
    require(!isPaused, "TGE paused");
    require(startDate < block.timestamp, "TGE hasnt started");
    require(block.timestamp <= endDate, "TGE has ended");
    require(totalContributions + amount <= hardcap, "Hardcap reached");
    USDCe.safeTransferFrom(msg.sender, address(this), amount);
    contributions[msg.sender] += amount;
    totalContributions += amount;
    tokenAmount = amount * tokensPerUSDC;
    emit TokensPurchased(msg.sender, amount);
  }


  /// @notice Claim bought tokens after crowdsale ended
  /// @return tokenAmount Amount of tokens bought
  function claim() public returns (uint tokenAmount) {
    require(block.timestamp > endDate, "TGE hasnt ended");
    require(!hasClaimed[msg.sender], "Already Claimed");
    hasClaimed[msg.sender] = true;
    tokenAmount = contributions[msg.sender] * tokensPerUSDC;
    token.safeTransfer(msg.sender, tokenAmount);
    emit TokensClaimed(msg.sender, tokenAmount);
  }
  
  
  /// @notice Claimable amount
  /// @param user Claiming user
  /// @return tokens amount claimable
  function claimable(address user) public view returns (uint) {
    if (hasClaimed[user] || block.timestamp <= endDate) return 0;
    else return contributions[user] * tokensPerUSDC;
  }
}
