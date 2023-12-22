// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Common.sol";

/**
 * @title Dice game, players predict if outcome will be over or under the selected number
 */

contract Dice is Common {
    using SafeERC20 for IERC20;

    constructor(
        address _bankroll,
        address _vrf,
        address link_eth_feed,
        address _forwarder
    ) {
        Bankroll = IBankRoll(_bankroll);
        IChainLinkVRF = IVRFCoordinatorV2(_vrf);
        LINK_ETH_FEED = AggregatorV3Interface(link_eth_feed);
        ChainLinkVRF = _vrf;
        _trustedForwarder = _forwarder;
    }

    struct DiceGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        uint32 multiplier;
        bool isOver;
    }

    mapping(address => DiceGame) diceGames;
    mapping(uint256 => address) diceIDs;

    /**
     * @dev event emitted at the start of the game
     * @param playerAddress address of the player that made the bet
     * @param wager wagered amount
     * @param multiplier selected multiplier for the wager range 10421-9900000, multiplier values divide by 10000
     * @param tokenAddress address of token the wager was made, 0 address is considered the native coin
     * @param isOver if true dice outcome must be over the selected number, false must be under
     * @param numBets number of bets the player intends to make
     * @param stopGain gain value at which the betting stop if a gain is reached
     * @param stopLoss loss value at which the betting stop if a loss is reached
     */
    event Dice_Play_Event(
        address indexed playerAddress,
        uint256 wager,
        uint32 multiplier,
        address tokenAddress,
        bool isOver,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        uint256 VRFFee
    );

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param diceOutcomes results of dice roll, range 0-9999
     * @param payouts individual payouts for each bet
     * @param numGames number of games performed
     */
    event Dice_Outcome_Event(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint32 multiplier,
        uint256[] diceOutcomes,
        uint256[] payouts,
        uint32 numGames
    );

    /**
     * @dev event emitted when a refund is done in dice
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event Dice_Refund_Event(
        address indexed player,
        uint256 wager,
        address tokenAddress
    );

    error AwaitingVRF(uint256 requestID);
    error InvalidMultiplier(uint256 max, uint256 min, uint256 multiplier);
    error InvalidNumBets(uint256 maxNumBets);
    error WagerAboveLimit(uint256 wager, uint256 maxWager);
    error NotAwaitingVRF();
    error BlockNumberTooLow(uint256 have, uint256 want);
    error OnlyCoordinatorCanFulfill(address have, address want);

    /**
     * @dev function to get current request player is await from VRF, returns 0 if none
     * @param player address of the player to get the state
     */
    function Dice_GetState(
        address player
    ) external view returns (DiceGame memory) {
        return (diceGames[player]);
    }

    /**
     * @dev Function to play Dice, takes the user wager saves bet parameters and makes a request to the VRF
     * @param wager wager amount
     * @param tokenAddress address of token to bet, 0 address is considered the native coin
     * @param numBets number of bets to make, and amount of random numbers to request
     * @param stopGain treshold value at which the bets stop if a certain profit is obtained
     * @param stopLoss treshold value at which the bets stop if a certain loss is obtained
     * @param isOver if true dice outcome must be over the selected number, false must be under
     * @param multiplier selected multiplier for the wager range 10421-9900000, multiplier values divide by 10000
     */
    function Dice_Play(
        uint256 wager,
        uint32 multiplier,
        address tokenAddress,
        bool isOver,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        address msgSender = _msgSender();
        if (!(multiplier >= 10421 && multiplier <= 9900000)) {
            revert InvalidMultiplier(9900000, 10421, multiplier);
        }
        if (diceGames[msgSender].requestID != 0) {
            revert AwaitingVRF(diceGames[msgSender].requestID);
        }
        if (!(numBets > 0 && numBets <= 100)) {
            revert InvalidNumBets(100);
        }

        _kellyWager(wager, tokenAddress, multiplier);
        uint256 fee = _transferWager(
            tokenAddress,
            wager * numBets,
            700000,
            21,
            msgSender
        );

        uint256 id = _requestRandomWords(numBets);

        diceGames[msgSender] = DiceGame(
            wager,
            stopGain,
            stopLoss,
            id,
            tokenAddress,
            uint64(block.number),
            numBets,
            multiplier,
            isOver
        );
        diceIDs[id] = msgSender;

        emit Dice_Play_Event(
            msgSender,
            wager,
            multiplier,
            tokenAddress,
            isOver,
            numBets,
            stopGain,
            stopLoss,
            fee
        );
    }

    /**
     * @dev Function to refund user in case of VRF request failling
     */
    function Dice_Refund() external nonReentrant {
        address msgSender = _msgSender();
        DiceGame storage game = diceGames[msgSender];
        if (game.requestID == 0) {
            revert NotAwaitingVRF();
        }
        if (game.blockNumber + 200 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 200);
        }

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        delete (diceIDs[game.requestID]);
        delete (diceGames[msgSender]);

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit Dice_Refund_Event(msgSender, wager, tokenAddress);
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
        if (msg.sender != ChainLinkVRF) {
            revert OnlyCoordinatorCanFulfill(msg.sender, ChainLinkVRF);
        }
        fulfillRandomWords(requestId, randomWords);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal {
        address playerAddress = diceIDs[requestId];
        if (playerAddress == address(0)) revert();
        DiceGame storage game = diceGames[playerAddress];

        int256 totalValue;
        uint256 payout;
        uint32 i;
        uint256[] memory diceOutcomes = new uint256[](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        uint256 winChance = 99000000000 / game.multiplier;
        uint256 numberToRollOver = 10000000 - winChance;
        uint256 gamePayout = (game.multiplier * game.wager) / 10000;

        address tokenAddress = game.tokenAddress;

        for (i = 0; i < game.numBets; i++) {
            if (totalValue >= int256(game.stopGain)) {
                break;
            }
            if (totalValue <= -int256(game.stopLoss)) {
                break;
            }

            diceOutcomes[i] = randomWords[i] % 10000000;
            if (diceOutcomes[i] >= numberToRollOver && game.isOver == true) {
                totalValue += int256(gamePayout - game.wager);
                payout += gamePayout;
                payouts[i] = gamePayout;
                continue;
            }

            if (diceOutcomes[i] <= winChance && game.isOver == false) {
                totalValue += int256(gamePayout - game.wager);
                payout += gamePayout;
                payouts[i] = gamePayout;
                continue;
            }

            totalValue -= int256(game.wager);
        }

        payout += (game.numBets - i) * game.wager;

        emit Dice_Outcome_Event(
            playerAddress,
            game.wager,
            payout,
            tokenAddress,
            game.multiplier,
            diceOutcomes,
            payouts,
            i
        );
        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        delete (diceIDs[requestId]);
        delete (diceGames[playerAddress]);
        if (payout != 0) {
            _transferPayout(playerAddress, payout, tokenAddress);
        }
    }

    /**
     * @dev calculates the maximum wager allowed based on the bankroll size
     */
    function _kellyWager(
        uint256 wager,
        address tokenAddress,
        uint256 multiplier
    ) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(Bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(Bankroll));
        }
        uint256 maxWager = (balance * (11000 - 10890)) / (multiplier - 10000);
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }
}

