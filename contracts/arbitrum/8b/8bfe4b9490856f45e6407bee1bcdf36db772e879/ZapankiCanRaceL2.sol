// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ZapankiGamesL2.sol";

contract ZapankiCanRaceL2 is ZapankiGamesL2 {
    using SafeERC20 for IERC20;

    struct CanRaceGame {
        uint256 wager;
        uint256 vrfId;
        address tokenAddress;
        uint64 blockNumber;
        uint8 pickedCanId;
    }

    mapping(address => CanRaceGame) canRaceGames;
    mapping(uint256 => address) vrfPendingPlayer;

    mapping(uint8 => uint64) public canMultipliers;

    event CanRaceFulfilled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint8 winnerCanId,
        uint64 multiplier,
        uint256 l2eAmount
    );
    event CanRaceRefund(address indexed player, uint256 wager, address tokenAddress);

    constructor(
        address _vrfCoordinator,
        IBankroll _bankroll,
        address _trustedForwarder,
        address _link_eth_feed,
        bytes32 _vrfKeyHash,
        uint64 _vrfSubId,
        uint32 _vrfCallbackGasLimit
    )
        ZapankiGamesL2(
            _vrfCoordinator,
            _bankroll,
            _trustedForwarder,
            _link_eth_feed,
            _vrfKeyHash,
            _vrfSubId,
            _vrfCallbackGasLimit
        )
    {
        canMultipliers[1] = 19600;
        canMultipliers[2] = 29600;
        canMultipliers[3] = 79600;
        canMultipliers[4] = 149600;
        canMultipliers[5] = 599600;
    }

    function getCurrentUserState(address player) external view returns (CanRaceGame memory) {
        return (canRaceGames[player]);
    }

    function getMultipliers() external view returns (uint64[5] memory multipliers) {
        for (uint8 i = 1; i < 5; i++) {
            multipliers[i - 1] = canMultipliers[i];
        }
        return multipliers;
    }

    function getWinner(uint256 randomWord) internal pure returns (uint8 canId) {
        uint256 rand = randomWord % 10000;
        if (rand < 4800) {
            canId = 1;
        } else if (rand < 8000) {
            canId = 2;
        } else if (rand < 9200) {
            canId = 3;
        } else if (rand < 9840) {
            canId = 4;
        } else {
            canId = 5;
        }
    }

    function play(uint256 wager, address tokenAddress, uint8 pickedCanId) external payable nonReentrant {
        address msgSender = _msgSender();
        require(canRaceGames[msgSender].vrfId == 0, "Waiting VRF request");

        _checkMaxWager(wager, tokenAddress, pickedCanId);
        _processWager(tokenAddress, wager, 400000, 22, msgSender);
        uint256 id = _requestRandomWords(1);

        canRaceGames[msgSender] = CanRaceGame(wager, id, tokenAddress, uint64(block.number), pickedCanId);
        vrfPendingPlayer[id] = msgSender;
    }

    function refund() external nonReentrant {
        address msgSender = _msgSender();
        CanRaceGame storage game = canRaceGames[msgSender];
        require(game.vrfId != 0, "Not waiting VRF request");
        require(game.blockNumber + BLOCK_REFUND_COOLDOWN + 10 > block.number, "Too early");

        uint256 wager = game.wager;
        address tokenAddress = game.tokenAddress;

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit CanRaceRefund(msgSender, wager, tokenAddress);

        delete (vrfPendingPlayer[game.vrfId]);
        delete (canRaceGames[msgSender]);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address playerAddress = vrfPendingPlayer[requestId];
        if (playerAddress == address(0)) return;
        CanRaceGame storage game = canRaceGames[playerAddress];
        if (block.number > game.blockNumber + BLOCK_REFUND_COOLDOWN) return;
        uint256 payout;

        uint8 winnerCanId = getWinner(randomWords[0]);
        uint64 multiplier = canMultipliers[winnerCanId];
        bool isWon = winnerCanId == game.pickedCanId;

        uint64 userMultiplier;
        if (isWon) {
            payout += (game.wager * multiplier) / 10000;
            userMultiplier = multiplier;
        }

        _transferToBankroll(game.tokenAddress, game.wager);
        if (payout != 0) {
            _payoutBankrollToPlayer(playerAddress, payout, game.tokenAddress);
        }

        uint256 l2eAmount = bankroll.payoutL2E(playerAddress, game.tokenAddress, game.wager, payout);

        emit CanRaceFulfilled(
            playerAddress,
            game.wager,
            payout,
            game.tokenAddress,
            winnerCanId,
            userMultiplier,
            l2eAmount
        );
        delete (vrfPendingPlayer[requestId]);
        delete (canRaceGames[playerAddress]);
    }

    function _checkMaxWager(uint256 wager, address tokenAddress, uint8 canId) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * (11000 - 10890)) / (canMultipliers[canId] - 10000);
        require(wager <= maxWager, "Too many wager");
    }
}

