// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC20Burnable.sol";
import "./IERC20.sol";

contract RelayLottery {
    ERC20Burnable public ERC20Token;

    uint256 public pool;
    uint256 public fees;
    uint256 public ticket_cost;
    uint256 public fee_basis_points = 500;
    uint256 public total_basis_points = 10000;

    address s_owner;
    address g_owner;
    address[] public players;
    address[] public bonusPoolTokens;

    bool public lotteryStarted;

    mapping(address => uint256) public bonusPool;

    constructor(address tokenAddress, address giver) {
        s_owner = msg.sender;
        g_owner = giver;
        ERC20Token = ERC20Burnable(tokenAddress);
        pool = 0;
        fees = 0;
        ticket_cost = 10 ether;
    }

    modifier onlyOwner() {
        require(msg.sender == s_owner, "Caller is not the owner");
        _;
    }

    modifier onlyGiver() {
        require(msg.sender == g_owner || msg.sender == s_owner, "Caller is not the giver");
        _;
    }

    modifier hasLotteryStarted() {
        require(lotteryStarted, "Lottery has not yet started");
        _;
    }

    modifier notZeroPlayers() {
        require(players.length != 0, "No one in the lottery");
        _;
    }

    function updateTicketCost(uint256 newTicketCost) external onlyOwner {
        ticket_cost = newTicketCost;
    }

    function updateFeeBasisPoints(uint256 _fee_basis_points)
        external
        onlyOwner
    {
        fee_basis_points = _fee_basis_points;
    }

    function updateTotalBasisPoints(uint256 _total_basis_points)
        external
        onlyOwner
    {
        total_basis_points = _total_basis_points;
    }

    function giveTickets(address wallet, uint256 amount) external onlyGiver {
        for (uint256 i = 0; i < amount; i++) {
            players.push(wallet);
        }
    }

    function addBonusTokens(address tokenAddress, uint256 amount)
        external
        payable
        onlyOwner
    {
        bool alreadyIn = false;
        for (uint256 i = 0; i < bonusPoolTokens.length; i++) {
            if (tokenAddress == bonusPoolTokens[i]) {
                alreadyIn = true;
            }
        }
        if (!alreadyIn) {
            bonusPoolTokens.push(tokenAddress);
        }

        if (tokenAddress == address(0)) {
            require(
                amount == msg.value,
                "provided amount does not match native tokens sent"
            );
            bonusPool[tokenAddress] += amount;
        } else {
            bonusPool[tokenAddress] += amount;
            IERC20(tokenAddress).transferFrom(
                msg.sender,
                address(this),
                amount
            );
        }
    }

    function removeBonusToken(address tokenAddress) external onlyOwner {
        uint256 bonusTokensLength = bonusPoolTokens.length;
        require(
            bonusTokensLength != 0,
            "no bonus token to remove from lottery"
        );
        // require(bonusTokensLength != 0, "No bonus tokens in lottery");
        uint256 currentBonusTokenAmount = bonusPool[tokenAddress];
        uint256 poolIndex = 0;
        // Find index of token in array of bonus tokens
        while (
            poolIndex < bonusTokensLength &&
            bonusPoolTokens[poolIndex] != tokenAddress
        ) {
            if (poolIndex == bonusTokensLength - 1) break;
            poolIndex++;
        }

        // Guard if token not found
        require(
            bonusPoolTokens[poolIndex] == tokenAddress,
            "Token is not in bonus pool"
        );

        // Remove the token from the array and reset amount
        while (poolIndex < bonusTokensLength - 1) {
            bonusPoolTokens[poolIndex] = bonusPoolTokens[poolIndex + 1];
            poolIndex++;
        }
        bonusPoolTokens.pop();
        bonusPool[tokenAddress] = 0;

        // send current funds of token to owner
        if (tokenAddress == address(0)) {
            payable(msg.sender).transfer(currentBonusTokenAmount);
        } else {
            IERC20(tokenAddress).transfer(msg.sender, currentBonusTokenAmount);
        }
    }

    function startNextLottery() external onlyOwner {
        lotteryStarted = true;
    }

    function stopLottery() external onlyOwner {
        lotteryStarted = false;
    }

    function getPlayers() external view returns (address[] memory) {
        return players;
    }

    function getBonusPoolTokens() external view returns (address[] memory) {
        return bonusPoolTokens;
    }

    function enter(uint256 numTickets) public hasLotteryStarted {
        ERC20Token.transferFrom(
            msg.sender,
            address(this),
            ticket_cost * numTickets
        );
        uint256 poolRatio = (ticket_cost) / 2;
        ERC20Token.burn(poolRatio * numTickets);
        uint256 poolShare = ((total_basis_points - fee_basis_points) *
            poolRatio) / total_basis_points;
        pool = pool + (poolShare * numTickets);
        fees = fees + ((poolRatio - poolShare) * numTickets);
        for (uint256 index = 0; index < numTickets; index++) {
            players.push(msg.sender);
        }
    }

    function withdrawFees() external onlyOwner {
        ERC20Token.transfer(msg.sender, fees);
        fees = 0;
    }

    function withdrawRemaining(address tokenAddress, uint256 amount)
        external
        onlyOwner
    {
        require(
            IERC20(tokenAddress).balanceOf(address(this)) >= amount,
            "Invalid amount requested to be withdrawn"
        );
        if (tokenAddress == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(tokenAddress).transfer(msg.sender, amount);
        }
    }
}

