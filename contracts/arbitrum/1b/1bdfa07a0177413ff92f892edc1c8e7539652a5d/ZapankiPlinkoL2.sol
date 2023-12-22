// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ZapankiGamesL2.sol";

contract ZapankiPlinkoL2 is ZapankiGamesL2 {
    using SafeERC20 for IERC20;

    struct PlinkoGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 vrfId;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        uint8 risk;
        uint8 numRows;
    }

    mapping(address => PlinkoGame) plinkoGames;
    mapping(uint256 => address) vrfPendingPlayer;
    uint256[18][18][18] plinkoMultipliers;
    uint256[9][3] kellyFractions;

    event PlinkoFulfilled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        bool[][] paths,
        uint8 risk,
        uint256[] payouts,
        uint32 numGames,
        uint256 l2eAmount
    );
    event PlinkoRefund(address indexed player, uint256 wager, address tokenAddress);

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
        kellyFractions[0] = [573159, 240816, 372158, 267835, 453230, 480140, 327817, 384356, 467936];
        kellyFractions[1] = [108157, 100164, 100856, 82065, 91981, 83772, 68092, 69475, 100288];
        kellyFractions[2] = [31369, 25998, 38394, 27787, 29334, 29004, 22764, 21439, 27190];

        plinkoMultipliers[0][0] = [2050, 400, 90, 60, 40, 60, 90, 400, 2050];
        plinkoMultipliers[0][1] = [4500, 800, 90, 60, 40, 40, 60, 90, 800, 4500];
        plinkoMultipliers[0][2] = [4700, 800, 200, 90, 60, 40, 60, 90, 200, 800, 4700];
        plinkoMultipliers[0][3] = [6500, 1700, 400, 90, 60, 40, 40, 60, 90, 400, 1700, 6500];
        plinkoMultipliers[0][4] = [7000, 1600, 300, 200, 90, 60, 40, 60, 90, 200, 300, 1600, 7000];
        plinkoMultipliers[0][5] = [8000, 1700, 600, 400, 90, 60, 40, 40, 60, 90, 400, 600, 1700, 8000];
        plinkoMultipliers[0][6] = [10000, 4500, 900, 300, 110, 90, 60, 40, 60, 90, 110, 300, 900, 4500, 10000];
        plinkoMultipliers[0][7] = [11000, 4500, 1300, 900, 110, 90, 60, 40, 40, 60, 90, 110, 900, 1300, 4500, 11000];
        plinkoMultipliers[0][8] = [
            12000,
            2800,
            2400,
            800,
            200,
            90,
            90,
            60,
            40,
            60,
            90,
            90,
            200,
            800,
            2400,
            2800,
            12000
        ];
        plinkoMultipliers[1][0] = [5000, 400, 50, 40, 20, 40, 50, 400, 5000];
        plinkoMultipliers[1][1] = [6600, 1200, 50, 40, 20, 20, 40, 50, 1200, 6600];
        plinkoMultipliers[1][2] = [9500, 1000, 200, 90, 40, 20, 40, 90, 200, 1000, 9500];
        plinkoMultipliers[1][3] = [15000, 2000, 500, 60, 50, 20, 20, 50, 60, 500, 2000, 15000];
        plinkoMultipliers[1][4] = [17500, 3500, 400, 200, 60, 40, 20, 40, 60, 200, 400, 3500, 17500];
        plinkoMultipliers[1][5] = [25000, 4400, 700, 400, 90, 40, 20, 20, 40, 90, 400, 700, 4400, 25000];
        plinkoMultipliers[1][6] = [39000, 5500, 1500, 400, 90, 80, 40, 20, 40, 80, 90, 400, 1500, 5500, 39000];
        plinkoMultipliers[1][7] = [50000, 6000, 2200, 800, 200, 90, 40, 20, 20, 40, 90, 200, 800, 2200, 6000, 50000];
        plinkoMultipliers[1][8] = [
            52000,
            8000,
            1500,
            1000,
            300,
            200,
            50,
            30,
            20,
            30,
            50,
            200,
            300,
            1000,
            1500,
            8000,
            52000
        ];
        plinkoMultipliers[2][0] = [10000, 60, 20, 20, 10, 20, 20, 60, 10000];
        plinkoMultipliers[2][1] = [14300, 500, 70, 30, 10, 10, 30, 70, 500, 14300];
        plinkoMultipliers[2][2] = [17000, 1500, 200, 30, 20, 10, 20, 30, 200, 1500, 17000];
        plinkoMultipliers[2][3] = [29000, 1500, 200, 80, 50, 30, 30, 50, 80, 200, 1500, 29000];
        plinkoMultipliers[2][4] = [38000, 2000, 400, 200, 80, 30, 10, 30, 80, 200, 400, 2000, 38000];
        plinkoMultipliers[2][5] = [50000, 6800, 700, 200, 90, 40, 20, 20, 40, 90, 200, 700, 6800, 50000];
        plinkoMultipliers[2][6] = [77000, 6500, 1300, 300, 200, 50, 30, 10, 30, 50, 200, 300, 1300, 6500, 77000];
        plinkoMultipliers[2][7] = [80000, 20000, 5000, 500, 80, 50, 30, 10, 10, 30, 50, 80, 500, 5000, 20000, 80000];
        plinkoMultipliers[2][8] = [
            100000,
            28000,
            3000,
            1500,
            150,
            60,
            50,
            40,
            10,
            40,
            50,
            60,
            150,
            1500,
            3000,
            28000,
            100000
        ];
    }

    function getCurrentUserState(address player) external view returns (PlinkoGame memory) {
        return (plinkoGames[player]);
    }

    function play(
        uint256 wager,
        address tokenAddress,
        uint8 numRows,
        uint8 risk,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        address msgSender = _msgSender();
        require(8 <= numRows && numRows <= 16, "numRows must be between 8 and 16");
        require(risk < 3, "risk: 0, 1, 2");
        require(plinkoGames[msgSender].vrfId == 0, "Waiting VRF request");
        require(0 < numBets && numBets <= 60, "Invalid numBets");

        _checkMaxWager(wager, tokenAddress, numRows, risk);
        _processWager(tokenAddress, wager * numBets, 1500000, 21, msgSender);
        uint256 id = _requestRandomWords(numBets);

        plinkoGames[msgSender] = PlinkoGame(
            wager,
            stopGain,
            stopLoss,
            id,
            tokenAddress,
            uint64(block.number),
            numBets,
            risk,
            numRows
        );
        vrfPendingPlayer[id] = msgSender;
    }

    function refund() external nonReentrant {
        address msgSender = _msgSender();
        PlinkoGame storage game = plinkoGames[msgSender];
        require(plinkoGames[msgSender].vrfId != 0, "Not waiting VRF request");
        require(game.blockNumber + BLOCK_REFUND_COOLDOWN + 10 > block.number, "Too early");

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit PlinkoRefund(msgSender, wager, tokenAddress);

        delete (vrfPendingPlayer[game.vrfId]);
        delete (plinkoGames[msgSender]);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        address playerAddress = vrfPendingPlayer[_requestId];
        if (playerAddress == address(0)) return;
        PlinkoGame storage game = plinkoGames[playerAddress];
        if (block.number > game.blockNumber + BLOCK_REFUND_COOLDOWN) return;

        bool[][] memory gamesResults = new bool[][](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        int256 totalValue;
        uint256 payout;
        uint32 gamePlayed;

        for (gamePlayed = 0; gamePlayed < game.numBets; gamePlayed++) {
            if (_shouldStop(totalValue, game.stopGain, game.stopLoss)) {
                break;
            }
            (uint256 multiplier, bool[] memory gameResults) = _calcResult(
                _randomWords[gamePlayed],
                game.numRows,
                game.risk
            );

            gamesResults[gamePlayed] = gameResults;
            payouts[gamePlayed] = (game.wager * multiplier) / 100;
            payout += payouts[gamePlayed];
            totalValue += int256(payouts[gamePlayed]) - int256(game.wager);
        }

        payout += (game.numBets - gamePlayed) * game.wager;

        _transferToBankroll(game.tokenAddress, game.wager * game.numBets);
        if (payout != 0) {
            _payoutBankrollToPlayer(playerAddress, payout, game.tokenAddress);
        }

        uint256 l2eAmount = bankroll.payoutL2E(playerAddress, game.tokenAddress, game.wager * game.numBets, payout);

        emit PlinkoFulfilled(
            playerAddress,
            game.wager,
            payout,
            game.tokenAddress,
            gamesResults,
            game.risk,
            payouts,
            gamePlayed,
            l2eAmount
        );

        delete (vrfPendingPlayer[_requestId]);
        delete (plinkoGames[playerAddress]);
    }

    function _calcResult(
        uint256 randomWords,
        uint8 numRows,
        uint8 risk
    ) internal view returns (uint256 multiplier, bool[] memory currentGameResult) {
        currentGameResult = new bool[](numRows);
        int8 ended = 0;
        for (uint8 g = 0; g < numRows; g++) {
            currentGameResult[g] = _isBitSet(randomWords, g);
            if (currentGameResult[g]) {
                ended += 1;
            } else {
                ended -= 1;
            }
        }
        uint8 multiplierSlot = uint8((ended + int8(numRows)) / 2);
        multiplier = plinkoMultipliers[risk][numRows - 8][multiplierSlot];
    }

    function _isBitSet(uint256 source, uint256 needle) internal pure returns (bool) {
        return (source & (1 << needle)) != 0;
    }

    function _checkMaxWager(uint256 wager, address tokenAddress, uint8 numRows, uint8 risk) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * kellyFractions[risk][numRows - 8]) / 100000000;
        require(wager <= maxWager, "Too many wager");
    }
}

