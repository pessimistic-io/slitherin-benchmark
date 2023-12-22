//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Random.sol";
import "./GameBase.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

contract GameManager is GameBase {
    using SafeMathUpgradeable for uint256;

    uint256 nonce;

    function _init() internal override {
        nonce = Random.numberChosen(0, 100, 0);
    }

    function play(
        TierType category,
        uint256 tokenID,
        uint8 numberChosen
    ) external virtual override whenNotPaused returns (uint256) {
        require(
            address(userManager) != address(0),
            "GameManager: missing implementation"
        );
        require(
            numberChosen >= 0 && numberChosen <= 100,
            "GameManager: the number must be between 0 and 100"
        );
        Tier memory tier = getTier(category);
        uint256 balance = userManager.balanceOfTokenID(tokenID);
        require(balance >= tier.amount, "The tokenID not enough credit");
        userManager.debit(tokenID, tier.amount);
        uint256 lastTier = currentTiers[category];
        uint256 gameID;
        if (lastTier <= 0) {
            NumberChosen[] memory numbersChosen = _getNumbersChosen(
                tokenID,
                numberChosen,
                balance
            );
            gameID = _firstGame(numbersChosen, tier, category);
            emit NewGame(gameID, tokenID, category);
        } else {
            Game storage currentGame = games[lastTier];
            if (block.timestamp < currentGame.endedAt) {
                gameID = lastTier;
                if (!_existsPlayer(tokenID, gameID)) {
                    _currentGame(
                        currentGame,
                        tier,
                        gameID,
                        NumberChosen({
                            tokenID: tokenID,
                            number: numberChosen,
                            balanceBeforeGame: balance,
                            createdAt: block.timestamp
                        })
                    );
                } else {
                    revert("The tokenID has already played");
                }
            } else {
                NumberChosen[] memory numbersChosen = _getNumbersChosen(
                    tokenID,
                    numberChosen,
                    balance
                );
                gameID = _newGame(numbersChosen, category, tier);
                emit NewGame(gameID, tokenID, category);
            }
        }
        userManager.updateUserGame(tokenID, gameID);
        currentTiers[category] = gameID;
        gamesOfTokenID[tokenID].push(gameID);
        emit PlayGame(gameID, tokenID, category);
        return gameID;
    }

    function getGamesEndedBetweenIntervalOf(
        uint256 tokenID,
        uint256 startInterval,
        uint256 endInterval
    ) external view override returns (UserGame[] memory) {
        UserGame[] memory userGame;
        if (games.length <= 0) {
            return userGame;
        }
        if (games.length - 1 == 1) {
            uint256 gameID = 1;
            Game memory g = games[gameID];
            if (
                _tokenIDExistsIn(1, tokenID) &&
                g.endedAt >= startInterval &&
                g.endedAt <= endInterval &&
                _gameIsOver(g)
            ) {
                userGame = new UserGame[](1);
                userGame[0].gameID = gameID;
                userGame[0].category = g.category;
                userGame[0].isWinner = g.winner == tokenID;
                for (uint256 i = 0; i < g.playersInGame; i++) {
                    if (playersOf[gameID][i].tokenID == tokenID) {
                        userGame[0].balanceBeforeGame = playersOf[gameID][i]
                            .balanceBeforeGame;
                    }
                }
            }
            return userGame;
        }
        uint256 amountGameOverAndBetweenInterval = 0;
        for (uint i = 0; i < gamesOfTokenID[tokenID].length; i++) {
            Game memory g = games[gamesOfTokenID[tokenID][i]];
            if (
                g.endedAt <= startInterval &&
                g.endedAt <= endInterval &&
                _gameIsOver(g)
            ) {
                amountGameOverAndBetweenInterval++;
            }
        }
        userGame = new UserGame[](amountGameOverAndBetweenInterval);
        for (uint i = 0; i < gamesOfTokenID[tokenID].length; i++) {
            uint256 gameID = gamesOfTokenID[tokenID][i];
            Game memory g = games[gameID];
            if (
                g.endedAt <= startInterval &&
                g.endedAt <= endInterval &&
                _gameIsOver(g)
            ) {
                userGame[i].gameID = gameID;
                userGame[i].category = g.category;
                userGame[i].isWinner = g.winner == tokenID;
                for (uint256 j = 0; j < g.playersInGame; j++) {
                    if (playersOf[gameID][j].tokenID == tokenID) {
                        userGame[i].balanceBeforeGame = playersOf[gameID][j]
                            .balanceBeforeGame;
                    }
                }
            }
        }
        return userGame;
    }

    function _getNumbersChosen(
        uint256 tokenID,
        uint8 numberChosen,
        uint256 balance
    ) internal virtual returns (NumberChosen[] memory) {
        NumberChosen memory botA = NumberChosen({
            tokenID: tokenIDBotA,
            number: Random.numberChosen(0, 100, nonce),
            balanceBeforeGame: 0,
            createdAt: block.timestamp
        });
        nonce++;
        NumberChosen memory botB = NumberChosen({
            tokenID: tokenIDBotB,
            number: Random.numberChosen(0, 100, nonce),
            balanceBeforeGame: 0,
            createdAt: block.timestamp
        });
        nonce++;
        NumberChosen memory player = NumberChosen({
            tokenID: tokenID,
            number: numberChosen,
            balanceBeforeGame: balance,
            createdAt: block.timestamp
        });
        NumberChosen[] memory numbersChosen = new NumberChosen[](3);
        numbersChosen[0] = botA;
        numbersChosen[1] = botB;
        numbersChosen[2] = player;
        return numbersChosen;
    }

    function _computeTarget(
        uint256 gameID,
        uint256 size
    ) internal view virtual returns (uint256) {
        uint256 sum;
        uint256 percent = 80;
        for (uint256 i; i < size; i++) {
            sum += playersOf[gameID][i].number;
        }
        return sum.div(size).mul(percent).div(100);
    }

    function _getWinner(
        uint256 gameID,
        uint256 size,
        uint256 target
    ) internal view virtual returns (NumberChosen memory) {
        NumberChosen memory winner;
        uint256 closestDiff = type(uint256).max;
        for (uint256 i = 0; i < size; i++) {
            NumberChosen memory numberSelected = playersOf[gameID][i];
            uint256 diff = target > numberSelected.number
                ? target - numberSelected.number
                : numberSelected.number - target;
            if (diff < closestDiff) {
                winner = numberSelected;
                closestDiff = diff;
            }
        }
        return winner;
    }

    function _getNumberChosenOf(
        uint256 tokenID,
        NumberChosen[] memory players
    ) internal view virtual returns (NumberChosen memory) {
        for (uint256 i; i < players.length; i++) {
            if (tokenID == players[i].tokenID) {
                return players[i];
            }
        }
        revert("Not found");
    }

    function _existsPlayer(
        uint256 tokenID,
        uint256 gameID
    ) internal view virtual returns (bool) {
        for (uint i = 0; i < games[gameID].playersInGame; i++) {
            if (playersOf[gameID][i].tokenID == tokenID) {
                return true;
            }
        }
        return false;
    }

    function _firstGame(
        NumberChosen[] memory numbersChosen,
        Tier memory tier,
        TierType category
    ) internal returns (uint256) {
        uint256 sizeGame = games.length;
        uint256 gameID;
        Game memory game = Game({
            id: 0,
            winner: 0,
            playersInGame: numbersChosen.length,
            startedAt: block.timestamp,
            endedAt: block.timestamp + tier.duration,
            updatedAt: block.timestamp,
            category: category,
            pool: tier.amount.mul(numbersChosen.length)
        });
        if (sizeGame <= 0) {
            games.push();
            games.push(game);
            gameID = 1;
        } else {
            gameID = games.length;
            games.push(game);
        }
        lastGameLaunched = block.timestamp;
        for (uint256 i = 0; i < numbersChosen.length; i++) {
            playersOf[gameID][i] = numbersChosen[i];
        }
        uint256 target = _computeTarget(gameID, numbersChosen.length);
        games[gameID].winner = _getWinner(gameID, numbersChosen.length, target).tokenID;
        games[gameID].id = gameID;
        return gameID;
    }

    function _currentGame(
        Game storage game,
        Tier memory tier,
        uint256 gameID,
        NumberChosen memory newPlayer
    ) internal virtual {
        uint256 newSize = game.playersInGame + 1;
        playersOf[gameID][0].number = Random.numberChosen(0, 100, nonce);
        nonce++;
        playersOf[gameID][1].number = Random.numberChosen(0, 100, nonce);
        nonce++;
        playersOf[gameID][game.playersInGame] = newPlayer;
        uint256 target = _computeTarget(gameID, newSize);
        NumberChosen memory winner = _getWinner(gameID, newSize, target);
        game.winner = winner.tokenID;
        game.playersInGame = newSize;
        game.updatedAt = block.timestamp;
        game.pool = tier.amount.mul(newSize);
    }

    function _newGame(
        NumberChosen[] memory numbersChosen,
        TierType category,
        Tier memory tier
    ) internal returns (uint256) {
        uint256 gameID = games.length;
        Game memory game = Game({
            id: gameID,
            winner: 0,
            playersInGame: numbersChosen.length,
            startedAt: block.timestamp,
            endedAt: block.timestamp + tier.duration,
            updatedAt: block.timestamp,
            category: category,
            pool: tier.amount.mul(numbersChosen.length)
        });
        lastGameLaunched = block.timestamp;
        games.push(game);
         for (uint256 i = 0; i < numbersChosen.length; i++) {
            playersOf[gameID][i] = numbersChosen[i];
        }
        uint256 target = _computeTarget(gameID, numbersChosen.length);
        games[gameID].winner = _getWinner(gameID, numbersChosen.length, target).tokenID;
        return gameID;
    }
}

