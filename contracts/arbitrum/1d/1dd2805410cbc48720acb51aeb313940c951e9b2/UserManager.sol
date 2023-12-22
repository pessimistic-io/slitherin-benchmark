// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./UserGameManager.sol";
import "./Intervals.sol";
import "./ComputeReward.sol";
import "./MathUpgradeable.sol";

contract UserManager is UserGameManager {
    modifier canClaim(uint256 tokenId) {
        require(getClaimableRewards(tokenId) > 0, "No token claimable");
        _;
    }
    function lastIntervalRewardsFromUserGame(
        uint256 _tokenId
    ) internal view returns (uint256 reward) {
        (
            uint256 nbOfDaysLastUserGame,
            uint256 secondsLeftLastUserGame
        ) = Intervals.getNbOfIntervalsAndSecondsLeft(
                usersGame[_tokenId].date - users[_tokenId].createdAt,
                1 days
            );
        (uint256 nbOfDaysFromNow, ) = Intervals.getNbOfIntervalsAndSecondsLeft(
            block.timestamp - users[_tokenId].createdAt,
            1 days
        );
        uint256 rewardTimeInterval = block.timestamp - usersGame[_tokenId].date;
        uint256[] memory aprSinceCreation = dayAprSinceCreationOf(_tokenId);
        uint256 aprCount = aprSinceCreation.length;

        if (nbOfDaysFromNow > nbOfDaysLastUserGame) {
            if (secondsLeftLastUserGame > 0) {
                reward += ComputeReward.calc(
                    usersGame[_tokenId].tokenBalance,
                    aprSinceCreation[nbOfDaysLastUserGame],
                    1 days - secondsLeftLastUserGame
                );
                rewardTimeInterval =
                    rewardTimeInterval -
                    (1 days - secondsLeftLastUserGame);
            }
            uint256 balance = usersGame[_tokenId].tokenBalance;
            for (uint256 i = nbOfDaysLastUserGame; i < nbOfDaysFromNow; i++) {
                uint256 apr = aprSinceCreation[i];
                (uint256 nbDays, ) = Intervals.getNbOfIntervalsAndSecondsLeft(
                    rewardTimeInterval,
                    1 days
                );
                if (nbDays > 0) {
                    rewardTimeInterval -= 1 days;
                    reward += ComputeReward.calc(balance, apr, 1 days);
                }
            }
            if (rewardTimeInterval > 0) {
                reward += ComputeReward.calc(
                    balance,
                    aprSinceCreation[aprCount - 1],
                    rewardTimeInterval
                );
            }
        } else {
            uint256 latestApr = getLatestAprOf(_tokenId);
            reward += ComputeReward.calc(
                usersGame[_tokenId].tokenBalance,
                latestApr,
                rewardTimeInterval
            );
        }
    }

    function getTotalRewards(uint256 tokenId) public view returns (uint256) {
        if (usersGame[tokenId].date <= 0) {
            return totalRewards(tokenId, 0);
        }
        return
            lastIntervalRewardsFromUserGame(tokenId) +
            usersGame[tokenId].totalReward;
    }

    function totalRewards(
        uint256 tokenId,
        uint256 amount
    ) public view returns (uint256 rewards) {
        User memory user = users[tokenId];
        uint256[] memory _aprSinceCreation = dayAprSinceCreationOf(tokenId);
        uint256 _aprCount = _aprSinceCreation.length;

        if (usersGame[tokenId].date <= 0) {
            (uint256 nbOfDays, uint256 secondsLeftFromDay) = Intervals
                .getNbOfIntervalsAndSecondsLeft(
                    block.timestamp - user.createdAt,
                    1 days
                );
            if (amount == 0) {
                amount = user.balance;
            }
            for (uint256 i = 0; i < nbOfDays; i++) {
                rewards += ComputeReward.calc(
                    amount,
                    _aprSinceCreation[i],
                    1 days
                );
            }
            if (secondsLeftFromDay > 0) {
                rewards += ComputeReward.calc(
                    amount,
                    _aprSinceCreation[_aprCount - 1],
                    secondsLeftFromDay
                );
            }
        } else {
            rewards =
                lastIntervalRewardsFromUserGame(tokenId) +
                usersGame[tokenId].totalReward;
        }
    }

    function claimReward(
        uint256 tokenId
    )
        external
        whenNotPaused
        nonReentrant
        onlyUserOwner(tokenId)
        canClaim(tokenId)
    {
        uint256 claimableReward = getClaimableRewards(tokenId);
        _updateUserReward(tokenId, claimableReward);
        uint256 teamIncentive = _computeFeeAmount(claimableReward, rewardFee);
        uint256 userRewards = claimableReward - teamIncentive;
        Boreable(boredInBorderland).userReward(_msgSender(), userRewards);
        Boreable(boredInBorderland).userReward(address(this), teamIncentive);
        _teamPayment();
    }

    function compoundReward(
        uint256 tokenId
    )
        external
        whenNotPaused
        nonReentrant
        onlyUserOwner(tokenId)
        canClaim(tokenId)
    {
        uint256 claimableReward = getClaimableRewards(tokenId);
        _updateUserCompound(tokenId, 0, claimableReward);
    }

    function claimAndCompoundReward(
        uint256 tokenId,
        uint256 claimPercentage
    )
        external
        whenNotPaused
        nonReentrant
        onlyUserOwner(tokenId)
        canClaim(tokenId)
    {
        require(
            claimPercentage < 100,
            "You must claim less than 100% of claim"
        );
        uint256 claimableReward = getClaimableRewards(tokenId);
        uint256 claim = (claimableReward * claimPercentage) / 100;
        uint256 compound = claimableReward - claim;
        _updateUserCompound(tokenId, claim, compound);
        uint256 teamIncentive = _computeFeeAmount(claim, rewardFee);
        uint256 userRewards = claim - teamIncentive;
        Boreable(boredInBorderland).userReward(_msgSender(), userRewards);
        Boreable(boredInBorderland).userReward(address(this), teamIncentive);
        _teamPayment();
    }

    function balanceOfTokenID(
        uint256 tokenID
    ) external view override returns (uint256) {
        require(tokenID != 0 && _exists(tokenID), "TokenID does not exist");
        return users[tokenID].balance;
    }

    function credit(
        uint256 tokenID,
        uint256 amount
    ) external override onlyGameManager {
        users[tokenID].balance += amount;
        users[tokenID].updatedAt = block.timestamp;
        _updateUserGameTokenBalance(tokenID, amount);
    }

    function debit(
        uint256 tokenID,
        uint256 amount
    ) external override onlyGameManager {
        users[tokenID].balance -= amount;
        users[tokenID].updatedAt = block.timestamp;
    }

    function getClaimableRewards(
        uint256 tokenId
    ) public view onlyExist(tokenId) returns (uint256) {
        if (usersGame[tokenId].date > 0) {
            if (usersGame[tokenId].lastClaimTime <= block.timestamp - 4 hours && usersGame[tokenId].lastClaimTime != 0) {
                (uint256 nbOfIntervalsClaimable, ) = Intervals
                    .getNbOfIntervalsAndSecondsLeft(
                        block.timestamp - usersGame[tokenId].lastClaimTime,
                        4 hours
                    );
                uint256 _totalRewards = getTotalRewards(tokenId);
                return
                    Math.mulDiv(
                        _totalRewards,
                        nbOfIntervalsClaimable * 4 hours,
                        block.timestamp - usersGame[tokenId].lastClaimTime
                    );
            }
            if (
                usersGame[tokenId].lastClaimTime == 0 &&
                users[tokenId].createdAt <= block.timestamp - 4 hours
            ) {
                (uint256 nbOfIntervalsClaimable, ) = Intervals
                    .getNbOfIntervalsAndSecondsLeft(
                        block.timestamp - users[tokenId].createdAt,
                        4 hours
                    );
                uint256 _totalRewards = getTotalRewards(tokenId);
                return
                    Math.mulDiv(
                        _totalRewards,
                        nbOfIntervalsClaimable * 4 hours,
                        block.timestamp - users[tokenId].createdAt
                    );
            }
            return 0;
        }
        if (users[tokenId].createdAt <= block.timestamp - 4 hours) {
            (uint256 nbOfIntervalsClaimable, ) = Intervals
                .getNbOfIntervalsAndSecondsLeft(
                    block.timestamp - users[tokenId].createdAt,
                    4 hours
                );
            return
                Math.mulDiv(
                    totalRewards(tokenId, 0),
                    nbOfIntervalsClaimable * 4 hours,
                    block.timestamp - users[tokenId].createdAt
                );
        }
        return 0;
    }

    function _updateUserGameTokenBalance(uint256 _tokenId, uint256 _amount) internal {
      usersGame[_tokenId].tokenBalance += _amount;
    }

    function _updateUserCompound(
        uint256 _tokenId,
        uint256 _claimedAmount,
        uint256 _compoundAmount
    ) internal {
        UserGame storage _userGame = usersGame[_tokenId];
        if (_userGame.lastClaimTime == 0 && _userGame.date == 0) {
            _userGame.id += 1;
            _userGame.rewardT0 = 0;
            _userGame.rewardT1 = getTotalRewards(_tokenId);
            _userGame.totalReward =
                _userGame.rewardT1 -
                _claimedAmount -
                _compoundAmount;
            _userGame.tokenBalance = users[_tokenId].balance + _compoundAmount;
            _userGame.date = block.timestamp;
        } else {
            _userGame.totalReward =
                getTotalRewards(_tokenId) -
                _claimedAmount -
                _compoundAmount;
            _userGame.tokenBalance += _compoundAmount;
        }
        users[_tokenId].balance += _compoundAmount;
        _userGame.lastClaimTime = block.timestamp;
    }

    function _updateUserReward(
        uint256 _tokenId,
        uint256 _claimedAmount
    ) internal {
        UserGame storage _userGame = usersGame[_tokenId];
        if (_userGame.lastClaimTime == 0 && _userGame.date == 0) {
            _userGame.id += 1;
            _userGame.rewardT0 = 0;
            _userGame.rewardT1 = totalRewards(_tokenId, 0);
            _userGame.totalReward = _userGame.rewardT1 - _claimedAmount;
            _userGame.tokenBalance = users[_tokenId].balance;
            _userGame.date = block.timestamp;
        } else {
            _userGame.totalReward =  getTotalRewards(_tokenId) - _claimedAmount;
        }
        _userGame.lastClaimTime = block.timestamp;
    }

    function updateUserGame(
        uint256 tokenId,
        uint256 gameId
    ) external override onlyGameManager {
        UserGame storage userGame = usersGame[tokenId];
        userGame.id += 1;
        Gameable.Game memory lastGame = Gameable(gameManager).getGame(gameId);
        Gameable.Tier memory gameTier = Gameable(gameManager).getTier(
            lastGame.category
        );
        if (userGame.date > 0) {
            userGame.rewardT0 = userGame.totalReward;
            userGame.rewardT1 = lastIntervalRewardsFromUserGame(tokenId);
            userGame.tokenBalance = users[tokenId].balance;
        } else {
            userGame.rewardT0 = 0;
            uint256 balanceBeforeFirstGame = gameTier.amount +
                users[tokenId].balance;
            userGame.rewardT1 = totalRewards(tokenId, balanceBeforeFirstGame);
            userGame.tokenBalance += users[tokenId].balance;
        }
        userGame.totalReward = userGame.rewardT0 + userGame.rewardT1;
        userGame.date = block.timestamp;
        userGame.gameIds[uint(lastGame.category)] = uint(lastGame.category);
    }
}

