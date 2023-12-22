// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./console.sol";

contract AnylLotteryEth is Ownable {
    IERC20 tokenTicket;
    uint256 public ethInLottery;
    uint256 public maxEthInLottery;
    uint256 public tokensInLottery;
    uint256 public maxTokensInLottery;
    uint256 public minTokensForBet;
    uint256 public maxTokensForBet;
    uint256 public winRate = 10; 
    uint256 public winMultiplier = 10; 
    uint private randomCounter = 1;

    event BetResult(address indexed _from, uint256 _value);

    constructor(address _addressTokenTicket) {
        tokenTicket = IERC20(_addressTokenTicket);
    }

    function startLottery(uint256 _maxTokensInLottery, uint256 _minTokensForBet, uint256 _maxTokensForBet) public payable onlyOwner {
        require(msg.value > 0, "Missing ETH for lottery");
        require(_maxTokensInLottery > 0, "Missing lottery tokens");

        ethInLottery = msg.value;
        maxEthInLottery = msg.value;
        maxTokensInLottery = _maxTokensInLottery;
        minTokensForBet = _minTokensForBet;
        maxTokensForBet = _maxTokensForBet;
    }

    function bet(uint256 _tokens) public {
        require(maxEthInLottery > 0, "Lottery is not running");
        require(tokensInLottery < maxTokensInLottery, "Lottery is over");
        require(_tokens >= minTokensForBet, "Bet is too low");
        require(_tokens <= maxTokensForBet, "Bet is too large");

        tokensInLottery += _tokens;
        tokenTicket.transferFrom(msg.sender, address(this), _tokens);
        console.log('tokensInLottery',tokensInLottery,maxTokensInLottery);
        console.log('ethInLottery',ethInLottery,maxEthInLottery);

        
        uint256 prize = (maxEthInLottery * _tokens * winMultiplier) / maxTokensInLottery;

        uint rand = random(msg.sender);
        if (ethInLottery >= prize && rand % 10000 < winRate * 100) {
            console.log("Lottery win", prize);
            ethInLottery -= prize;
            (bool sent, ) = payable(msg.sender).call{value: prize}("");
            require(sent, "Failed to send Ether");
            emit BetResult(msg.sender, prize);
        } else {
            console.log("Lottery loose");
            emit BetResult(msg.sender, 0);
        }
    }

    function withdrawEth() public onlyOwner {
        uint256 balance = address(this).balance;
        (bool sent, ) = payable(msg.sender).call{value: balance}("");
        require(sent, "Failed to send Ether");
    }

    function withdrawTokens() public onlyOwner {
        tokenTicket.transfer(msg.sender, tokenTicket.balanceOf(address(this)));
    }

    function random(address sender) private returns (uint) {
        randomCounter++;
        return uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, sender)));
    }
}

