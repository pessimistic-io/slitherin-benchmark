// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ZapankiGames.sol";

/**
 * @title Coin Flip game, players predict if outcome will be heads or tails
 */

contract ZapankiCoinFlip is ZapankiGames {
    using SafeERC20 for IERC20;

    constructor(address _bankroll, address _vrf, address link_eth_feed) ZapankiGames(_vrf) {
        bankroll = IBankRoll(_bankroll);
        vrfCoordinator = IVRFCoordinatorV2(_vrf);
        LINK_ETH_FEED = AggregatorV3Interface(link_eth_feed);
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
    event CoinFlipFulfilled(
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
    event CoinFlipRefund(address indexed player, uint256 wager, address tokenAddress);

    error WagerAboveLimit(uint256 wager, uint256 maxWager);
    error AwaitingVRF(uint256 requestID);
    error InvalidNumBets(uint256 maxNumBets);
    error NotAwaitingVRF();
    error BlockNumberTooLow(uint256 have, uint256 want);

    /**
     * @dev function to get current request player is await from VRF, returns 0 if none
     * @param player address of the player to get the state
     */
    function getCurrentUserState(address player) external view returns (CoinFlipGame memory) {
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
    function flip(
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

        _kellyWager(wager, tokenAddress);
        _transferWager(tokenAddress, wager * numBets, 700000, 22);
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
    }

    /**
     * @dev Function to refund user in case of VRF request failling
     */
    function refund() external nonReentrant {
        CoinFlipGame storage game = coinFlipGames[msg.sender];
        if (game.requestID == 0) {
            revert NotAwaitingVRF();
        }
        if (game.blockNumber + 200 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 200);
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
        emit CoinFlipRefund(msg.sender, wager, tokenAddress);
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
        uint256 maxWager = (balance * 1122448) / 100000000;
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        address playerAddress = coinIDs[_requestId];
        if (playerAddress == address(0)) revert();
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

            coinFlip[i] = uint8(_randomWords[i] % 2);

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

        emit CoinFlipFulfilled(playerAddress, game.wager, payout, tokenAddress, coinFlip, payouts, i);
        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        delete (coinIDs[_requestId]);
        delete (coinFlipGames[playerAddress]);
        if (payout != 0) {
            _transferPayout(playerAddress, payout, tokenAddress);
        }
    }
}

