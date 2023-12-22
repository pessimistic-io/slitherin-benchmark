//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./IERC20.sol";

import "./console.sol";

interface ExchangeRateOracle { // Chainlink compatible
  function latestRoundData()
    external
    view
    returns (
      uint80, // roundId,
      int256, // answer,
      uint256, // startedAt,
      uint256, // updatedAt,
      uint80 // answeredInRound
    );
}

contract InstantSwap {
  uint256 public constant PRICE_FEED_FRESHNESS = 24*60*60; // 24h after which price feed is considered stale
  uint256 constant PERC_BASE = 10000; // == 100.00%
  uint256 public fee = 15; // 0.15%
  // tier 2 used if less than feeTier2Limit would be left in the pool after the swap
  uint256 public feeTier2Limit = 100_000 * 1e6; // 100k DUSD
  uint256 public feeTier2 = 120; // 1.2%
  // tier 3 used if less than feeTier3Limit would be left in the pool after the swap
  uint256 public feeTier3Limit = 50_000 * 1e6; // 50k DUSD
  uint256 public feeTier3 = 240; // 2.4%

  IERC20 public immutable DUSD;

  ExchangeRateOracle public priceOracle;

  bool public paused;

  address public owner;
  modifier onlyOwner() {
    require(owner == msg.sender, "unauthorized");
    _;
  }

  event Swap(bool DUSDin, uint256 amountIn, uint256 amountOut, address indexed account);
  event FeeUpdated(uint8 tier, uint256 newFee);
  event FeeTierLimitUpdated(uint8 tier, uint256 newLimit);
  event Paused();
  event Unpaused();
  event OwnershipTransferred(address indexed newOwner);
  event WithdrawnDUSD(address recipient, uint256 _amount);
  event WithdrawnETH(address recipient, uint256 _amount);
    
  constructor(address _dusd, address _priceOracle) {
    owner = msg.sender;

    DUSD = IERC20(_dusd);
    priceOracle = ExchangeRateOracle(_priceOracle);
  }

  //
  //
  /* ========== Swapping ========== */
  //
  //

  function swapDUSD2ETH(uint256 _amountDUSDin, uint256 _minETHout) public whenNotPaused {
    uint256 amountETHout = calculateAmountETHout(_amountDUSDin);
    require(address(this).balance >= amountETHout, "insufficient liquidity");

    amountETHout -= amountETHout * getFee(true, _amountDUSDin) / PERC_BASE;
    require(amountETHout >= _minETHout, "less than min amount out");
    
    DUSD.transferFrom(msg.sender, address(this), _amountDUSDin);
    
    (bool sent,) = msg.sender.call{ value: amountETHout }("");
    require(sent, "failed to send ETH");
    
    emit Swap(true, _amountDUSDin, amountETHout, msg.sender);
  }

  function swapETH2DUSD(uint _minDUSDout) external payable whenNotPaused {
    uint256 amountDUSDout = calculateAmountDUSDout(msg.value);
    require(DUSD.balanceOf(address(this)) >= amountDUSDout, "insufficient liquidity");

    amountDUSDout -= amountDUSDout * getFee(false, msg.value) / PERC_BASE;
    require(amountDUSDout >= _minDUSDout, "less than min amount out");
    
    DUSD.transfer(msg.sender, amountDUSDout);
    
    emit Swap(false, msg.value, amountDUSDout, msg.sender);
  }

  function getExchangeRate() public view returns (uint256) {
    (
      /*uint80 roundID*/,
      int price,
      /*uint startedAt*/,
      uint timestamp,
      /*uint80 answeredInRound*/
    ) = priceOracle.latestRoundData();
    require(price > 0, "invalid price");
    require(timestamp > block.timestamp-PRICE_FEED_FRESHNESS, "price feed stale"); 
    return uint256(price);
  }

  function calculateAmountETHout(uint256 _amountDUSDin) public view returns (uint256) {
    // DUSD = 6 decimals, exchange rate = 8, eth = 18.
    // so we need to end up with 18 decimals, 18 - (6 - 8) = 18 -- 2 = 20 decimals to add
    return _amountDUSDin * 1e20 / getExchangeRate();
  }

  function calculateAmountDUSDout(uint256 _amountETHin) public view returns (uint256) {
    // eth = 18 decimals, exchange rate = 8, DUSD = 6.
    // so we need to end up with 6 decimals, 18 + 8 - 6 = 20 decimals to remove
    return _amountETHin * getExchangeRate() / 1e20;
  }

  function getFee(bool _dusdIn, uint256 _amountIn) public view returns (uint256) {
    if(_dusdIn) { // DUSD2ETH
      uint256 amountOut = calculateAmountETHout(_amountIn);
      uint256 amountAvailable = getETHBalance();
      uint256 amountAfterSwap = 0;
      if(amountAvailable > amountOut) {
        amountAfterSwap = amountAvailable - amountOut; // we ignore the fee here
      }

      // Tier 3 check
      uint256 tier3LimitInEth = feeTier3Limit * 1e20 / getExchangeRate();
      if(amountAfterSwap < tier3LimitInEth) {
        return feeTier3;
      }

      // Tier 2 check
      uint256 tier2LimitInEth = feeTier2Limit * 1e20 / getExchangeRate();
      if(amountAfterSwap < tier2LimitInEth) {
        return feeTier2;
      }
    }
    else { // ETH2DUSD
      uint256 amountOut = calculateAmountDUSDout(_amountIn);
      uint256 amountAvailable = getDUSDBalance();
      uint256 amountAfterSwap = 0;
      if(amountAvailable > amountOut) {
        amountAfterSwap = amountAvailable - amountOut; // we ignore the fee here
      }
      
      // Tier 3 check
      if(amountAfterSwap < feeTier3Limit) {
        return feeTier3;
      }
      
      // Tier 2 check
      if(amountAfterSwap < feeTier2Limit) {
        return feeTier2;
      }
    }
    // default base fee
    return fee;
  }

  //
  //
  /* ========== ADMIN functions ========== */
  //
  //

  function updateFee(uint8 _tier, uint256 _newFee) public onlyOwner { 
    require(_tier == 1 || _tier == 2 || _tier == 3, "invalid fee tier");
    require(_newFee <= PERC_BASE, "new fee exceeds 100%");
    if(_tier == 1) {
      require(_newFee < feeTier2, "invalid base fee");
      fee = _newFee;
    }
    if(_tier == 2) {
      require(_newFee > fee && _newFee < feeTier3, "invalid tier 2 fee");
      feeTier2 = _newFee;
    }
    if(_tier == 3) {
      require(_newFee > feeTier2, "invalid tier 3 fee");
      feeTier3 = _newFee;
    }
    emit FeeUpdated(_tier, _newFee);
  }

  function updateFeeTierLimit(uint8 _tier, uint256 _newLimit) public onlyOwner {
    require(_tier == 2 || _tier == 3, "invalid fee tier");
    if(_tier == 2) {
      require(_newLimit > feeTier3Limit, "tier 2 limit must be more than tier 3 limit");
      feeTier2Limit = _newLimit;
      emit FeeTierLimitUpdated(_tier, _newLimit);
      return;
    }
    if(_tier == 3) {
      require(_newLimit < feeTier2Limit, "tier 3 limit must be less than tier 2 limit");
      feeTier3Limit = _newLimit;
      emit FeeTierLimitUpdated(_tier, _newLimit);
      return;
    }
  }

  function transferOwnership(address _newOwner) public onlyOwner {
    require(_newOwner != owner, "new owner equals current owner");
    owner = _newOwner;
    emit OwnershipTransferred(_newOwner);
  }

  function withdrawETH(uint256 _amount) public onlyOwner {
    if(_amount == 0) {
      _amount = address(this).balance;
    }
    (bool sent,) = owner.call{ value: _amount }("");
    require(sent, "failed to send ETH");
    emit WithdrawnETH(owner, _amount);
  }
  
  function withdrawDUSD(uint256 _amount) public onlyOwner {
    if(_amount == 0) {
      _amount = DUSD.balanceOf(address(this));
    }
    DUSD.transfer(owner, _amount);
    emit WithdrawnDUSD(owner, _amount);
  }

  //
  //
  /* ========== Pausing ========== */
  //
  //
  
  modifier whenNotPaused() {
    require(!paused, "paused");
    _;
  }

  modifier whenPaused() {
    require(paused, "not paused");
    _;
  }

  function pause() external whenNotPaused onlyOwner {
    paused = true;
    emit Paused();
  }

  function unpause() external whenPaused onlyOwner {
    paused = false;
    emit Unpaused();
  }

  function getETHBalance() public view returns (uint256) {
    return address(this).balance;
  }

  function getDUSDBalance() public view returns (uint256) {
    return DUSD.balanceOf(address(this));
  }

  receive() external payable {
  }
}

