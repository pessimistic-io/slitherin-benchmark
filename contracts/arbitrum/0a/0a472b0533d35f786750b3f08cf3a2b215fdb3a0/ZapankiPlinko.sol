// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ZapankiGames.sol";

/**
 * @title plinko game, players select a number of rows and risk and get payouts depending on the final position of the ball
 */
contract ZapankiPlinko is ZapankiGames {
    using SafeERC20 for IERC20;

    constructor(address _bankroll, address _vrf, address link_eth_feed) ZapankiGames(_vrf) {
        bankroll = IBankRoll(_bankroll);
        vrfCoordinator = IVRFCoordinatorV2(_vrf);
        LINK_ETH_FEED = AggregatorV3Interface(link_eth_feed);
        kellyFractions[0] = [573159, 240816, 372158, 267835, 453230, 480140, 327817, 384356, 467936];
        kellyFractions[1] = [108157, 100164, 100856, 82065, 91981, 83772, 68092, 69475, 100288];
        kellyFractions[2] = [31369, 25998, 38394, 27787, 29334, 29004, 22764, 21439, 27190];
    }

    struct PlinkoGame {
        uint256 wager;
        uint256 stopGain;
        uint256 stopLoss;
        uint256 requestID;
        address tokenAddress;
        uint64 blockNumber;
        uint32 numBets;
        uint8 risk;
        uint8 numRows;
    }

    mapping(address => PlinkoGame) plinkoGames;
    mapping(uint256 => address) plinkoIDs;
    mapping(uint8 => mapping(uint8 => mapping(uint8 => uint256))) plinkoMultipliers;
    mapping(uint8 => mapping(uint8 => bool)) isMultiplierSet;
    uint256[9][3] kellyFractions;

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param paths direction taken by the plinko ball at each row, true-> right, false->left
     * @param risk risk selected by player
     * @param payouts individual payouts for each bet
     * @param numGames number of games performed
     */
    event PlinkoFulfilled(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        bool[][] paths,
        uint8 risk,
        uint256[] payouts,
        uint32 numGames
    );

    /**
     * @dev event emitted when a refund is done in plinko
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event PlinkoRefund(address indexed player, uint256 wager, address tokenAddress);

    error AwaitingVRF(uint256 requestID);
    error InvalidNumRows();
    error InvalidRisk();
    error InvalidNumBets(uint256 maxNumBets);
    error WagerAboveLimit(uint256 wager, uint256 maxWager);
    error NotAwaitingVRF();
    error BlockNumberTooLow(uint256 have, uint256 want);
    error MismatchedLength(uint256 multipliers, uint256 outcome);
    error MultiplierAlreadySet(uint8 numRows, uint8 risk);
    error InvalidNumberToSet();

    /**
     * @dev function to get current request player is await from VRF, returns 0 if none
     * @param player address of the player to get the state
     */
    function getCurrentUserState(address player) external view returns (PlinkoGame memory) {
        return (plinkoGames[player]);
    }

    /**
     * @dev function to view the current plinko multipliers
     * @return multipliers all multipliers for all rows and risks
     */
    function getMultipliers() external view returns (uint256[17][9][3] memory multipliers) {
        for (uint8 r = 0; r < 3; r++) {
            for (uint8 g = 0; g < 9; g++) {
                for (uint8 i = 0; i < 17; i++) {
                    multipliers[r][g][i] = plinkoMultipliers[r][g + 8][i];
                }
            }
        }
        return multipliers;
    }

    /**
     * @dev Function to play Plinko, takes the user wager saves bet parameters and makes a request to the VRF
     * @param wager wager amount
     * @param tokenAddress address of token to bet, 0 address is considered the native coin
     * @param numBets number of bets to make, and amount of random numbers to request
     * @param stopGain treshold value at which the bets stop if a certain profit is obtained
     * @param stopLoss treshold value at which the bets stop if a certain loss is obtained
     * @param numRows number of Rows that plinko will have, range 8-16
     * @param risk risk for game, higher risk increases variance, range 0-2
     */
    function play(
        uint256 wager,
        address tokenAddress,
        uint8 numRows,
        uint8 risk,
        uint32 numBets,
        uint256 stopGain,
        uint256 stopLoss
    ) external payable nonReentrant {
        if (numRows < 8 || numRows > 16) {
            revert InvalidNumRows();
        }
        if (risk >= 3) {
            revert InvalidRisk();
        }
        if (plinkoGames[msg.sender].requestID != 0) {
            revert AwaitingVRF(plinkoGames[msg.sender].requestID);
        }
        if (!(numBets > 0 && numBets <= 60)) {
            revert InvalidNumBets(60);
        }

        _kellyWager(wager, tokenAddress, numRows, risk);
        _transferWager(tokenAddress,
            wager * numBets,
            1500000,
            21);
        uint256 id = _requestRandomWords(numBets);

        plinkoGames[msg.sender] = PlinkoGame(
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
        plinkoIDs[id] = msg.sender;
    }

    /**
     * @dev Function to refund user in case of VRF request failling
     */
    function refund() external nonReentrant {
        PlinkoGame storage game = plinkoGames[msg.sender];
        if (game.requestID == 0) {
            revert NotAwaitingVRF();
        }
        if (game.blockNumber + 200 > block.number) {
            revert BlockNumberTooLow(block.number, game.blockNumber + 200);
        }

        uint256 wager = game.wager * game.numBets;
        address tokenAddress = game.tokenAddress;

        delete (plinkoIDs[game.requestID]);
        delete (plinkoGames[msg.sender]);

        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: wager}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, wager);
        }
        emit PlinkoRefund(msg.sender, wager, tokenAddress);
    }

    /**
     * @dev function to set the plinko multipliers, can only be called by bankroll owner
     * @param multipliers array of all multipliers for the selected number of rows and risk
     * @param numRows number of rows to set multiplier
     * @param risk risk to set multiplier
     */
    function setPlinkoMultipliers(uint256[] calldata multipliers, uint8 numRows, uint8 risk) external {
        if (msg.sender != bankroll.getOwner()) {
            revert NotOwner(bankroll.getOwner(), msg.sender);
        }
        if (isMultiplierSet[risk][numRows]) {
            revert MultiplierAlreadySet(numRows, risk);
        }

        if (multipliers.length != numRows + 1) {
            revert MismatchedLength(multipliers.length, numRows + 1);
        }
        if (numRows < 8 || numRows > 16) {
            revert InvalidNumRows();
        }
        if (risk >= 3) {
            revert InvalidRisk();
        }

        for (uint8 i = 0; i < multipliers.length; i++) {
            plinkoMultipliers[risk][numRows][i] = multipliers[i];
        }
        isMultiplierSet[risk][numRows] = true;
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        address playerAddress = plinkoIDs[_requestId];
        if (playerAddress == address(0)) revert();
        PlinkoGame storage game = plinkoGames[playerAddress];

        bool[][] memory gamesResults = new bool[][](game.numBets);
        uint256[] memory payouts = new uint256[](game.numBets);

        int256 totalValue;
        uint256 payout;
        uint32 i;
        uint256 multiplier;

        address tokenAddress = game.tokenAddress;

        for (i = 0; i < game.numBets; i++) {
            if (totalValue >= int256(game.stopGain)) {
                break;
            }
            if (totalValue <= -int256(game.stopLoss)) {
                break;
            }

            (multiplier, gamesResults[i]) = _plinkoGame(_randomWords[i], game.numRows, game.risk);

            payouts[i] = (game.wager * multiplier) / 100;
            payout += payouts[i];
            totalValue += int256(payouts[i]) - int256(game.wager);
        }

        payout += (game.numBets - i) * game.wager;

        emit PlinkoFulfilled(playerAddress, game.wager, payout, tokenAddress, gamesResults, game.risk, payouts, i);
        _transferToBankroll(tokenAddress, game.wager * game.numBets);
        delete (plinkoIDs[_requestId]);
        delete (plinkoGames[playerAddress]);
        if (payout != 0) {
            _transferPayout(playerAddress, payout, tokenAddress);
        }
    }

    /**
     * @dev function to get result of individual plinko game
     * @param randomWords rng to determine the result
     * @param numRows number of rows of game
     * @param risk risk level selected
     */
    function _plinkoGame(
        uint256 randomWords,
        uint8 numRows,
        uint8 risk
    ) internal view returns (uint256 multiplier, bool[] memory currentGameResult) {
        currentGameResult = new bool[](numRows);
        int8 ended = 0;
        for (uint8 g = 0; g < numRows; g++) {
            currentGameResult[g] = _getBitValue(randomWords, g);
            if (currentGameResult[g]) {
                ended += 1;
            } else {
                ended -= 1;
            }
        }
        uint8 multiplierSlot = uint8(ended + int8(numRows)) >> 1;
        multiplier = plinkoMultipliers[risk][numRows][multiplierSlot];
    }

    function _getBitValue(uint256 four_nibbles, uint256 index) internal pure returns (bool) {
        return (four_nibbles & (1 << index)) != 0;
    }

    /**
     * @dev calculates the maximum wager allowed based on the bankroll size
     */
    function _kellyWager(uint256 wager, address tokenAddress, uint8 numRows, uint8 risk) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * kellyFractions[risk][numRows - 8]) / 100000000;
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }
}

