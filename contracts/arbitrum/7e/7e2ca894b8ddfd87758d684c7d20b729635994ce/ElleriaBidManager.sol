pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./ISignature.sol";
import "./IElleriumTokenERC20.sol";
import "./IEllerianHero.sol";

/** 
 * Tales of Elleria
*/
contract ElleriaBidManager is Ownable, ReentrancyGuard {

  struct Bid {
      address owner;
      uint256 elmBalance;
      uint256 usdcBalance;
      uint256 elmBidPrice;
      uint256 remainingBidQuantity;
      bool isRefunded;
  }

  // X $ELM + 50 USDC. Not possible to increase unless all bids refunded and contract migrated. 
  // If USDC cost is altered (reduced to increase $ELM burn), all remaining bids will be automatically refunded.
  uint256 public usdcCostInEther = 50; 
  uint256 public bidCounter;

  address private signerAddr;
  address private safeAddr;
  address private couponAddr;
  ISignature private signatureAbi;

  IERC20 private elleriumAbi;
  IERC20 private usdcAbi;
  uint256 private usdcDecimals = 10**6;

  mapping(uint256 => Bid) private bids;

  // Mint cycles
  IEllerianHero private minterAbi;
  uint256 public auctionId = 0;
  uint256 public currentCycleMax = 200;
  uint256 public currentCycleLeft = 200;

  modifier onlyIfBidValid(uint256 _bidId) {
      require(_bidId < bidCounter);
      require(bids[_bidId].isRefunded == false);
      require(bids[_bidId].remainingBidQuantity > 0);
      _;
  }

  function SetAddresses(address _signatureAddr, address _signerAddr, address _elmAddr, address _usdcAddr, address _safeAddr, address _minterAddr) external onlyOwner {
    signerAddr = _signerAddr;
    safeAddr = _safeAddr;

    signatureAbi = ISignature(_signatureAddr);
    elleriumAbi = IERC20(_elmAddr);
    usdcAbi = IERC20(_usdcAddr);
    minterAbi = IEllerianHero(_minterAddr);
      }

  function SetCouponAddress(address _couponAddr) external onlyOwner {
    couponAddr = _couponAddr;
  }

  function ResetAuctionCycle(uint256 _max, uint256 _auctionId) external onlyOwner {
    currentCycleMax = _max;
    currentCycleLeft = currentCycleMax;
    auctionId = _auctionId;

    emit CycleReset(auctionId, currentCycleMax);
  }

  function ReduceUsdcCost(uint256 _usdcCostInEther) external onlyOwner {
    require (_usdcCostInEther < usdcCostInEther, "BidManager: can only reduce USDC cost");

    uint256 difference = usdcCostInEther - _usdcCostInEther;
    usdcCostInEther = _usdcCostInEther;

    // Might fail if too many bids, migrate instead.
    for (uint256 i = 0; i < bidCounter; i += 1) {
      if (bids[i].remainingBidQuantity > 0) {
        uint256 refundAmount = (difference * bids[i].remainingBidQuantity * usdcDecimals);
        bids[i].usdcBalance = bids[i].usdcBalance - refundAmount;
        usdcAbi.transfer(bids[i].owner, refundAmount);
        emit BidUpdated(bids[i].owner, bids[i].elmBalance, bids[i].usdcBalance, bids[i].remainingBidQuantity, i);
      }
    }
  }

  function OwnerRefundAllBid() external onlyOwner {
    for (uint256 i = 0; i < bidCounter; i += 1) {
      if (bids[i].isRefunded == false && bids[i].remainingBidQuantity > 0) {
      refundBid(i);
      }
    }
  }

  function OwnerRefundBid(uint256 _bidId) external onlyOwner onlyIfBidValid(_bidId) {
    refundBid(_bidId);
  }

  function ConsumeBid(uint256 _bidId, uint256 quantity, uint256 _variant) external onlyOwner onlyIfBidValid(_bidId) {
    require(quantity < currentCycleLeft, "BidManager: not enough heroes left");
    currentCycleLeft -= quantity;

    uint256 elmPrice = bids[_bidId].elmBidPrice * quantity;
    uint256 usdcPrice = usdcCostInEther * quantity * usdcDecimals;

    require(quantity <= bids[_bidId].remainingBidQuantity, "BidManager: quantity exceed");
    require(elmPrice <= bids[_bidId].elmBalance, "BidManager: insufficient elm");
    require(usdcPrice <= bids[_bidId].usdcBalance, "BidManager: insufficient usdc");

    emit BidConsumed(bids[_bidId].owner, elmPrice, usdcPrice, quantity, _bidId, auctionId);

    elleriumAbi.transfer(safeAddr, elmPrice);
    usdcAbi.transfer(safeAddr, usdcPrice);

    bids[_bidId].elmBalance = bids[_bidId].elmBalance - elmPrice;
    bids[_bidId].usdcBalance = bids[_bidId].usdcBalance - usdcPrice;
    bids[_bidId].remainingBidQuantity = bids[_bidId].remainingBidQuantity - quantity;

    minterAbi.mintUsingToken(bids[_bidId].owner, quantity, _variant);
  }

  function RedeemUsingCoupon(address _recipient, uint256 _quantity, uint256 _variant) external {
    require(msg.sender == couponAddr, "BidManager: not allowed");

    minterAbi.mintUsingToken(_recipient, _quantity, _variant);
    emit CouponRedeemed(_recipient, _quantity);
  }

  function GetBid(uint256 _bidId) external view returns (Bid memory) {
    return bids[_bidId];
  }

  function CreateBid(uint256 _elmAmountInWEI, uint256 quantity) external nonReentrant {
    require(quantity > 0, "BidManager: Invalid quantity");

    elleriumAbi.transferFrom(msg.sender, address(this), _elmAmountInWEI * quantity);
    usdcAbi.transferFrom(msg.sender, address(this), usdcCostInEther * quantity * usdcDecimals);

    bids[bidCounter] = Bid(
      msg.sender,
      _elmAmountInWEI * quantity,
      usdcCostInEther * quantity * usdcDecimals,
      _elmAmountInWEI,
      quantity,
      false
    );

    emit BidUpdated(
      msg.sender,
      _elmAmountInWEI * quantity,
      usdcCostInEther * quantity * usdcDecimals,
      quantity,
      bidCounter++
    );
  }

 function SupplementBid(uint256 _bidId, uint256 _newElmBidPrice) external nonReentrant onlyIfBidValid(_bidId) {
    require(bids[_bidId].owner == msg.sender, "BidManager: you are not owner");
    require(bids[_bidId].elmBidPrice < _newElmBidPrice, "BidManager: bids can only be raised");

    uint256 valueDifference = (_newElmBidPrice - bids[_bidId].elmBidPrice) * bids[_bidId].remainingBidQuantity;
    elleriumAbi.transferFrom(msg.sender, address(this), valueDifference);
  
    bids[_bidId].elmBalance = bids[_bidId].elmBalance + valueDifference;
    bids[_bidId].elmBidPrice = _newElmBidPrice;

    emit BidUpdated(
      msg.sender, 
      bids[_bidId].elmBalance, 
      bids[_bidId].usdcBalance, 
      bids[_bidId].remainingBidQuantity, 
      _bidId
      );
  }

  function RefundBid(bytes memory _signature, uint256 _time, uint256 _bidId) external nonReentrant onlyIfBidValid(_bidId) {
    require(msg.sender == bids[_bidId].owner, "BidManager: cannot refund for others");
    require((block.timestamp - _time < 600), "BidManager: signature expired");
    require(
      signatureAbi.verify(signerAddr, msg.sender, _time, "cancel bid", _bidId, _signature),
      "BidManager: invalid signature"
    );

    refundBid(_bidId);
  }

  function refundBid(uint256 _bidId) internal {
    emit BidCancelled(bids[_bidId].owner, bids[_bidId].elmBalance, bids[_bidId].usdcBalance, bids[_bidId].remainingBidQuantity, _bidId);
  
    elleriumAbi.transfer(bids[_bidId].owner, bids[_bidId].elmBalance);
    usdcAbi.transfer(bids[_bidId].owner, bids[_bidId].usdcBalance);
    
    bids[_bidId].elmBalance = 0;
    bids[_bidId].usdcBalance = 0;
    bids[_bidId].isRefunded = true;
    bids[_bidId].remainingBidQuantity = 0;
  }

  // Events
  event BidUpdated(address indexed owner, uint256 elmValue, uint256 usdcValue, uint256 quantity, uint256 bidId);
  event BidCancelled(address indexed owner, uint256 elmValue, uint256 usdcValue, uint256 quantity, uint256 bidId);
  event BidConsumed(address indexed owner, uint256 elmValue, uint256 usdcValue, uint256 quantity, uint256 bidId, uint256 auctionId);
  event CycleReset(uint256 auctionId, uint256 quantity);
  event CouponRedeemed(address indexed recipient, uint256 quantity);
}

