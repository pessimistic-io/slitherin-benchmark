// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";

import "./IHunchGame.sol";
import "./ITicketFundsProvider.sol";

abstract contract HunchGame is ERC721Enumerable, IHunchGame, Ownable {
    struct TicketFundsInfo {
        uint256 amount;
        uint256 multipliedAmount;
        uint256 tokenId;
    }

    uint256 public constant ONE_MULTIPLIER = 10000;
    uint256 public constant TREASURY_PERCENTAGE = 500;
    uint256 public constant MAX_PERCENTAGE = 10000;

    uint256 public override gameId;
    uint256 public nextTicketId = 1;

    ITicketFundsProvider public ticketFundsProvider;

    mapping(uint256 => TicketFundsInfo) public tickets;

    address payable public treasury;

    constructor(
        string memory _name,
        string memory _symbol,
        ITicketFundsProvider _ticketFundsProvider,
        address payable _treasury
    ) ERC721(_name, _symbol) {
        require(_treasury != address(0), "Bad address");
        require(address(_ticketFundsProvider) != address(0), "Bad address");

        ticketFundsProvider = _ticketFundsProvider;
        treasury = _treasury;
    }

    receive() external payable {
        // Declared empty to simply allow contract to accept ETH (for ETH bet tickets)
    }

    function setTreasury(address payable _treasury) external override onlyOwner {
        require(_treasury != address(0), "Bad address");
        treasury = _treasury;
    }

    function createETHTicket(uint256 _ethAmount) internal 
            returns (uint256 ticketId, TicketFundsInfo memory ticket, uint256 treasuryAmount, uint256 multiplier) {

        require(_ethAmount > 0, "Amount not positive");
        return createAmountTicket(_ethAmount, _ethAmount);
    }

    function createETHTicketFromPosition(uint256 _tokenId, uint256 _token0ETHPrice, uint256 _token1ETHPrice) internal 
            returns (uint256 ticketId, TicketFundsInfo memory ticket, uint256 treasuryAmount, uint256 multiplier) {
        ticketId = createPositionTicket(_tokenId);
        (, multiplier, treasuryAmount) = updatePositionTicket(ticketId, _token0ETHPrice, _token1ETHPrice, false);

        ticket = tickets[ticketId];
    }

    function createPositionTicket(uint256 _tokenId) internal returns (uint256 ticketId)
    {
        (address owner,,,,,) = ticketFundsProvider.stakedPositions(_tokenId);
        if (owner != address(0)) {
            require(owner == msg.sender, "Not allowed");
        }

        ticketId = mintTicket();
        tickets[ticketId] = TicketFundsInfo(0, 0, _tokenId);

        if (owner == address(0)) {
            ticketFundsProvider.stakeWithTicket(_tokenId, msg.sender, ticketId);
        } else {
            ticketFundsProvider.updateTicketInfo(_tokenId, msg.sender, ticketId);
        }
    }

    // Multiplier returend format: ONE_MULTIPLIER (10000) represents a multiplier of 1.0
    function updatePositionTicket(uint256 _ticketId, uint256 _token0ETHPrice, uint256 _token1ETHPrice, bool _raiseCloseEvent) internal returns (uint256 multipliedAmount, uint256 multiplier, uint256 treasuryAmount) {
        require(ownerOf(_ticketId) == msg.sender, "Not allowed");

        TicketFundsInfo storage ticket = tickets[_ticketId];

        require(ticket.tokenId != 0, "Not position ticket");

        (uint256 ethAmount, uint256 timeMultipliedETHAmount) = ticketFundsProvider.getFunds(
            ticket.tokenId, msg.sender, _ticketId, _token0ETHPrice, _token1ETHPrice);
        require(ethAmount > 0, "No fees");

        treasuryAmount = getTreasuryAmount(ethAmount);
        uint256 tokenId = ticket.tokenId;
        ticket.tokenId = 0;
        ticket.amount = ethAmount - treasuryAmount;

        (multipliedAmount, multiplier) = getMultipliedETHAmount(timeMultipliedETHAmount, _ticketId);

        ticket.multipliedAmount = multipliedAmount;

        sendToTreasury(treasuryAmount);

        if (_raiseCloseEvent) {
            emit ClosePositionTicket(msg.sender, _ticketId, tokenId, ticket.amount + treasuryAmount, 
                treasuryAmount, ticket.amount, ticket.multipliedAmount, multiplier);
        }
    }

    function getMultipliedETHAmount(uint256 _ethAmount, uint256 _ticketId) public virtual 
        returns (uint256 multipliedETHAmount, uint256 multiplier);

    function createAmountTicket(uint256 _ethAmount, uint256 _timeMultipliedETHAmount) private 
            returns (uint256 ticketId, TicketFundsInfo memory ticket, uint256 treasuryAmount, uint256 multiplier) {

        treasuryAmount = getTreasuryAmount(_ethAmount);

        ticketId = mintTicket();

        uint256 multipliedAmount;
        (multipliedAmount, multiplier) = getMultipliedETHAmount(_timeMultipliedETHAmount, ticketId);
        ticket = TicketFundsInfo(_ethAmount - treasuryAmount, multipliedAmount, 0);
        tickets[ticketId] = ticket;

        sendToTreasury(treasuryAmount);   
    }

    function mintTicket() private returns (uint256 ticketId) {
        ticketId = nextTicketId++;
        _safeMint(msg.sender, ticketId);
    }

    function sendToTreasury(uint256 _ethAmount) internal {
        (bool sentToTreasury, ) = treasury.call{value: _ethAmount}("");
        require(sentToTreasury, "Failed to send to treasury");
    }

    function getTreasuryAmount(uint256 _ethAmount) internal pure returns (uint256 treasuryAmount)
    {
        treasuryAmount = _ethAmount * TREASURY_PERCENTAGE / MAX_PERCENTAGE;
    }

    function getAmountBeforeTreasury(uint256 _ethAmount) internal pure returns (uint256 amountBeforeTreasury) {
        amountBeforeTreasury = _ethAmount * MAX_PERCENTAGE / (MAX_PERCENTAGE - TREASURY_PERCENTAGE);
    }
}

