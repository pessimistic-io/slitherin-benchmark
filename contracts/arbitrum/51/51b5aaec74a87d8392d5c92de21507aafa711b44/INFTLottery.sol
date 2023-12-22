// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./IERC721Receiver.sol";

interface INFTLottery is IERC721Receiver {
    enum LotteryState { Pending, Open, Closed }

    struct Lottery {
        address owner;
        address salesRecipient;
        address nftAddress;
        uint256 tokenId;
        address ticketCurrency;
        uint256 ticketCost;
        uint16 minTickets;
        uint8 category;
        uint256 startTimestamp;
        uint256 endTimestamp;
        LotteryState state;
        address winner;
    }

    struct LotteryPlayers {
        uint256 totalTicketsSold;
        address[] playerWallets;    
        mapping(address => uint256) tickets;
    }

    event LotteryCreated(uint256 indexed lotteryId, Lottery lottery);
    event LotteryOpened(uint256 indexed lotteryId, Lottery lottery);
    event LotteryClosed(uint256 indexed lotteryId, Lottery lottery);
    event LotteryRefund(uint256 indexed lotteryId, address indexed player, Lottery lottery, uint256 refundAmount);
    event RaffleTokenClaim(uint256 indexed lotteryId, address indexed player, Lottery lottery, uint256 claimedTokenAmount);
    event LotteryTicketBought(uint256 indexed lotteryId, address player, uint256 amount);
    event LotteryWinner(uint256 indexed lotteryId, address winner, Lottery lottery); 

    function createLottery(Lottery calldata lotteryData) external returns (uint256);
    function openLottery(uint256 lotteryId) external;
    function closeLottery(uint256 lotteryId) external;
    function buyTicket(uint256 lotteryId, uint256 numberOfTickets) external;

    // LotteryPlayers struct variables
    function getTotalTicketsSold(uint256 lotteryId) external view returns (uint256);
    function getPlayerWallets(uint256 lotteryId) external view returns (address[] memory);
    function getTickets(uint256 lotteryId, address player) external view returns (uint256);
}
