// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Common.sol";
import "./Interfaces.sol";
import "./AccessControl.sol";

/**
 * @title Dice game, players predict if outcome will be over or under the selected number
 */

contract Dice is Common, AccessControl, IDiceGame {
    using SafeERC20 for IERC20;
    IRouterWrapper public router;

    /**
     * @dev Constructor function
     * @param _bankroll Address of the bankroll contract
     * @param _vrf Address of the VRF contract
     * @param link_eth_feed Address of the LINK_ETH_FEED contract
     * @param _chainlinkKeyHash Chainlink key hash
     * @param _chainlinkSubId Chainlink subscription ID
     * @param _router Address of the router contract
     */
    constructor(
        address _bankroll,
        address _vrf,
        address link_eth_feed,
        bytes32 _chainlinkKeyHash,
        uint64 _chainlinkSubId,
        address _router
    ) {
        require(
            _bankroll != address(0) &&
                _vrf != address(0) &&
                link_eth_feed != address(0) &&
                _router != address(0),
            "Invalid address"
        );

        Bankroll = IBankRollFacet(_bankroll);
        IChainLinkVRF = VRFCoordinatorV2Interface(_vrf);
        LINK_ETH_FEED = AggregatorV3Interface(link_eth_feed);
        ChainLinkVRF = _vrf;
        chainlinkKeyHash = _chainlinkKeyHash;
        chainlinkSubId = _chainlinkSubId;
        router = IRouterWrapper(_router);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    mapping(address => DiceGame) diceGames;
    mapping(uint256 => address) diceIDs;
    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");

    /**
     * @dev function to get current request player is await from VRF, returns 0 if none
     * @param player address of the player to get the state
     */
    function getState(address player) external view returns (DiceGame memory) {
        require(player != address(0), "Invalid player address");
        return (diceGames[player]);
    }

    /**
     * @dev Function to calculate the maximum wager based on the Kelly Criterion
     * @param wager The amount of the wager
     * @param tokenAddress The address of the token used for the wager
     * @param multiplier selected multiplier for the wager range 10421-9900000, multiplier values divide by 10000
     */
    function _kellyWager(
        uint256 wager,
        address tokenAddress,
        uint256 multiplier
    ) internal view {
        uint256 balance = (tokenAddress == address(0))
            ? address(Bankroll).balance
            : IERC20(tokenAddress).balanceOf(address(Bankroll));
        uint256 maxWager = (balance * (11000 - 10890)) / (multiplier - 10000);
        require(wager <= maxWager, "Wager above limit");
    }

    /**
     * @dev calculates if the user bet is still awaiting VRF results
     * @param player The address of the player
     */
    function _isAwaitingVRF(address player) internal view {
        require(diceGames[player].requestID == 0, "Awaiting VRF");
    }

    /**
     * @dev Function to run initial checks before playing the Slots game
     * @param player The address of the player
     * @param tokenAddress The address of the token used for the wager
     */
    function runInitialChecks(
        address player,
        address tokenAddress,
        uint256 wager,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        uint32 multiplier
    ) external view override {
        require(wager > 0, "Wager must be greater than 0");
        require(player != address(0), "Invalid sender address");
        require(stopGain > 0, "StopGain must be greater than 0");
        require(stopLoss > 0, "StopLoss must be greater than 0");
        require(numBets > 0 && numBets <= 100, "Invalid numBets");
        require(
            Bankroll.getIsValidWager(address(this), tokenAddress),
            "Bankroll: Invalid wager"
        );
        bool suspended = Bankroll.isPlayerSuspended(player);
        require(!suspended, "Player is suspended");
        _kellyWager(wager, tokenAddress, multiplier);
        _isAwaitingVRF(player);
    }


    /**
     * @dev Function to play the dice game
     * @param wager The amount of the wager
     * @param tokenAddress The address of the token used for the wager
     * @param numBets The number of bets to play
     * @param stopGain The stop gain amount
     * @param stopLoss The stop loss amount
     * @param isOver if true dice outcome must be over the selected number, false must be under
     * @param multiplier selected multiplier for the wager range 10421-9900000, multiplier values divide by 10000
     * @param msgSender The address of the player
     * @param betId The ID of the bet
     * @return id The ID of the game
     */
    function play(
        uint256 wager,
        address tokenAddress,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss,
        bool isOver,
        uint32 multiplier,
        address msgSender,
        uint256 betId
    )
        external
        payable
        override
        onlyRole(ROUTER_ROLE)
        nonReentrant
        returns (uint256 id)
    {
        id = _requestRandomWords(numBets);

        diceGames[msgSender] = DiceGame(
            wager,
            stopGain,
            stopLoss,
            id,
            tokenAddress,
            uint64(block.number),
            numBets,
            multiplier,
            isOver,
            betId
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
            betId
        );
    }

    /**
     * @dev Refund the wager for the game
     * @param msgSender The address of the player
     */
    function refund(
        address msgSender
    ) external onlyRole(ROUTER_ROLE) nonReentrant {
        require(msgSender != address(0), "Invalid sender address");
        DiceGame storage game = diceGames[msgSender];
        require(game.requestID != 0, "Not awaiting VRF");
        require(game.blockNumber + 200 < block.number, "Block number too low");

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        // Refund the wager to the player
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msgSender).call{value: wager}("");
            require(success, "Transfer failed");
        } else {
            IERC20(tokenAddress).safeTransfer(msgSender, wager);
        }

        delete (diceIDs[game.requestID]);
        delete (diceGames[msgSender]);

        // Emit refund event
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
        require(msg.sender == ChainLinkVRF, "Only coordinator can fulfill");
        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @dev Fulfill the random words for a dice game
     * @param requestId The ID of the request
     * @param randomWords The array of random words
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal {
        address playerAddress = diceIDs[requestId];
        require(playerAddress != address(0), "Invalid requestId");

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
        uint256 betId = game.betId;

        router.updatePayout(betId, payout);
        emit Dice_Outcome_Event(
            playerAddress,
            payout,
            tokenAddress,
            diceOutcomes,
            payouts,
            i,
            betId
        );
        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        delete (diceIDs[requestId]);
        delete (diceGames[playerAddress]);
        if (payout != 0) {
            _transferPayout(playerAddress, payout, tokenAddress);
        }
    }
}

