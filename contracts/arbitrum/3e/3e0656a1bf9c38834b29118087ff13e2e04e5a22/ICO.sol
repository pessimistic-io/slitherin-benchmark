// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract ICO is Ownable, ReentrancyGuard {
    IERC20 public token;
    uint256 public constant RATE = 10000;
    uint256 public constant HARD_CAP = 50 ether;
    uint256 public constant MIN_CONTRIBUTION = 0.00001 ether;
    uint256 public constant MAX_CONTRIBUTION = 1 ether;
    uint256 public constant TOTAL_SUPPLY = 620000 * 10**18;

    address[] public investors;
    uint256 public weiRaised;
    uint256 public tokensSold;
    bool public isFinalized;

    bool public isClaimEnabled = false;

    uint256 public startTime = 0;

    mapping(address => uint256) public contributions;

    event PresaleStarted(uint256 startTime);
    event TokenPurchase(address indexed purchaser, uint256 value, uint256 amount);
    event PresaleFinalized();
    event TokenClaimed(address indexed claimer, uint256 amount);

    constructor(IERC20 _token) {
        token = _token;
    }

    receive() external payable {
    buyTokens(msg.sender);
}


    function startPresale() public onlyOwner nonReentrant {
        require(startTime == 0, "Presale already started");
        require(token.balanceOf(address(this)) == TOTAL_SUPPLY , "Token balance incorrect");
        startTime = block.timestamp;
        emit PresaleStarted(startTime);
    }

    function buyTokens(address beneficiary) public payable nonReentrant {
        uint256 weiAmount = msg.value;
        require(startTime > 0 && block.timestamp >= startTime, "Presale not started yet");
        require(!isFinalized, "Presale already finalized");
        require(weiAmount >= MIN_CONTRIBUTION, "Amount below minimum contribution");
        require(contributions[msg.sender] + weiAmount <= MAX_CONTRIBUTION, "Contribution limit exceeded");
        require(weiRaised + weiAmount <= HARD_CAP, "HARD_CAP exceeded");

        uint256 tokens = weiAmount * RATE;

        uint256 newTokensSold = tokensSold + tokens;
        require(newTokensSold <= TOTAL_SUPPLY, "Not enough tokens available");

        if (contributions[beneficiary] == 0) {
            investors.push(beneficiary);
        }
        contributions[beneficiary] += weiAmount;

        weiRaised += weiAmount;
        tokensSold = newTokensSold;

        emit TokenPurchase(beneficiary, weiAmount, tokens);
    }

    function finalizePresale() public onlyOwner nonReentrant {
        require(!isFinalized, "Presale already finalized");
        require(weiRaised >= MIN_CONTRIBUTION, "Not enough wei raised");
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

        uint256 contributedWei = contributions[msg.sender];
        uint256 tokens = contributedWei * RATE;
        contributions[msg.sender] = 0;

        token.transfer(msg.sender, tokens);

        emit TokenClaimed(msg.sender, tokens);
    }

    function withdrawFunds() public onlyOwner nonReentrant {
        require(isFinalized, "Presale not finalized yet");
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawTokens() public onlyOwner nonReentrant {
        require(isFinalized, "Presale not finalized yet");
        token.transfer(owner(), token.balanceOf(address(this)));
    }
}
