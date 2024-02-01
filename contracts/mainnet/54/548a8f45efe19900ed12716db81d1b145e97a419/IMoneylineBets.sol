// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IMoneylineBets {
    enum Result {
        NONE, WIN, DRAW, LOSE, CANCEL
    }

    enum Status {
        NONE, OPEN, CLOSED, FINALIZED, INVALIDATED
    }

    struct Bet {
        bytes32 code;
        uint256 id;
        string teamA;
        string teamB;
        uint256 startsAt;
        uint256 endsAt;
        uint256 pricePerTicket;
        uint256 prizePerTicket;
        uint256 commissionPerTicket;
        uint256 injectedAmount;
        uint256 treasuryAmount;
        Result result;
        Status status;
        mapping(Result => address[]) choices;
        mapping(Result => uint256[]) ticketCounts;
        mapping(Result => uint256) totalTicketCount;
        mapping(address => uint256) claimable;
    }

    struct BetView {
        bytes32 code;
        uint256 id;
        string teamA;
        string teamB;
        uint256 startsAt;
        uint256 endsAt;
        uint256 pricePerTicket;
        uint256 prizePerTicket;
        uint256 commissionPerTicket;
        uint256 injectedAmount;
        uint256 treasuryAmount;
        Result result;
        Status status;
        address[] winChoices;
        uint256[] winTicketCounts;
        address[] loseChoices;
        uint256[] loseTicketCounts;
        address[] drawChoices;
        uint256[] drawTicketCounts;
        uint256 winTotalTicketCount;
        uint256 drawTotalTicketCount;
        uint256 loseTotalTicketCount;
        uint256 winTotalSize;
        uint256 loseTotalSize;
        uint256 drawTotalSize;
        uint256 claimable;
    }

    struct OpenBetRequest {
        string code;
        string teamA;
        string teamB;
        uint256 startsAt;
        uint256 endsAt;
        uint256 pricePerTicket;
        uint256 commissionPerTicket;
    }

    function makeBet(uint256 id, Result choice, uint256 ticketCount) external payable;

    function claimBet(uint256 id) external;

    function openBets(
        OpenBetRequest[] calldata requests
    ) external returns (uint256);

    function closeBets(
        uint256[] calldata ids,
        Result[] calldata results
    ) external;

    function finalizeBet(uint256 id, uint256 fromIdx, uint256 limit, bool isLast) external;

    function invalidateBet(uint256 id, Result choice, uint256 fromIdx, uint256 limit, bool isLast) external;

    function settleTreasury(uint256 id) external;

    function injectBet(uint256 id) external payable;

    function viewBet(uint256 id, address viewer) external view returns (BetView memory);

    function viewBets(uint256 fromId, address viewer) external view returns (BetView[100] memory);
}
