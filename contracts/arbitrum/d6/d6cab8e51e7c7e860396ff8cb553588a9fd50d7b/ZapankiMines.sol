// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ZapankiGames.sol";

/**
 * @title Mines game, player have 25 tiles where mines are hidden, players flip tiles until they cashout or reveal a mine in which case they lose
 */
contract ZapankiMines is ZapankiGames {
    using SafeERC20 for IERC20;

    constructor(address _bankroll, address _vrf, address link_eth_feed, uint8[24] memory maxReveal) ZapankiGames(_vrf) {
        bankroll = IBankRoll(_bankroll);
        vrfCoordinator = IVRFCoordinatorV2(_vrf);
        LINK_ETH_FEED = AggregatorV3Interface(link_eth_feed);
        _setMaxReveal(maxReveal);
    }

    struct MinesGame {
        address tokenAddress;
        uint256 wager;
        uint256 requestID;
        uint64 blockNumber;
        uint64 currentMultiplier;
        uint8 numMines;
        bool[25] revealedTiles;
        bool[25] tilesPicked;
        bool isCashout;
    }

    mapping(address => MinesGame) minesGames;
    mapping(uint256 => address) minesIDs;
    mapping(uint256 => mapping(uint256 => uint256)) minesMultipliers;
    mapping(uint256 => uint256) minesMaxReveal;

    /**
     * @dev event emitted by the VRF callback with the tile reveal results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout payout if player were to end the game
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param minesTiles tiles in which mines were revealed, if any is true the game is over and the player lost
     * @param revealedTiles all tiles that have been revealed, true correspond to a revealed tile
     * @param multiplier current game multiplier if the game player chooses to end the game
     */
    event MinesReveal(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        bool[25] minesTiles,
        bool[25] revealedTiles,
        uint256 multiplier
    );

    /**
     * @dev event emitted by the VRF callback with the tile reveal results and cashout
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param minesTiles tiles in which mines were revealed, if any is true the game is over and the player lost
     * @param revealedTiles all tiles that have been revealed, true correspond to a revealed tile
     * @param multiplier current game multiplier
     */
    event MinesRevealCashout(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        bool[25] minesTiles,
        bool[25] revealedTiles,
        uint256 multiplier
    );

    /**
     * @dev event emitted by the VRF callback with the bet results
     * @param playerAddress address of the player that made the bet
     * @param wager wager amount
     * @param payout total payout transfered to the player
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param multiplier final game multiplier
     */
    event MinesEnd(
        address indexed playerAddress,
        uint256 wager,
        uint256 payout,
        address tokenAddress,
        uint256 multiplier
    );

    /**
     * @dev event emitted when a refund is done in mines
     * @param player address of the player reciving the refund
     * @param wager amount of wager that was refunded
     * @param tokenAddress address of token the refund was made in
     */
    event Mines_Refund_Event(address indexed player, uint256 wager, address tokenAddress);

    error InvalidNumMines();
    error AlreadyInGame();
    error NotInGame();
    error AwaitingVRF(uint256 requestID);
    error InvalidNumberToReveal(uint32 numberPicked, uint256 maxAllowed);
    error TileAlreadyRevealed(uint8 position);
    error WagerAboveLimit(uint256 wager, uint256 maxWager);
    error NoRequestPending();
    error BlockNumberTooLow(uint256 have, uint256 want);

    /**
     * @dev function to view the current mines multipliers
     * @param numMines number of mines in the game
     * @param numRevealed tiles revealed
     * @return multiplier multiplier of selected numMines and numRevealed
     */
    function getMultipliers(uint256 numMines, uint256 numRevealed) public view returns (uint256 multiplier) {
        multiplier = minesMultipliers[numMines][numRevealed];
        return multiplier;
    }

    /**
     * @dev function to view the max number of tiles to reveal in mines
     * @return maxReveal array with max number of tiles to reveal for each number of mines
     */
    function getMaxReveal() external view returns (uint256[24] memory maxReveal) {
        for (uint256 i = 0; i < 24; i++) {
            maxReveal[i] = minesMaxReveal[i + 1];
        }
    }

    /**
     * @dev get current game state of player
     * @param player address of the player that made the bet
     * @return minesState current state of player game
     */
   function getCurrentUserState(address player) external view returns (MinesGame memory minesState) {
        minesState = minesGames[player];
        return minesState;
    }

    /**
     * @dev function to start mines game, player cannot currently be in a game
     * @param wager wager amount
     * @param tokenAddress address of token the wager was made and payout, 0 address is considered the native coin
     * @param tiles arrays of tiles to initialy reveal, true equals that tile will be revealed
     * @param isCashout if true, game will give payout if player doesn't reveal mines
     * @param numMines number of mines present in game, range from 1-24
     */
    function play(
        uint256 wager,
        address tokenAddress,
        uint8 numMines,
        bool[25] calldata tiles,
        bool isCashout
    ) external payable nonReentrant {
        if (!(numMines >= 1 && numMines <= 24)) {
            revert InvalidNumMines();
        }

        MinesGame storage game = minesGames[msg.sender];
        if (game.requestID != 0) {
            revert AwaitingVRF(game.requestID);
        }
        if (game.numMines != 0) {
            revert AlreadyInGame();
        }

        uint32 numTilesToReveal;
        for (uint8 i = 0; i < tiles.length; i++) {
            if (tiles[i]) {
                numTilesToReveal++;
            }
        }
        uint256 _minesMaxReveal = minesMaxReveal[numMines];
        if (numTilesToReveal == 0 || numTilesToReveal > _minesMaxReveal) {
            revert InvalidNumberToReveal(numTilesToReveal, _minesMaxReveal);
        }

        _kellyWager(wager, tokenAddress, _minesMaxReveal, numMines);
        _transferWager(tokenAddress,
            wager,
            400000,
            22);
        uint256 id = _requestRandomWords(numTilesToReveal);
        minesIDs[id] = msg.sender;
        game.numMines = numMines;
        game.wager = wager;
        game.tokenAddress = tokenAddress;
        game.isCashout = isCashout;
        game.tilesPicked = tiles;
        game.requestID = id;
        game.blockNumber = uint64(block.number);
    }

    /**
     * @dev function to reveal tiles in an ongoing game
     * @param tiles array of tiles that the player wishes to reveal, can't choose already revealed tiles, true equals that tile will be revealed
     * @param isCashout if true and player doesn't reveal mines, will cashout
     */
    function reveal(bool[25] calldata tiles, bool isCashout) external payable nonReentrant {
        MinesGame storage game = minesGames[msg.sender];

        if (game.numMines == 0) {
            revert NotInGame();
        }
        if (game.requestID != 0) {
            revert AwaitingVRF(game.requestID);
        }

        uint32 numTilesRevealed;
        uint32 numTilesToReveal;
        for (uint8 i = 0; i < tiles.length; i++) {
            if (tiles[i]) {
                if (game.revealedTiles[i]) {
                    revert TileAlreadyRevealed(i);
                }
                numTilesToReveal++;
            }
            if (game.revealedTiles[i]) {
                numTilesRevealed++;
            }
        }

        if (numTilesToReveal == 0 || numTilesToReveal + numTilesRevealed > minesMaxReveal[game.numMines]) {
            revert InvalidNumberToReveal(numTilesToReveal + numTilesRevealed, minesMaxReveal[game.numMines]);
        }

        _payVRFFee(400000, 24);

        uint256 id = _requestRandomWords(numTilesToReveal);
        minesIDs[id] = msg.sender;
        game.tilesPicked = tiles;
        game.isCashout = isCashout;
        game.requestID = id;
        game.blockNumber = uint64(block.number);
    }

    /**
     * @dev function to end player current game and receive payout
     */

    function end() external nonReentrant {
        MinesGame storage game = minesGames[msg.sender];
        if (game.numMines == 0) {
            revert NotInGame();
        }
        if (game.requestID != 0) {
            revert AwaitingVRF(game.requestID);
        }

        uint256 multiplier = game.currentMultiplier;
        uint256 wager = game.wager;
        uint256 payout = (multiplier * wager) / 10000;
        address tokenAddress = game.tokenAddress;
        _transferToBankroll(tokenAddress, wager);
        delete (minesGames[msg.sender]);
        _transferPayout(msg.sender, payout, tokenAddress);
        emit MinesEnd(msg.sender, wager, payout, tokenAddress, multiplier);
    }

    /**
     * @dev Function to get refund for game if VRF request fails
     */
    function refund() external nonReentrant {
        if (minesGames[msg.sender].numMines == 0) {
            revert NotInGame();
        }
        if (minesGames[msg.sender].requestID == 0) {
            revert NoRequestPending();
        }
        if (minesGames[msg.sender].blockNumber + 200 > block.number) {
            revert BlockNumberTooLow(block.number, minesGames[msg.sender].blockNumber + 200);
        }

        uint256 wager = minesGames[msg.sender].wager;
        address tokenAddress = minesGames[msg.sender].tokenAddress;
        delete (minesGames[msg.sender]);
        if (tokenAddress == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: wager}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(tokenAddress).safeTransfer(msg.sender, wager);
        }
        emit Mines_Refund_Event(msg.sender, wager, tokenAddress);
    }

    /**
     * @dev function to set game multipliers only callable by the owner
     * @param numMines number of mines to set multipliers for
     */
    function setMinesMultipliers(uint256 numMines) external {
        if (msg.sender != bankroll.getOwner()) {
            revert NotOwner(bankroll.getOwner(), msg.sender);
        }

        for (uint256 g = 1; g <= 25 - numMines; g++) {
            uint256 multiplier = 1;
            uint256 divisor = 1;
            for (uint256 f = 0; f < g; f++) {
                multiplier *= (25 - numMines - f);
                divisor *= (25 - f);
            }
            minesMultipliers[numMines][g] = (9900 * (10 ** 9)) / ((multiplier * (10 ** 9)) / divisor);
        }
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        address player = minesIDs[_requestId];
        if (player == address(0)) revert();
        delete (minesIDs[_requestId]);
        MinesGame storage game = minesGames[player];

        uint32 i;
        uint256 numberOfRevealedTiles;
        for (i = 0; i < game.revealedTiles.length; i++) {
            if (game.revealedTiles[i] == true) {
                numberOfRevealedTiles += 1;
            }
        }

        uint256 numberOfMinesLeft = game.numMines;
        bool[25] memory mines;
        bool won = true;
        uint8 randomCounter;

        for (i = 0; i < game.tilesPicked.length; i++) {
            if (numberOfMinesLeft == 0 || 25 - numberOfRevealedTiles == numberOfMinesLeft) {
                if (game.tilesPicked[i]) {
                    game.revealedTiles[i] = true;
                }
                continue;
            }
            if (game.tilesPicked[i]) {
                bool gem = _pickTile(
                    player,
                    i,
                    25 - numberOfRevealedTiles,
                    numberOfMinesLeft,
                    _randomWords[randomCounter]
                );
                if (gem == false) {
                    numberOfMinesLeft -= 1;
                    mines[i] = true;
                    won = false;
                }
                numberOfRevealedTiles += 1;
                randomCounter += 1;
            }
        }

        if (!won) {
            if (game.isCashout == false) {
                emit MinesReveal(player, game.wager, 0, game.tokenAddress, mines, game.revealedTiles, 0);
            } else {
                emit MinesRevealCashout(player, game.wager, 0, game.tokenAddress, mines, game.revealedTiles, 0);
            }
            _transferToBankroll(game.tokenAddress, game.wager);
            delete (minesGames[player]);

            return;
        }

        uint256 multiplier = minesMultipliers[numberOfMinesLeft][numberOfRevealedTiles];

        if (game.isCashout == false) {
            game.currentMultiplier = uint64(multiplier);
            game.requestID = 0;
            emit MinesReveal(
                player,
                game.wager,
                (multiplier * game.wager) / 10000,
                game.tokenAddress,
                mines,
                game.revealedTiles,
                multiplier
            );
        } else {
            uint256 wager = game.wager;
            address tokenAddress = game.tokenAddress;
            emit MinesRevealCashout(
                player,
                wager,
                (multiplier * wager) / 10000,
                tokenAddress,
                mines,
                game.revealedTiles,
                multiplier
            );
            _transferToBankroll(tokenAddress, game.wager);
            delete (minesGames[player]);
            _transferPayout(player, (multiplier * wager) / 10000, tokenAddress);
        }
    }

    function _pickTile(
        address player,
        uint256 tileNumber,
        uint256 numberTilesLeft,
        uint256 numberOfMinesLeft,
        uint256 rng
    ) internal returns (bool) {
        uint256 winChance = 10000 - (numberOfMinesLeft * 10000) / numberTilesLeft;

        bool won = false;
        if (rng % 10000 <= winChance) {
            won = true;
        }
        minesGames[player].revealedTiles[tileNumber] = true;
        return won;
    }

    /**
     * @dev function to set game max number of reveals only callable at deploy time
     * @param maxReveal max reveal for each num Mines
     */
    function _setMaxReveal(uint8[24] memory maxReveal) internal {
        for (uint256 i = 0; i < maxReveal.length; i++) {
            minesMaxReveal[i + 1] = maxReveal[i];
        }
    }

    /**
     * @dev calculates the maximum wager allowed based on the bankroll size
     */
    function _kellyWager(uint256 wager, address tokenAddress, uint256 maxReveal, uint256 numMines) internal view {
        uint256 balance;
        if (tokenAddress == address(0)) {
            balance = address(bankroll).balance;
        } else {
            balance = IERC20(tokenAddress).balanceOf(address(bankroll));
        }
        uint256 maxWager = (balance * (11000 - 10890)) / (minesMultipliers[numMines][maxReveal] - 10000);
        if (wager > maxWager) {
            revert WagerAboveLimit(wager, maxWager);
        }
    }
}

