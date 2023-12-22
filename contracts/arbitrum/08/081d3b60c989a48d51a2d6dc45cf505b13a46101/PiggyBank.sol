// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {ECDSAUpgradeable} from "./ECDSAUpgradeable.sol";
import {AddressUpgradeable} from "./AddressUpgradeable.sol";
import {SafeOwnableUpgradeable} from "./SafeOwnableUpgradeable.sol";
import {CommonError} from "./CommonError.sol";
import {BlockNumberReader} from "./BlockNumberReader.sol";
import {IPiggyBank} from "./IPiggyBank.sol";
import {PiggyBankStorage} from "./PiggyBankStorage.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

contract PiggyBank is
    SafeOwnableUpgradeable,
    UUPSUpgradeable,
    IPiggyBank,
    PiggyBankStorage,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address payable;

    function initialize(address owner_, address portal_) public initializer {
        if (portal_ == address(0) || owner_ == address(0)) {
            revert CommonError.ZeroAddressSet();
        }

        __Ownable_init(owner_);

        portal = portal_;
    }

    function initializeSeason(
        uint256 season,
        uint256 seasonStartBlock,
        uint256 initRoundTarget
    ) external payable onlyPortal {
        RoundInfo memory roundInfo = RoundInfo({
            totalAmount: 0,
            target: initRoundTarget,
            currentIndex: 0,
            startBlock: seasonStartBlock
        });

        seasons[season].totalAmount = msg.value;
        seasons[season].startBlock = seasonStartBlock;
        rounds[season] = roundInfo;

        emit InitializeSeason(season, seasonStartBlock, roundInfo);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function deposit(
        uint256 season,
        address account,
        uint256 income
    ) external payable override onlyPortal {
        if (countDownBlockLong == 0) {
            revert CountDownBlockLongNotSet();
        }

        bool isEnd = checkIsSeasonEnd(season);
        if (isEnd) {
            if (!seasons[season].stopped) {
                seasons[season].stopped = true;
            }
            revert SeasonOver();
        }

        seasons[season].totalAmount += msg.value;

        // update round info
        RoundInfo storage roundInfo = rounds[season];
        if (roundInfo.totalAmount + income > roundInfo.target) {
            uint256 newRoundInitAmount = income -
                (roundInfo.target - roundInfo.totalAmount);

            uint256 remainingAmount = roundInfo.target - roundInfo.totalAmount;
            roundInfo.totalAmount = roundInfo.target;
            users[account][season][roundInfo.currentIndex]
                .amount += remainingAmount;

            emit Deposit(
                season,
                account,
                roundInfo.currentIndex,
                remainingAmount,
                roundInfo.totalAmount
            );

            // reward 8% to
            _rewardUserWhoChangeRound(account, season, roundInfo);

            _toNextRound(account, season, newRoundInitAmount);
        } else {
            roundInfo.totalAmount += income;
            users[account][season][roundInfo.currentIndex].amount += income;

            emit Deposit(
                season,
                account,
                roundInfo.currentIndex,
                income,
                roundInfo.totalAmount
            );
        }
    }

    function stop(uint256 season) external override onlyPortal {
        if (seasons[season].startBlock == 0) {
            revert InvalidSeason();
        }
        seasons[season].stopped = true;

        emit SeasonStopped(season, BlockNumberReader.getBlockNumber());
    }

    function claimReward(uint256 season) external {
        if (!checkIsSeasonEnd(season)) {
            revert SeasonNotOver();
        }

        if (!isClaimOpened) {
            revert CanNotClaim();
        }

        SeasonInfo memory seasonInfo = seasons[season];
        RoundInfo memory roundInfo = rounds[season];
        UserInfo storage userInfo = users[msg.sender][season][
            roundInfo.currentIndex
        ];

        if (userInfo.claimedAmount > 0) {
            revert AlreadyClaimed();
        }

        uint256 userReward = (seasonInfo.totalAmount * userInfo.amount) /
            roundInfo.totalAmount;

        userInfo.claimedAmount = userReward;

        payable(msg.sender).sendValue(userReward);

        emit ClaimedReward(season, msg.sender, userReward);
    }

    function _rewardUserWhoChangeRound(
        address account,
        uint256 season,
        RoundInfo memory roundInfo
    ) internal nonReentrant {
        uint256 reward = (roundInfo.target * newRoundRewardPercentage) /
            PERCENTAGE_BASE;
        seasons[season].totalAmount -= reward;
        payable(account).sendValue(reward);

        emit RewardUserWhoChangeRound(
            account,
            season,
            roundInfo.currentIndex,
            reward
        );
    }

    function setMultiple(uint8 multiple_) external override onlyOwner {
        multiple = multiple_;

        emit SetNewMultiple(multiple_);
    }

    function setCountDownBlockLong(
        uint256 countDownBlockLong_
    ) external onlyOwner {
        countDownBlockLong = countDownBlockLong_;

        emit SetNewCountDownBlockLong(countDownBlockLong_);
    }

    function setIsClaimOpened(bool isClaimOpened_) external onlyOwner {
        isClaimOpened = isClaimOpened_;

        emit SetIsClaimOpened(isClaimOpened);
    }

    function setNewRoundPercentage(uint16 percentage) external onlyOwner {
        newRoundRewardPercentage = percentage;

        emit SetNewRoundRewardPercentage(percentage);
    }

    function withdrawEmergency() external onlyOwner {
        uint256 amount = address(this).balance;
        payable(msg.sender).sendValue(amount);

        emit WithdrawEmergency(msg.sender, amount);
    }

    function _toNextRound(
        address account,
        uint256 season,
        uint256 nextRoundInitAmount
    ) internal {
        // update rounds
        RoundInfo storage roundInfo = rounds[season];
        roundInfo.currentIndex++;
        roundInfo.startBlock = uint32(BlockNumberReader.getBlockNumber());
        roundInfo.target += (roundInfo.target * multiple) / PERCENTAGE_BASE;

        if (nextRoundInitAmount > roundInfo.target) {
            roundInfo.totalAmount = roundInfo.target;
            // update userInfo
            users[account][season][roundInfo.currentIndex].amount = roundInfo
                .target;

            emit Deposit(
                season,
                account,
                roundInfo.currentIndex,
                roundInfo.target,
                roundInfo.totalAmount
            );

            // reward the user who change round to next round
            _rewardUserWhoChangeRound(account, season, roundInfo);

            _toNextRound(
                account,
                season,
                nextRoundInitAmount - roundInfo.target
            );
        } else {
            roundInfo.totalAmount = nextRoundInitAmount;

            users[account][season][roundInfo.currentIndex]
                .amount = nextRoundInitAmount;

            emit Deposit(
                season,
                account,
                roundInfo.currentIndex,
                nextRoundInitAmount,
                nextRoundInitAmount
            );
        }
    }

    function checkIsSeasonEnd(uint256 season) public view returns (bool) {
        bool isEnd = false;

        bool isAutoEnd = (rounds[season].totalAmount < rounds[season].target) &&
            BlockNumberReader.getBlockNumber() >=
            (countDownBlockLong + rounds[season].startBlock);

        if (isAutoEnd || seasons[season].stopped) {
            isEnd = true;
        }
        return isEnd;
    }

    function getSeasonInfo(
        uint256 season
    ) external view returns (SeasonInfo memory seasonInfo, bool isSeasonEnd) {
        seasonInfo = seasons[season];
        isSeasonEnd = checkIsSeasonEnd(season);
    }

    function getRoundInfo(
        uint256 season
    ) external view returns (RoundInfo memory) {
        return rounds[season];
    }

    function getSeasonSum(
        uint256 season
    ) external view returns (PiggyBankSumReturns memory sum) {
        sum = PiggyBankSumReturns({
            seasonTotalAmount: seasons[season].totalAmount,
            isEnd: checkIsSeasonEnd(season),
            roundTotalAmount: rounds[season].totalAmount,
            roundTarget: rounds[season].target,
            roundNextMultiple: multiple,
            roundIndex: rounds[season].currentIndex,
            roundStartBlock: rounds[season].startBlock,
            countDownBlockLong: countDownBlockLong
        });
    }

    function getUserInfo(
        address account,
        uint256 season,
        uint256 roundIndex
    ) external view returns (UserInfo memory) {
        return users[account][season][roundIndex];
    }

    modifier onlyPortal() {
        if (msg.sender != portal) {
            revert CallerNotPortal();
        }
        _;
    }
}

