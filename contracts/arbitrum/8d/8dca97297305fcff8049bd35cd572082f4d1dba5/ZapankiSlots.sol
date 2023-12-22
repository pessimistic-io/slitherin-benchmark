// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ZapankiGames.sol";

contract ZapankiSlots is ZapankiGames {
    using SafeERC20 for IERC20;

    constructor(address _bankroll, address _vrf, address link_eth_feed) ZapankiGames(_vrf) {
        bankroll = IBankRoll(_bankroll);
        vrfCoordinator = IVRFCoordinatorV2(_vrf);
        LINK_ETH_FEED = AggregatorV3Interface(link_eth_feed);
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

    struct SlotsGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
    }

    mapping(address => SlotsGame) slotsGames;
    mapping(uint256 => address) slotsIDs;

    mapping(uint16 => uint16) slotsMultipliers;
    uint16 numOutcomes;

    /**
     * @dev event emitted at the start of the game
     * @param playerAddress address of the player that made the bet
     * @param wager wagered amount
     * @param tokenAddress address of token the wager was made, 0 address is considered the native coin
     * @param numBets number of bets the player intends to make
     * @param stopGain gain value at which the betting stop if a gain is reached
     * @param stopLoss loss value at which the betting stop if a loss is reached
     */
    event Slots_Play_Event(
        address indexed playerAddress,
        uint256 wager,
        address tokenAddress,
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
     * @param slotIDs slots result
     * @param multipliers multiplier of the slots result
     * @param payouts individual payouts for each bet
     * @param numGames number of games performed
     */
    event Slots_Outcome_Event(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint16[] slotIDs,
        uint256[] multipliers,
        uint256[] payouts,
        uint32 numGames
    );

    /**
     * @dev event emitted when a refund is done in slots
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event Slots_Refund_Event(address indexed player, uint256 wager, address tokenAddress);

    error AwaitingVRF(uint256 requestID);
    error InvalidNumBets(uint256 maxNumBets);
    error NotAwaitingVRF();
    error WagerAboveLimit(uint256 wager, uint256 maxWager);
    error BlockNumberTooLow(uint256 have, uint256 want);

    /**
     * @dev function to get current request player is await from VRF, returns 0 if none
     * @param player address of the player to get the state
     */
    function getCurrentUserState(address player) external view returns (SlotsGame memory) {
        return (slotsGames[player]);
    }

    /**
     * @dev function to view the current slots multipliers
     * @return  multipliers multipliers for all slots outcomes
     */
    function getMultipliers() external view returns (uint16[] memory multipliers) {
        multipliers = new uint16[](numOutcomes);
        for (uint16 i = 0; i < numOutcomes; i++) {
            multipliers[i] = slotsMultipliers[i];
        }
        return multipliers;
    }

    /**
     * @dev Function to play slots, takes the user wager saves bet parameters and makes a request to the VRF
     * @param wager wager amount
     * @param tokenAddress address of token to bet, 0 address is considered the native coin
     * @param numBets number of bets to make, and amount of random numbers to request
     * @param stopGain treshold value at which the bets stop if a certain profit is obtained
     * @param stopLoss treshold value at which the bets stop if a certain loss is obtained
     */

    function play(
        uint256 wager,
        address tokenAddress,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        address msgSender = msg.sender;

        if (slotsGames[msgSender].requestID != 0) {
            revert AwaitingVRF(slotsGames[msgSender].requestID);
        }
        if (!(numBets > 0 && numBets <= 100)) {
            revert InvalidNumBets(100);
        }

        _kellyWager(wager, tokenAddress);
        _transferWager(tokenAddress, wager * numBets, 800000, 24);
        uint256 id = _requestRandomWords(numBets);

        slotsGames[msgSender] = SlotsGame(wager, stopGain, stopLoss, id, tokenAddress, uint64(block.number), numBets);
        slotsIDs[id] = msgSender;
    }

    /**
     * @dev Function to refund user in case of VRF request failling
     */
    function refund() external nonReentrant {
        address msgSender = msg.sender;
        SlotsGame storage game = slotsGames[msgSender];
        if (game.requestID == 0) {
            revert NotAwaitingVRF();
        }
        if (game.blockNumber + 200 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 200);
        }

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        delete (slotsIDs[game.requestID]);
        delete (slotsGames[msgSender]);

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit Slots_Refund_Event(msgSender, wager, tokenAddress);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address playerAddress = slotsIDs[requestId];
        if (playerAddress == address(0)) revert();
        SlotsGame storage game = slotsGames[playerAddress];

        uint256 payout;
        int256 totalValue;
        uint32 i;
        uint16[] memory slotID = new uint16[](game.numBets);
        uint256[] memory multipliers = new uint256[](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        address tokenAddress = game.tokenAddress;

        for (i = 0; i < game.numBets; i++) {
            if (totalValue >= int256(game.stopGain)) {
                break;
            }
            if (totalValue <= -int256(game.stopLoss)) {
                break;
            }

            slotID[i] = uint16(randomWords[i] % numOutcomes);
            multipliers[i] = slotsMultipliers[slotID[i]];

            if (multipliers[i] != 0) {
                totalValue += int256(game.wager * multipliers[i]) - int256(game.wager);
                payout += game.wager * multipliers[i];
                payouts[i] = game.wager * multipliers[i];
            } else {
                totalValue -= int256(game.wager);
            }
        }

        payout += (game.numBets - i) * game.wager;

        emit Slots_Outcome_Event(playerAddress, game.wager, payout, tokenAddress, slotID, multipliers, payouts, i);
        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        delete (slotsIDs[requestId]);
        delete (slotsGames[playerAddress]);
        if (payout != 0) {
            _transferPayout(playerAddress, payout, tokenAddress);
        }
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

    /**
     * @dev calculates the maximum wager allowed based on the bankroll size
     */
    function _kellyWager(uint256 wager, address tokenAddress) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * 55770) / 100000000;
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }
}

