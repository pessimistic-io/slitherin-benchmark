// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

contract IDO is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public unipToken;
    IERC20 public USDCtoken;

    bool public isInitialized;
    uint256 public rate = 10;
    uint256 public claimInterval;

    uint256 public startTime;
    uint256 public endTime;

    uint256 public minContribution;
    uint256 public maxContribution;

    uint256 public totalContributed;
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public purchasedAmounts;
    mapping(address => uint256) public lastPurchasedTime;

    // user address => claimed token amount
    mapping(address => uint256) public claimedAmounts;
    mapping(address => uint256) public lastClaimedTime;

    event IDOStarted(uint256 startTime, uint256 endTime);
    event TokensPurchased(address buyer, uint256 usdcAmount, uint256 unipAmount);

    constructor() {
    }

    function initialize(
        address _unipToken,
        address _usdcToken,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _minContribution,
        uint256 _maxContribution
    ) external onlyOwner {
        require(!isInitialized, "already initialized");
        isInitialized = true;

        unipToken = IERC20(_unipToken);
        USDCtoken = IERC20(_usdcToken);
        startTime = _startTime;
        endTime = _endTime;
        minContribution = _minContribution;
        maxContribution = _maxContribution;
        emit IDOStarted(_startTime, _endTime);
    }

    function setStartTime(uint256 t) external onlyOwner {
        startTime = t;
    }

    function setEndTime(uint256 t) external onlyOwner {
        endTime = t;
    }

    function setMinContribution(uint256 t) external onlyOwner{
        minContribution = t;
    }

    function setMaxContribution(uint256 t) external onlyOwner{
        maxContribution = t;
    }    

    function setRate(uint256 t) external onlyOwner{
        require(t < 1000, "rate must lt 1000");
        rate = t;
    }

    function setUSDC(address _token) external onlyOwner{
        USDCtoken = IERC20(_token);
    }

    function setClaimInterval(uint256 t) external onlyOwner{
        claimInterval = t;
    }

    function blockTimestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function checkIdoProgress() public view returns (uint256) {
        uint256 idoState = 1;
        if (startTime > block.timestamp) {
            idoState = 1;   //not start yet
        } else if (block.timestamp >= startTime && block.timestamp < endTime) {
            idoState = 2;   //ido running
        } else if (block.timestamp >= endTime) {
            idoState = 3;   //ido ended
        }

        return idoState;
    }

    function buyTokens(uint256 usdcAmount) external nonReentrant {
        require(block.timestamp >= startTime && block.timestamp < endTime, "IDO time not match");
        require(usdcAmount >= minContribution && usdcAmount <= maxContribution, "Contribution too small or too large");
        require(contributions[msg.sender] + usdcAmount <= maxContribution, "gt maxContribution");

        USDCtoken.safeTransferFrom(msg.sender, address(this), usdcAmount);

        contributions[msg.sender] += usdcAmount;
        totalContributed += usdcAmount;

        uint256 tokenAmount = calculateTokenAmount(usdcAmount);
        purchasedAmounts[msg.sender] += tokenAmount;
        lastPurchasedTime[msg.sender] = block.timestamp;

        emit TokensPurchased(msg.sender, usdcAmount, tokenAmount);
    }

    function calculateTokenAmount(uint256 usdcAmount) public view returns (uint256) {
        return usdcAmount.div(10**6).mul(10**18).mul(rate);
    }

    function remainTokens() public view returns (uint256) {
        if (claimedAmounts[msg.sender] >= purchasedAmounts[msg.sender]) {
            return 0;
        }

        uint256 remain = purchasedAmounts[msg.sender] - claimedAmounts[msg.sender];
        return remain;
    }

    function claimTokens() external nonReentrant {
        require(endTime <= block.timestamp, "IDO sale not finish yet");
        require(purchasedAmounts[msg.sender] > 0, "no token to claim");
        require(purchasedAmounts[msg.sender] > claimedAmounts[msg.sender], "all token already claimed");

        if (claimedAmounts[msg.sender] != 0) {
            uint256 timeSinceLastClaim = block.timestamp - lastClaimedTime[msg.sender];
            if(claimInterval > 0){
                require(timeSinceLastClaim >= claimInterval, "it's not the time to claim");
            } else {
                require(timeSinceLastClaim >= 7 days, "it's not the time to claim");
            }
        }

        uint256 shareToClaimEveryTime = purchasedAmounts[msg.sender].div(30);

        uint256 tokensToClaim = shareToClaimEveryTime;
        if (claimedAmounts[msg.sender] + shareToClaimEveryTime < purchasedAmounts[msg.sender]
         && claimedAmounts[msg.sender] + shareToClaimEveryTime.mul(2) > purchasedAmounts[msg.sender]) {
            tokensToClaim = purchasedAmounts[msg.sender].sub(claimedAmounts[msg.sender]);
        }
        require(claimedAmounts[msg.sender] + tokensToClaim <= purchasedAmounts[msg.sender], "purchasedAmounts < claimedAmounts");

        lastClaimedTime[msg.sender] = block.timestamp;
        claimedAmounts[msg.sender] = claimedAmounts[msg.sender].add(tokensToClaim);

        unipToken.safeTransfer(msg.sender, tokensToClaim);
    }

    function withdrawUsdcTokens() external nonReentrant onlyOwner {
        require(block.timestamp >= endTime, "IDO not end");
        uint256 balance = USDCtoken.balanceOf(address(this));
        USDCtoken.safeTransfer(msg.sender, balance);
    }

    function withdrawTokens() external nonReentrant onlyOwner {
        require(block.timestamp >= endTime, "IDO not end");
        uint256 balance = unipToken.balanceOf(address(this));
        unipToken.safeTransfer(msg.sender, balance);
    }
}

