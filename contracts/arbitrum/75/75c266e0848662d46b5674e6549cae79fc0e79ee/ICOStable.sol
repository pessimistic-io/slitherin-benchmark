// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract ICOStable is Ownable, ReentrancyGuard {
    IERC20 public token;
    IERC20 public usdc;

    uint256 public constant RATE = 333333333333333333; // USD to token rate
    uint256 public constant HARD_CAP = 186000000000; // 186,000 USDC
    uint256 public constant MIN_CONTRIBUTION = 200000000; // 200 USDC
    uint256 public constant MAX_CONTRIBUTION = 2000000000; // 2,000 USDC
    uint256 public constant TOTAL_SUPPLY = 620000 * 10**18;

    address[] public investors;
    uint256 public usdcRaised;
    uint256 public tokensSold;
    bool public isFinalized;

    bool public isClaimEnabled = false;

    mapping(address => uint256) public contributions;

    event PresaleStarted();
    event TokenPurchase(address indexed purchaser, uint256 value, uint256 amount);
    event PresaleFinalized();
    event TokenClaimed(address indexed claimer, uint256 amount);

    constructor(IERC20 _token, IERC20 _usdc) {
        token = _token;
        usdc = _usdc;
    }

    function startPresale() public onlyOwner nonReentrant {
        require(token.balanceOf(address(this)) == TOTAL_SUPPLY , "Token balance incorrect");
        emit PresaleStarted();
    }

    function buyTokens(address beneficiary, uint256 usdcAmount) public nonReentrant {
        require(usdcRaised + usdcAmount <= HARD_CAP, "HARD_CAP exceeded");
        require(usdcAmount >= MIN_CONTRIBUTION, "Amount below minimum contribution");
        require(contributions[msg.sender] + usdcAmount <= MAX_CONTRIBUTION, "Contribution limit exceeded");
        require(!isFinalized, "Presale already finalized");

       uint256 tokens = (usdcAmount * RATE) / 10**12;

        require(tokensSold + tokens <= TOTAL_SUPPLY, "Not enough tokens available");

        usdc.transferFrom(msg.sender, address(this), usdcAmount);

        if (contributions[beneficiary] == 0) {
            investors.push(beneficiary);
        }
        contributions[beneficiary] += usdcAmount;

        usdcRaised += usdcAmount;
        tokensSold += tokens;

        emit TokenPurchase(beneficiary, usdcAmount, tokens);
    }

    function finalizePresale() public onlyOwner nonReentrant {
        require(!isFinalized, "Presale already finalized");
        require(usdcRaised >= MIN_CONTRIBUTION, "Not enough USDC raised");
        isFinalized = true;
        emit PresaleFinalized();
    }

    function enableClaimTokens() public onlyOwner nonReentrant {
        isClaimEnabled = true;
    }

    function claimTokens() public nonReentrant {
        require(isFinalized, "Presale not finalized yet");
        require(contributions[msg.sender] > 0, "No tokens to claim for this address");
        require(isClaimEnabled, "Token claim is not enabled yet");

        uint256 contributedUsdc = contributions[msg.sender];
     uint256 tokens = (contributedUsdc * RATE) / 10**12;
contributions[msg.sender] = 0;


        token.transfer(msg.sender, tokens);

        emit TokenClaimed(msg.sender, tokens);
    }

    function withdrawFunds() public onlyOwner nonReentrant {
        require(isFinalized, "Presale not finalized yet");
        uint256 balance = usdc.balanceOf(address(this));
        usdc.transfer(owner(), balance);
    }

    function withdrawTokens() public onlyOwner nonReentrant {
        require(isFinalized, "Presale not finalized yet");
        uint256 remainingTokens = token.balanceOf(address(this));
        token.transfer(owner(), remainingTokens);
    }
}

