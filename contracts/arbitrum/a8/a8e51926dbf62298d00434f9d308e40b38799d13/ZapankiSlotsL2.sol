// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ZapankiGamesL2.sol";

contract ZapankiSlotsL2 is ZapankiGamesL2 {
    using SafeERC20 for IERC20;

    struct SlotsGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 vrfId;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
    }

    mapping(address => SlotsGame) slotsGames;
    mapping(uint256 => address) vrfPendingPlayer;

    mapping(uint16 => uint16) slotsMultipliers;
    uint16 numOutcomes;

    event SlotsFulfilled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint16[] slotIDs,
        uint256[] multipliers,
        uint256[] payouts,
        uint32 numGames,
        uint256 l2eAmount
    );
    event SlotsRefund(address indexed player, uint256 wager, address tokenAddress);

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
        _setSlotsMultipliers(
            [
                5,
                3,
                3,
                3,
                3,
                3,
                3,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                2,
                10,
                10,
                12,
                12,
                20,
                20,
                45,
                100
            ],
            [
                0,
                1,
                2,
                3,
                4,
                5,
                6,
                7,
                8,
                9,
                10,
                11,
                12,
                13,
                14,
                15,
                16,
                17,
                18,
                19,
                20,
                21,
                22,
                23,
                24,
                25,
                26,
                27,
                28,
                29,
                30,
                31,
                32,
                33,
                34,
                35,
                36,
                37,
                38,
                39,
                40,
                41,
                42,
                43,
                44,
                45,
                46,
                47,
                48,
                114,
                117,
                171,
                173,
                228,
                229,
                285,
                342
            ],
            343
        );
    }

    function getCurrentUserState(address player) external view returns (SlotsGame memory) {
        return (slotsGames[player]);
    }

    function getMultipliers() external view returns (uint16[] memory) {
        uint16[] memory multipliers = new uint16[](numOutcomes);
        for (uint16 i = 0; i < numOutcomes; i++) {
            multipliers[i] = slotsMultipliers[i];
        }
        return multipliers;
    }

    function play(
        uint256 wager,
        address tokenAddress,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        address msgSender = _msgSender();
        require(slotsGames[msgSender].vrfId == 0, "Waiting VRF request");
        require(0 < numBets && numBets <= 100, "Invalid numBets");

        _checkMaxWager(wager, tokenAddress);
        _processWager(tokenAddress, wager * numBets, 800000, 24, msgSender);
        uint256 id = _requestRandomWords(numBets);

        slotsGames[msgSender] = SlotsGame(wager, stopGain, stopLoss, id, tokenAddress, uint64(block.number), numBets);
        vrfPendingPlayer[id] = msgSender;
    }

    function refund() external nonReentrant {
        address msgSender = _msgSender();
        SlotsGame storage game = slotsGames[msgSender];
        require(game.vrfId != 0, "Not waiting VRF request");
        require(game.blockNumber + BLOCK_REFUND_COOLDOWN + 10 > block.number, "Too early");

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit SlotsRefund(msgSender, wager, tokenAddress);

        delete (vrfPendingPlayer[game.vrfId]);
        delete (slotsGames[msgSender]);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address playerAddress = vrfPendingPlayer[requestId];
        if (playerAddress == address(0)) return;
        SlotsGame storage game = slotsGames[playerAddress];
        if (block.number > game.blockNumber + BLOCK_REFUND_COOLDOWN) return;

        uint256 payout;
        int256 totalValue;
        uint32 gamePlayed;
        uint16[] memory slotID = new uint16[](game.numBets);
        uint256[] memory multipliers = new uint256[](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        for (gamePlayed = 0; gamePlayed < game.numBets; gamePlayed++) {
            if (_shouldStop(totalValue, game.stopGain, game.stopLoss)) {
                break;
            }

            slotID[gamePlayed] = uint16(randomWords[gamePlayed] % numOutcomes);
            multipliers[gamePlayed] = slotsMultipliers[slotID[gamePlayed]];

            if (multipliers[gamePlayed] != 0) {
                totalValue += int256(game.wager * multipliers[gamePlayed]) - int256(game.wager);
                payout += game.wager * multipliers[gamePlayed];
                payouts[gamePlayed] = game.wager * multipliers[gamePlayed];
            } else {
                totalValue -= int256(game.wager);
            }
        }

        payout += (game.numBets - gamePlayed) * game.wager;

        _transferToBankroll(game.tokenAddress, game.wager * game.numBets);
        if (payout != 0) {
            _payoutBankrollToPlayer(playerAddress, payout, game.tokenAddress);
        }

        uint256 l2eAmount = bankroll.payoutL2E(playerAddress, game.tokenAddress, game.wager * game.numBets, payout);

        emit SlotsFulfilled(
            playerAddress,
            game.wager,
            payout,
            game.tokenAddress,
            slotID,
            multipliers,
            payouts,
            gamePlayed,
            l2eAmount
        );

        delete (vrfPendingPlayer[requestId]);
        delete (slotsGames[playerAddress]);
    }

    function _setSlotsMultipliers(
        uint8[57] memory _multipliers,
        uint16[57] memory _outcomeNum,
        uint16 _numOutcomes
    ) internal {
        numOutcomes = _numOutcomes;
        for (uint16 i = 0; i < _multipliers.length; i++) {
            slotsMultipliers[_outcomeNum[i]] = _multipliers[i];
        }
    }

    function _checkMaxWager(uint256 wager, address tokenAddress) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * 55770) / 100000000;
        require(wager <= maxWager, "Too many wager");
    }
}

