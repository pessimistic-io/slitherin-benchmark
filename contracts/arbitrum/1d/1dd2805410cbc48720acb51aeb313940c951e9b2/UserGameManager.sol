// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./BaseUserManager.sol";
import "./Intervals.sol";
import "./Gameable.sol";

abstract contract UserGameManager is BaseUserManager {
    address public gameManager;

    modifier onlyGameManager() {
        require(msg.sender == gameManager, "You are not the game manager");
        _;
    }

    function getLatestAprOf(
        uint256 tokenId
    ) public view override returns (uint256) {
        uint256[] memory apr = dayAprSinceCreationOf(tokenId);
        uint256 aprCount = apr.length;
        return apr[aprCount - 1];
    }

    function dayAprSinceCreationOf(
        uint256 tokenId
    ) internal view returns (uint256[] memory) {
        User memory user = users[tokenId];
        (uint256 nbOfDays, ) = Intervals.getNbOfIntervalsAndSecondsLeft(
            block.timestamp - user.createdAt,
            1 days
        );
        uint256 currentDayStart = user.createdAt;
        uint256[] memory apr = new uint256[](nbOfDays + 1);
        apr[0] = aprs[user.category].apr;
        for (uint256 i = 1; i < apr.length; i++) {
            if (!fulfillDailyRequirement(tokenId, currentDayStart)) {
                if(apr[i - 1] < penality) {
                  apr[i] = 0;
                }
                else {
                  apr[i] = apr[i - 1] - penality;
                }
                
            } else {
                apr[i] = apr[i - 1];
            }
            currentDayStart = currentDayStart + 1 days;
        }
        return apr;
    }

    function fulfillDailyRequirement(
        uint256 tokenId,
        uint256 _startDay
    ) internal view returns (bool) {
        Gameable.UserGame[] memory userGames = Gameable(gameManager)
            .getGamesEndedBetweenIntervalOf(
                tokenId,
                _startDay,
                _startDay + 1 days
            );
        User memory user = users[tokenId];
        if (user.category == AprType.BORED) {
            return highTierRequirements(userGames);
        }
        if (user.category == AprType.MUTANT) {
            return middleTierRequirements(userGames);
        }
        return userGames.length > 0;
    }

    function highTierRequirements(
        Gameable.UserGame[] memory _userGames
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < _userGames.length; i++) {
            if (
                Gameable.TierType.BORED == _userGames[i].category ||
                _userGames[i].isWinner
            ) {
                return true;
            }
        }
        return false;
    }

    function middleTierRequirements(
        Gameable.UserGame[] memory _userGames
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < _userGames.length; i++) {
            if (
                _userGames[i].isWinner ||
                Gameable.TierType.MUTANT == _userGames[i].category ||
                Gameable.TierType.BORED == _userGames[i].category
            ) {
                return true;
            }
        }
        return false;
    }

    function setGameManager(address _gameManager) public onlyOwner {
        gameManager = _gameManager;
    }

    function getPlayersOf(address account) external view returns(UserDescription[] memory) {
      uint256 nbPlayers = balanceOf(account);
      UserDescription[] memory players = new UserDescription[](nbPlayers);
      for(uint256 i = 0; i < nbPlayers; i++) {
        uint256 tokenId = tokenOfOwnerByIndex(account, i);
        UserDescription memory player = getUserDescription(tokenId);
        player.name = users[tokenId].name;
        player.initialBalance = users[tokenId].initialBalance;
        players[i] = player;
      }
      return players;
    }
}

