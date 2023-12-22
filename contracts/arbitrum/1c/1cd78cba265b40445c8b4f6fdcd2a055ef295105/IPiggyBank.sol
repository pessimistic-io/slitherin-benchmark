// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IPiggyBankDefinition {
    struct SeasonInfo {
        uint256 totalAmount;
        uint256 startBlock;
        bool stopped;
    }

    struct RoundInfo {
        uint256 totalAmount;
        uint256 target;
        uint256 currentIndex;
        uint256 startBlock;
    }

    struct PiggyBankSumReturns {
        uint256 seasonTotalAmount;
        bool isEnd;
        uint256 roundTotalAmount;
        uint256 roundTarget;
        uint256 roundNextMultiple;
        uint256 roundIndex;
        uint256 roundStartBlock;
        uint256 countDownBlockLong;
    }

    struct UserInfo {
        uint256 amount;
        uint256 claimedAmount;
    }

    event WithdrawEmergency(address receiver, uint256 amount);
    event InitializeSeason(
        uint256 season,
        uint256 seasonStartBlock,
        RoundInfo roundInfo
    );
    event SetNewMultiple(uint8 multiple);
    event Deposit(
        uint256 season,
        address account,
        uint256 roundIndex,
        uint256 amount,
        uint256 roundTotalAmount
    );
    event SeasonStopped(uint256 season, uint256 stopBlockNumber);
    event SignerUpdate(address indexed signer, bool valid);
    event SetStoppedHash(
        uint256 season,
        bytes32 stoppedHash,
        address verifySigner
    );
    event ClaimedReward(uint256 season, address account, uint256 amount);
    event SetNewCountDownBlockLong(uint256 countDownBlockLong);
    event SetIsClaimOpened(bool isClaimOpened);
    event SetNewRoundRewardPercentage(uint16 percentage);
    event RewardUserWhoChangeRound(
        address account,
        uint256 season,
        uint256 roundIndex,
        uint256 amount
    );

    error CallerNotPortal();
    error InvalidRoundInfo();
    error SeasonOver();
    error InvalidSeason();
    error AlreadyClaimed();
    error SeasonNotOver();
    error CountDownBlockLongNotSet();
    error CanNotClaim();
}

interface IPiggyBank is IPiggyBankDefinition {
    function deposit(
        uint256 season,
        address account,
        uint256 income
    ) external payable;

    function setMultiple(uint8 multiple_) external;

    function checkIsSeasonEnd(uint256 season) external view returns (bool);

    function stop(uint256 season) external;

    function initializeSeason(
        uint256 season,
        uint256 seasonStartBlock,
        uint256 initRoundTarget
    ) external payable;
}

