// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Common.sol";

/**
 * @title Coin Flip game, players predict if outcome will be heads or tails
 */
contract CoinFlip is Common {
    using SafeERC20 for IERC20;

    constructor(address _bankroll, address _vrf) {
        Bankroll = IBankRoll(_bankroll);
        randomizer = _vrf;
    }

    struct CoinFlipGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        bool isHeads;
    }

    struct VRFData {
        uint256 id;
        uint256 feePayed;
    }

    mapping(address => VRFData) vrfdata;
    mapping(address => CoinFlipGame) coinFlipGames;
    mapping(uint256 => address) coinIDs;

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param coinOutcomes results of coinFlip, 1-> Heads, 0 ->Tails
     * @param payouts individual payouts for each bet
     * @param numGames number of games performed
     */
    event CoinFlip_Outcome_Event(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint8[] coinOutcomes,
        uint256[] payouts,
        uint32 numGames
    );

    /**
     * @dev event emitted when a refund is done in coin flip
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event CoinFlip_Refund_Event(
        address indexed player,
        uint256 wager,
        address tokenAddress
    );

    error AwaitingVRF(uint256 requestID);
    error InvalidNumBets(uint256 maxNumBets);
    error WagerAboveLimit(uint256 wager, uint256 maxWager);
    error NotAwaitingVRF();
    error BlockNumberTooLow(uint256 have, uint256 want);

    /**
     * @dev function to get current request player is await from VRF, returns 0 if none
     * @param player address of the player to get the state
     */
    function CoinFlip_GetState(
        address player
    ) external view returns (CoinFlipGame memory) {
        return (coinFlipGames[player]);
    }

    /**
     * @dev Function to play Coin Flip, takes the user wager saves bet parameters and makes a request to the VRF
     * @param wager wager amount
     * @param tokenAddress address of token to bet, 0 address is considered the native coin
     * @param numBets number of bets to make, and amount of random numbers to request
     * @param stopGain treshold value at which the bets stop if a certain profit is obtained
     * @param stopLoss treshold value at which the bets stop if a certain loss is obtained
     * @param isHeads if bet selected heads or Tails
     */

    function CoinFlip_Play(
        uint256 wager,
        address tokenAddress,
        bool isHeads,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        if (coinFlipGames[msg.sender].requestID != 0) {
            revert AwaitingVRF(coinFlipGames[msg.sender].requestID);
        }
        if (!(numBets > 0 && numBets <= 100)) {
            revert InvalidNumBets(100);
        }
        VRFData storage data = vrfdata[msg.sender];
        (, , uint256 ethPaid, uint256 ethRefunded, ) = IRandomizer(randomizer)
            .getRequest(data.id);
        if (data.feePayed > ethPaid - ethRefunded) {
            IRandomizer(randomizer).clientWithdrawTo(
                msg.sender,
                ((data.feePayed - (ethPaid - ethRefunded)) * 90) / 100
            );
        }

        _kellyWager(wager, tokenAddress);
        uint256 feePayed = _transferWager(tokenAddress, wager * numBets);
        uint256 id = _requestRandomWords(numBets);

        coinFlipGames[msg.sender] = CoinFlipGame(
            wager,
            stopGain,
            stopLoss,
            id,
            tokenAddress,
            uint64(block.number),
            numBets,
            isHeads
        );
        coinIDs[id] = msg.sender;
        vrfdata[msg.sender] = VRFData(id, feePayed);
    }

    /**
     * @dev Function to refund player in case of VRF request failling
     */

    function CoinFlip_Refund() external nonReentrant {
        CoinFlipGame storage game = coinFlipGames[msg.sender];
        if (game.requestID == 0) {
            revert NotAwaitingVRF();
        }
        if (game.blockNumber + 1500 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 1500);
        }

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        delete (coinIDs[game.requestID]);
        delete (coinFlipGames[msg.sender]);

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: wager}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, wager);
        }
        emit CoinFlip_Refund_Event(msg.sender, wager, tokenAddress);
    }

    error OnlyRandomizerCanFulfill(address have, address want);

    /**
     * @dev function called by Randomizer.ai with the random number
     * @param _id id provided when the request was made
     * @param _value random number
     */

    function randomizerCallback(uint256 _id, bytes32 _value) external {
        //Callback can only be called by randomizer
        if (msg.sender != randomizer) {
            revert OnlyRandomizerCanFulfill(msg.sender, randomizer);
        }
        address playerAddress = coinIDs[_id];
        CoinFlipGame storage game = coinFlipGames[playerAddress];

        int256 totalValue;
        uint256 payout;
        uint32 i;
        uint8[] memory coinFlip = new uint8[](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        address tokenAddress = game.tokenAddress;

        for (i = 0; i < game.numBets; i++) {
            if (totalValue >= int256(game.stopGain)) {
                break;
            }
            if (totalValue <= -int256(game.stopLoss)) {
                break;
            }

            coinFlip[i] = uint8(
                uint256(keccak256(abi.encodePacked(_value, i))) % 2
            );

            if (coinFlip[i] == 1 && game.isHeads == true) {
                totalValue += int256((game.wager * 9800) / 10000);
                payout += (game.wager * 19800) / 10000;
                payouts[i] = (game.wager * 19800) / 10000;
                continue;
            }
            if (coinFlip[i] == 0 && game.isHeads == false) {
                totalValue += int256((game.wager * 9800) / 10000);
                payout += (game.wager * 19800) / 10000;
                payouts[i] = (game.wager * 19800) / 10000;
                continue;
            }

            totalValue -= int256(game.wager);
        }

        payout += (game.numBets - i) * game.wager;

        emit CoinFlip_Outcome_Event(
            playerAddress,
            game.wager,
            payout,
            tokenAddress,
            coinFlip,
            payouts,
            i
        );
        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        delete (coinIDs[_id]);
        delete (coinFlipGames[playerAddress]);
        if (payout != 0) {
            _transferPayout(playerAddress, payout, tokenAddress);
        }
    }

    /**
     * @dev calculates the maximum wager allowed based on the bankroll size
     */
    function _kellyWager(uint256 wager, address tokenAddress) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(Bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(Bankroll));
        }
        uint256 maxWager = (balance * 1122448) / 100000000;
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }
}

