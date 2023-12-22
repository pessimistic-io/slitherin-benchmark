// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./VRFCoordinatorV2Interface.sol";
import "./AutomationCompatible.sol";
import "./ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";

//import "forge-std/console.sol";

interface IBankRoll {
    function getOwner() external view returns (address);
}

contract Lottery is AutomationCompatibleInterface, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address immutable weth;

    bytes32 immutable keyHash;
    uint64 immutable subId;
    uint16 constant minimumRequestConfirmations = 50;
    uint32 constant callBackGasLimit = 2_500_000;
    address immutable chainLinkVRF;

    uint256[12] MONTH_DURATION = [
        31,
        28,
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31
    ];
    uint256 public constant TICKET_COST = 0.001 ether;

    uint256 constant REBATE_SHARE = 5_000_000;
    uint256 constant BANKROLL_SHARE = 5_000_000;
    uint256 constant NEXT_LOTTERY_SHARE = 5_000_000;
    uint256 constant CHARITY_SHARE = 5_000_000;
    uint256 constant DIVISOR = 100_000_000;

    uint64 constant K = 1000;

    address immutable bankRoll;

    enum LotteryStatus {
        OPEN,
        PENDING_VRF,
        STOPPED,
        ERROR,
        CANCELED
    }

    struct Ticket {
        address player;
        uint64 startIndex;
        uint64 endIndex;
    }

    struct PlayerStats {
        uint128 ticketSum;
        uint64 numTicketsRebate;
        uint64 numTicketsBought;
        uint256 lastRoundPlayed;
    }

    struct LotteryGame {
        uint256 winnerPool;
        uint256 rebatePool;
        uint256 bankrollPool;
        uint256 nextLotteryPool;
        uint256 charityPool;
        Ticket[] tickets;
        uint64 totalTicketsBought;
        uint64 closeTime;
        uint64 blockNumberRequest;
        uint256 requestId;
    }

    bool public stopLottery;
    uint256 public charityFunds;

    uint256 public currentGameId;
    uint256 public currentMonth;
    uint256 public currentYear;
    LotteryStatus public currentLotteryStatus;

    mapping(uint256 => LotteryGame) public games;
    mapping(address => PlayerStats) public playerStats;

    error OnlyCoordinatorCanFulfill(address have, address want);
    error InvalidLotteryState(LotteryStatus have, LotteryStatus want);
    error InvalidTime(uint256 finishTime, uint256 currentTime);

    event TicketPurchased(
        uint256 roundId,
        address indexed player,
        uint64 amount,
        uint64 totalTicketsPurchased,
        uint256 rebateAmount
    );
    event VRFRequested(uint256 requestId);
    event LotteryResult(
        uint256 roundId,
        uint256 winningTicketId,
        address indexed winner,
        uint256 prize,
        uint256 nextLottery,
        uint256 charity
    );
    event DonationPerformed(address indexed to, uint256 amount);
    event RebateClaimed(
        uint256 roundId,
        address indexed player,
        uint256 amount
    );

    constructor(
        address _weth,
        bytes32 _keyHash,
        uint64 _subId,
        address _vrf,
        uint64 initialCloseTime,
        address _bankroll,
        uint256 _currentMonth,
        uint256 _currentYear
    ) {
        weth = _weth;
        keyHash = _keyHash;
        subId = _subId;
        chainLinkVRF = _vrf;
        bankRoll = _bankroll;

        currentGameId = 1;
        currentLotteryStatus = LotteryStatus.OPEN;
        games[currentGameId].closeTime = initialCloseTime;

        currentMonth = _currentMonth;
        currentYear = _currentYear;
    }

    function getState(
        address player
    )
        external
        view
        returns (
            uint256 _currentRoundId,
            LotteryGame memory _currentLottery,
            LotteryStatus _currentStatus,
            uint256 _currentMonth,
            uint256 _currentYear,
            PlayerStats memory _playerStatus,
            uint256 _playerRebateAvailable
        )
    {
        _currentRoundId = currentGameId;
        _currentLottery = games[currentGameId];
        _currentStatus = currentLotteryStatus;
        _currentMonth = currentMonth;
        _currentYear = currentYear;
        _playerStatus = playerStats[player];
        _playerRebateAvailable = _claimPrize(player);
    }

    function getGame(uint256 id) external view returns (LotteryGame memory) {
        return games[id];
    }

    function getPlayerStats(
        address player
    ) external view returns (PlayerStats memory) {
        return playerStats[player];
    }

    // Player Functions
    function purchaseTickets(uint64 amount) external payable nonReentrant {
        LotteryGame storage game = games[currentGameId];
        if (currentLotteryStatus != LotteryStatus.OPEN) {
            revert InvalidLotteryState(
                currentLotteryStatus,
                LotteryStatus.OPEN
            );
        }
        if (game.closeTime < block.timestamp) {
            revert InvalidTime(game.closeTime, block.timestamp);
        }
        PlayerStats memory stats = playerStats[msg.sender];

        uint256 totalCost = amount * TICKET_COST;
        uint256 amountToClaim = _claimPrize(msg.sender);
        if (amountToClaim != 0) {
            emit RebateClaimed(
                stats.lastRoundPlayed,
                msg.sender,
                amountToClaim
            );
            delete (stats);
        }
        if (
            stats.lastRoundPlayed != currentGameId && stats.lastRoundPlayed != 0
        ) {
            delete (stats);
        }
        if (msg.value + amountToClaim > totalCost) {
            _transferETH(msg.sender, msg.value + amountToClaim - totalCost);
        } else if (msg.value + amountToClaim < totalCost) {
            revert();
        }
        uint64 ticketsBefore = game.totalTicketsBought;
        uint64 ticketsAfter = ticketsBefore + amount;
        game.totalTicketsBought += amount;

        uint256 bankrollPool = (totalCost * BANKROLL_SHARE) / DIVISOR;
        uint256 rebatePool = (totalCost * REBATE_SHARE) / DIVISOR;
        uint256 nextLotteryPool = (totalCost * NEXT_LOTTERY_SHARE) / DIVISOR;
        uint256 charityPool = (totalCost * CHARITY_SHARE) / DIVISOR;
        game.bankrollPool += bankrollPool;
        game.rebatePool += rebatePool;
        game.nextLotteryPool += nextLotteryPool;
        game.charityPool += charityPool;
        game.winnerPool +=
            totalCost -
            bankrollPool -
            rebatePool -
            nextLotteryPool -
            charityPool;

        game.tickets.push(
            Ticket(msg.sender, ticketsBefore, ticketsBefore + amount - 1)
        );
        stats.numTicketsBought += amount;
        stats.lastRoundPlayed = currentGameId;
        if (ticketsBefore < K) {
            if (ticketsAfter > K) {
                uint64 inc = K - ticketsBefore;

                stats.numTicketsRebate += inc;
                stats.ticketSum += (inc * (inc + (2 * ticketsBefore) - 1)) / 2;
            } else {
                stats.numTicketsRebate += amount;
                stats.ticketSum +=
                    (amount * (amount + (2 * ticketsBefore) - 1)) /
                    2;
            }
        }
        playerStats[msg.sender] = stats;
        emit TicketPurchased(
            currentGameId,
            msg.sender,
            amount,
            ticketsAfter,
            amountToClaim
        );
    }

    function claimRebate() external nonReentrant {
        uint256 amountToClaim = _claimPrize(msg.sender);
        if (amountToClaim != 0) {
            delete (playerStats[msg.sender]);
            _transferETH(msg.sender, amountToClaim);
            emit RebateClaimed(
                playerStats[msg.sender].lastRoundPlayed,
                msg.sender,
                amountToClaim
            );
        }
    }

    function _claimPrize(address player) public view returns (uint256) {
        PlayerStats memory stats = playerStats[player];
        if (
            stats.lastRoundPlayed == 0 ||
            stats.lastRoundPlayed == currentGameId ||
            stats.numTicketsRebate == 0
        ) {
            return 0;
        }

        uint256 totalRebate = games[stats.lastRoundPlayed].rebatePool;
        uint256 totalTicketsBought = games[stats.lastRoundPlayed]
            .totalTicketsBought;
        if (totalTicketsBought > K) {
            totalTicketsBought = K;
        }
        if (totalTicketsBought == 1) {
            return totalRebate;
        }
        uint256 u = stats.numTicketsRebate;

        uint256 sum = stats.ticketSum;

        uint256 b = (2 * totalRebate) / (totalTicketsBought);
        uint256 m = (b * K) / (totalTicketsBought - 1);
        if (((m * sum) / (K)) + 1 > b * u) {
            return 0;
        }

        uint256 reward = b * u - ((m * sum) / (K)) - 1;

        return reward;
    }

    // Onwer Functions
    function closeLottery() external {
        if (msg.sender != IBankRoll(bankRoll).getOwner()) {
            revert();
        }
        stopLottery = true;
    }

    function donate(address to, uint256 amount) external nonReentrant {
        if (msg.sender != IBankRoll(bankRoll).getOwner()) {
            revert();
        }
        if (charityFunds < amount) {
            revert();
        }
        charityFunds -= amount;
        _transferETH(to, amount);
        emit DonationPerformed(to, amount);
    }

    // Emergency functions
    function errorLottery() external {
        if (
            currentLotteryStatus == LotteryStatus.STOPPED ||
            currentLotteryStatus == LotteryStatus.ERROR
        ) {
            revert InvalidLotteryState(
                currentLotteryStatus,
                LotteryStatus.PENDING_VRF
            );
        }
        if (block.timestamp < games[currentGameId].closeTime + (2 weeks)) {
            revert InvalidTime(
                games[currentGameId].closeTime + (2 weeks),
                block.timestamp
            );
        }
        currentLotteryStatus = LotteryStatus.ERROR;
    }

    function cancelLottery() external {
        if (msg.sender != IBankRoll(bankRoll).getOwner()) {
            revert();
        }
        currentLotteryStatus = LotteryStatus.CANCELED;
    }

    function rescueTicket(uint256 ticketIndex) external nonReentrant {
        if (
            !(currentLotteryStatus == LotteryStatus.ERROR ||
                currentLotteryStatus == LotteryStatus.CANCELED)
        ) {
            revert InvalidLotteryState(
                currentLotteryStatus,
                LotteryStatus.ERROR
            );
        }

        Ticket memory t = games[currentGameId].tickets[ticketIndex];
        delete (games[currentGameId].tickets[ticketIndex]);
        uint256 totalValue = (1 + t.endIndex - t.startIndex) * TICKET_COST;
        _transferETH(t.player, totalValue);
    }

    function rescueETH(address to, uint256 amount) external nonReentrant {
        if (msg.sender != IBankRoll(bankRoll).getOwner()) {
            revert();
        }
        if (block.timestamp < games[currentGameId].closeTime + (5 weeks)) {
            revert();
        }
        _transferETH(to, amount);
    }

    // Chainlink Functions
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded =
            (games[currentGameId].closeTime < block.timestamp &&
                currentLotteryStatus == LotteryStatus.OPEN) ||
            (currentLotteryStatus == LotteryStatus.PENDING_VRF &&
                block.number > games[currentGameId].blockNumberRequest + 1000);
    }

    function performUpkeep(bytes calldata performData) external override {
        if (
            (games[currentGameId].closeTime < block.timestamp &&
                currentLotteryStatus == LotteryStatus.OPEN) ||
            (currentLotteryStatus == LotteryStatus.PENDING_VRF &&
                block.number > games[currentGameId].blockNumberRequest + 1000)
        ) {
            LotteryGame storage game = games[currentGameId];

            if (game.tickets.length == 0) {
                if (stopLottery) {
                    currentLotteryStatus = LotteryStatus.STOPPED;
                    return;
                }
                currentLotteryStatus = LotteryStatus.OPEN;
                emit LotteryResult(
                    currentGameId,
                    0,
                    address(0),
                    0,
                    game.nextLotteryPool,
                    0
                );

                LotteryGame storage nextLottery = games[currentGameId + 1];
                _setupNextLotteryStartTime(nextLottery, game.closeTime);
                nextLottery.winnerPool = game.nextLotteryPool;

                currentGameId++;

                return;
            } else {
                currentLotteryStatus = LotteryStatus.PENDING_VRF;
                uint256 id = VRFCoordinatorV2Interface(chainLinkVRF)
                    .requestRandomWords(
                        keyHash,
                        subId,
                        minimumRequestConfirmations,
                        callBackGasLimit,
                        1
                    );
                game.blockNumberRequest = uint64(block.number);
                game.requestId = id;
                emit VRFRequested(id);
            }
        }
    }

    /**
     * @dev function called by Chainlink VRF with random numbers
     * @param requestId id provided when the request was made
     * @param randomWords array of random numbers
     */
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        if (msg.sender != chainLinkVRF) {
            revert OnlyCoordinatorCanFulfill(msg.sender, chainLinkVRF);
        }
        fulfillRandomWords(requestId, randomWords);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal {
        if (requestId != games[currentGameId].requestId) {
            revert();
        }
        if (currentLotteryStatus != LotteryStatus.PENDING_VRF) {
            revert();
        }
        LotteryGame storage game = games[currentGameId];

        uint256 max = game.tickets.length - 1;
        uint256 min = 0;
        uint256 guess;

        uint256 winningTicket = (randomWords[0] % game.totalTicketsBought);
        address winner;

        while (min <= max) {
            guess = (min + max) / 2;

            if (
                winningTicket >= game.tickets[guess].startIndex &&
                winningTicket <= game.tickets[guess].endIndex
            ) {
                winner = game.tickets[guess].player;
                break;
            }

            if (game.tickets[guess].startIndex > winningTicket) {
                max = guess - 1;
            } else {
                min = guess + 1;
            }
        }

        if (winner == address(0)) {
            currentLotteryStatus = LotteryStatus.ERROR;
            return;
        }

        if (stopLottery) {
            currentLotteryStatus = LotteryStatus.STOPPED;

            _transferETH(winner, game.winnerPool + game.nextLotteryPool);
            _transferETH(bankRoll, game.bankrollPool);

            emit LotteryResult(
                currentGameId,
                winningTicket,
                winner,
                game.winnerPool + game.nextLotteryPool,
                0,
                game.charityPool
            );
            charityFunds += game.charityPool;
            currentGameId++;
        } else {
            currentLotteryStatus = LotteryStatus.OPEN;

            _transferETH(winner, game.winnerPool);
            _transferETH(bankRoll, game.bankrollPool);

            emit LotteryResult(
                currentGameId,
                winningTicket,
                winner,
                game.winnerPool,
                game.nextLotteryPool,
                game.charityPool
            );
            LotteryGame storage nextLottery = games[currentGameId + 1];

            _setupNextLotteryStartTime(nextLottery, game.closeTime);

            nextLottery.winnerPool = game.nextLotteryPool;
            charityFunds += game.charityPool;
            currentGameId++;
        }
    }

    function _setupNextLotteryStartTime(
        LotteryGame storage nextLottery,
        uint64 currentLotteryCloseTime
    ) internal {
        if (currentMonth == 11) {
            currentMonth = 0;
            currentYear += 1;
            nextLottery.closeTime =
                currentLotteryCloseTime +
                (uint64(MONTH_DURATION[currentMonth]) * 1 days);
        } else {
            currentMonth += 1;
            if (currentMonth == 1) {
                if (
                    currentYear % 4 == 0 &&
                    (currentYear % 100 != 0 || currentYear % 400 == 0)
                ) {
                    nextLottery.closeTime = currentLotteryCloseTime + (29 days);
                } else {
                    nextLottery.closeTime = currentLotteryCloseTime + (28 days);
                }
            } else {
                nextLottery.closeTime =
                    currentLotteryCloseTime +
                    (uint64(MONTH_DURATION[currentMonth]) * 1 days);
            }
        }
    }

    function _transferETH(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount, gas: 3000}("");
        if (!success) {
            (bool _success, ) = weth.call{value: amount}(
                abi.encodeWithSignature("deposit()")
            );
            if (!_success) {
                revert();
            }
            IERC20(weth).safeTransfer(to, amount);
        }
    }
}

