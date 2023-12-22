// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Common.sol";

/**
 * @title video poker game, players get dealt a 5 card hand and can replace any number of cards to form winning combinations
 */

contract VideoPoker is Common {
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

        for (uint8 s = 0; s < 4; s++) {
            for (uint8 n = 1; n < 14; n++) {
                initialDeck.push(Card(n, s));
            }
        }
    }

    struct Card {
        uint8 number;
        uint8 suit;
    }

    struct VideoPokerGame {
        uint256 wager;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        Card[5] cardsInHand;
        bool[5] toReplace;
        bool ingame;
        bool isFirstRequest;
    }

    Card[] initialDeck;
    mapping(address => VideoPokerGame) videoPokerGames;
    mapping(uint256 => address) videoPokerIDs;

    event VideoPoker_Play_Event(
        address indexed playerAddress,
        uint256 wager,
        address tokenAddress,
        uint256 VRFFee
    );
    /**
     * @dev event emitted by the VRF callback with the intial 5 card hand
     * @param playerAddress address of the player that made the bet
     * @param playerHand initial player Hand
     */
    event VideoPoker_Start_Event(
        address indexed playerAddress,
        Card[5] playerHand
    );

    event VideoPoker_Fee_Event(address indexed playerAddress, uint256 VRFFee);

    /**
     * @dev event emitted by the VRF callback with the final results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param playerHand final player Hand
     * @param outcome result of final hand, 0-> no winning combination
     */
    event VideoPoker_Outcome_Event(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        Card[5] playerHand,
        uint256 outcome
    );

    /**
     * @dev event emitted when a refund is done in video poker
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event VideoPoker_Refund_Event(
        address indexed player,
        uint256 wager,
        address tokenAddress
    );

    error AlreadyInGame();
    error NotInGame();
    error AwaitingVRF(uint256 requestID);
    error NoFeeRequired();
    error NoRequestPending();
    error BlockNumberTooLow(uint256 have, uint256 want);
    error OnlyCoordinatorCanFulfill(address have, address want);
    error WagerAboveLimit(uint256 wager, uint256 maxWager);

    /**
     * @dev Function to get current state of video Poker
     * @param player address of player to view game state
     * @return videopokerState current state of game of the player
     */
    function VideoPoker_GetState(
        address player
    ) external view returns (VideoPokerGame memory videopokerState) {
        videopokerState = videoPokerGames[player];
        return videopokerState;
    }

    /**
     * @dev Function to start Video poker, takes the user wager saves bet parameters and makes a request to the VRF
     * @param wager wager amount
     * @param tokenAddress address of token to bet, 0 address is considered the native coin
     */
    function VideoPoker_Start(
        uint256 wager,
        address tokenAddress
    ) external payable nonReentrant {
        address msgSender = _msgSender();

        VideoPokerGame storage game = videoPokerGames[msgSender];
        if (game.requestID != 0) {
            revert AwaitingVRF(game.requestID);
        }
        if (game.ingame) {
            revert AlreadyInGame();
        }

        _kellyWager(wager, tokenAddress);
        uint256 fee = _transferWager(
            tokenAddress,
            wager,
            500000,
            36,
            msgSender
        );
        uint256 id = _requestRandomWords(5);

        videoPokerIDs[id] = msgSender;
        game.tokenAddress = tokenAddress;
        game.wager = wager;
        game.isFirstRequest = true;
        game.requestID = id;
        game.blockNumber = uint64(block.number);
        game.ingame = true;

        emit VideoPoker_Play_Event(msgSender, wager, tokenAddress, fee);
    }

    /**
     * @dev Function to replace cards in player hand, if no cards to replace are selected there isn't a VRF request
     * @param toReplace array of cards that the player whished to replace, true equals that the card will be replaced
     */
    function VideoPoker_Replace(
        bool[5] calldata toReplace
    ) external payable nonReentrant {
        address msgSender = _msgSender();
        VideoPokerGame storage game = videoPokerGames[msgSender];
        if (!game.ingame) {
            revert NotInGame();
        }
        if (game.requestID != 0) {
            revert AwaitingVRF(game.requestID);
        }

        bool replaceCards;
        for (uint8 i = 0; i < 5; i++) {
            if (toReplace[i]) {
                replaceCards = true;
                break;
            }
        }

        if (replaceCards) {
            uint256 VRFFee = _payVRFFee(500000, 26);
            uint256 id = _requestRandomWords(5);
            videoPokerIDs[id] = msgSender;
            game.toReplace = toReplace;
            game.requestID = id;
            game.blockNumber = uint64(block.number);
            emit VideoPoker_Fee_Event(msgSender, VRFFee);
        } else {
            if (msg.value != 0) {
                revert NoFeeRequired();
            }
            (uint256 multiplier, uint256 outcome) = _determineHandPayout(
                game.cardsInHand
            );

            address tokenAddress = game.tokenAddress;
            uint256 wager = game.wager;
            emit VideoPoker_Outcome_Event(
                msgSender,
                wager,
                multiplier * wager,
                tokenAddress,
                game.cardsInHand,
                outcome
            );
            _transferToBankroll(tokenAddress, game.wager);
            delete (videoPokerGames[msgSender]);
            if (multiplier != 0) {
                _transferPayout(msgSender, multiplier * wager, tokenAddress);
            }
        }
    }

    /**
     * @dev Function to get refund for game if VRF request fails
     */
    function VideoPoker_Refund() external nonReentrant {
        address msgSender = _msgSender();
        VideoPokerGame storage game = videoPokerGames[msgSender];
        if (!game.ingame) {
            revert NotInGame();
        }
        if (game.requestID == 0) {
            revert NoRequestPending();
        }
        if (game.blockNumber + 200 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 200);
        }

        uint256 wager = game.wager;
        address tokenAddress = game.tokenAddress;
        delete (videoPokerGames[msgSender]);
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }
        emit VideoPoker_Refund_Event(msgSender, wager, tokenAddress);
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
        address player = videoPokerIDs[requestId];
        if (player == address(0)) revert();
        delete (videoPokerIDs[requestId]);
        VideoPokerGame storage game = videoPokerGames[player];

        if (game.isFirstRequest) {
            Card[] memory deck = initialDeck;

            for (uint8 i = 0; i < 5; i++) {
                _pickCard(i, randomWords[i], player, deck);
            }

            game.requestID = 0;
            game.isFirstRequest = false;
            emit VideoPoker_Start_Event(player, game.cardsInHand);
        } else {
            Card[] memory deck = initialDeck;

            for (uint256 g = 0; g < 5; g++) {
                for (uint256 j = 0; j < 52; j++) {
                    if (
                        game.cardsInHand[g].number == deck[j].number &&
                        game.cardsInHand[g].suit == deck[j].suit
                    ) {
                        deck[j] = deck[deck.length - 1];
                        assembly {
                            mstore(deck, sub(mload(deck), 1))
                        }
                        break;
                    }
                }
            }

            for (uint8 i = 0; i < 5; i++) {
                if (game.toReplace[i]) {
                    _pickCard(i, randomWords[i], player, deck);
                }
            }

            uint256 wager = game.wager;
            address tokenAddress = game.tokenAddress;
            (uint256 multiplier, uint256 outcome) = _determineHandPayout(
                game.cardsInHand
            );
            emit VideoPoker_Outcome_Event(
                player,
                wager,
                wager * multiplier,
                tokenAddress,
                game.cardsInHand,
                outcome
            );
            _transferToBankroll(tokenAddress, game.wager);
            delete (videoPokerGames[player]);
            _transferPayout(player, wager * multiplier, tokenAddress);
        }
    }

    function _pickCard(
        uint8 handPosition,
        uint256 rng,
        address player,
        Card[] memory deck
    ) internal {
        uint256 cardPosition = rng % deck.length;
        videoPokerGames[player].cardsInHand[handPosition] = deck[cardPosition];
        _removeCardFromDeck(cardPosition, deck);
    }

    function _removeCardFromDeck(
        uint256 cardPositon,
        Card[] memory deck
    ) internal pure {
        deck[cardPositon] = deck[deck.length - 1];
        assembly {
            mstore(deck, sub(mload(deck), 1))
        }
    }

    function _determineHandPayout(
        Card[5] memory cardsInHand
    ) public pure returns (uint256, uint256) {
        Card[5] memory sortedCards = _sort(cardsInHand);

        //check 4 of a kind
        if (
            sortedCards[1].number == sortedCards[2].number &&
            sortedCards[2].number == sortedCards[3].number
        ) {
            if (
                sortedCards[1].number == sortedCards[0].number ||
                sortedCards[3].number == sortedCards[4].number
            ) {
                return (30, 7);
            }
        }
        //check full house -> 3 of a kind + pair
        if (
            sortedCards[1].number == sortedCards[0].number &&
            sortedCards[4].number == sortedCards[3].number
        ) {
            if (
                sortedCards[1].number == sortedCards[2].number ||
                sortedCards[3].number == sortedCards[2].number
            ) {
                return (8, 6);
            }
        }
        //check royal flush + straight flush + flush
        if (
            sortedCards[0].suit == sortedCards[1].suit &&
            sortedCards[2].suit == sortedCards[3].suit &&
            sortedCards[0].suit == sortedCards[4].suit &&
            sortedCards[2].suit == sortedCards[1].suit
        ) {
            if (sortedCards[0].number == 1 && sortedCards[4].number == 13) {
                if (
                    sortedCards[2].number == sortedCards[3].number - 1 &&
                    sortedCards[3].number == sortedCards[4].number - 1 &&
                    sortedCards[1].number == sortedCards[2].number - 1
                ) {
                    return (100, 9);
                }
            }
            if (sortedCards[0].number == 1 && sortedCards[1].number == 2) {
                if (
                    sortedCards[0].number == sortedCards[1].number - 1 &&
                    sortedCards[2].number == sortedCards[3].number - 1 &&
                    sortedCards[3].number == sortedCards[4].number - 1 &&
                    sortedCards[1].number == sortedCards[2].number - 1
                ) {
                    return (50, 8);
                }
            }
            if (
                sortedCards[0].number == sortedCards[1].number - 1 &&
                sortedCards[2].number == sortedCards[3].number - 1 &&
                sortedCards[3].number == sortedCards[4].number - 1 &&
                sortedCards[1].number == sortedCards[2].number - 1
            ) {
                return (50, 8);
            }
            return (6, 5);
        }

        //check straight
        if (sortedCards[0].number == 1 && sortedCards[1].number == 2) {
            if (
                sortedCards[0].number == sortedCards[1].number - 1 &&
                sortedCards[2].number == sortedCards[3].number - 1 &&
                sortedCards[3].number == sortedCards[4].number - 1 &&
                sortedCards[1].number == sortedCards[2].number - 1
            ) {
                return (5, 4);
            }
        }
        if (sortedCards[0].number == 1 && sortedCards[4].number == 13) {
            if (
                sortedCards[2].number == sortedCards[3].number - 1 &&
                sortedCards[3].number == sortedCards[4].number - 1 &&
                sortedCards[1].number == sortedCards[2].number - 1
            ) {
                return (5, 4);
            }
        }
        if (
            sortedCards[0].number == sortedCards[1].number - 1 &&
            sortedCards[1].number == sortedCards[2].number - 1 &&
            sortedCards[2].number == sortedCards[3].number - 1 &&
            sortedCards[3].number == sortedCards[4].number - 1
        ) {
            return (5, 4);
        }
        //check three of a kind
        if (
            sortedCards[0].number == sortedCards[1].number &&
            sortedCards[1].number == sortedCards[2].number
        ) {
            return (3, 3);
        }
        if (
            sortedCards[1].number == sortedCards[2].number &&
            sortedCards[2].number == sortedCards[3].number
        ) {
            return (3, 3);
        }
        if (
            sortedCards[2].number == sortedCards[3].number &&
            sortedCards[3].number == sortedCards[4].number
        ) {
            return (3, 3);
        }
        //check two pair
        if (sortedCards[0].number == sortedCards[1].number) {
            if (
                sortedCards[2].number == sortedCards[3].number ||
                sortedCards[3].number == sortedCards[4].number
            ) {
                return (2, 2);
            }
        }

        if (sortedCards[1].number == sortedCards[2].number) {
            if (sortedCards[3].number == sortedCards[4].number) {
                return (2, 2);
            }
        }
        //check one pair jacks or higher
        if (sortedCards[0].number == sortedCards[1].number) {
            if (sortedCards[0].number > 10 || sortedCards[0].number == 1) {
                return (1, 1);
            }
        }
        if (sortedCards[1].number == sortedCards[2].number) {
            if (sortedCards[1].number > 10 || sortedCards[1].number == 1) {
                return (1, 1);
            }
        }
        if (sortedCards[2].number == sortedCards[3].number) {
            if (sortedCards[2].number > 10 || sortedCards[2].number == 1) {
                return (1, 1);
            }
        }
        if (sortedCards[3].number == sortedCards[4].number) {
            if (sortedCards[3].number > 10 || sortedCards[3].number == 1) {
                return (1, 1);
            }
        }

        return (0, 0);
    }

    function _quickSort(
        Card[5] memory arr,
        int256 left,
        int256 right
    ) internal pure {
        int256 i = left;
        int256 j = right;
        if (i == j) return;
        uint256 pivot = arr[uint256(left + (right - left) / 2)].number;
        while (i <= j) {
            while (arr[uint256(i)].number < pivot) i++;
            while (pivot < arr[uint256(j)].number) j--;
            if (i <= j) {
                (arr[uint256(i)].number, arr[uint256(j)].number) = (
                    arr[uint256(j)].number,
                    arr[uint256(i)].number
                );
                (arr[uint256(i)].suit, arr[uint256(j)].suit) = (
                    arr[uint256(j)].suit,
                    arr[uint256(i)].suit
                );
                i++;
                j--;
            }
        }
        if (left < j) {
            _quickSort(arr, left, j);
        }
        if (i < right) {
            _quickSort(arr, i, right);
        }
    }

    function _sort(Card[5] memory data) internal pure returns (Card[5] memory) {
        _quickSort(data, int256(0), int256(data.length - 1));
        return data;
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
        uint256 maxWager = (balance * 133937) / 100000000;
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }
}

