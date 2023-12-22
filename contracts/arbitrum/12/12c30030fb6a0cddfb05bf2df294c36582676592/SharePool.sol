// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ITreasurySharePool} from "./ITreasurySharePool.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IERC20} from "./IERC20.sol";
import {SafeCast} from "./SafeCast.sol";
import "./UUPSUpgradeableExp.sol";

contract SharePool is ITreasurySharePool, UUPSUpgradeableExp {
    using SafeCast for uint256;

    struct RoundInfo {
        uint128 reward;
        uint128 totalStaked;
        uint256 rewardIndex;
    }

    struct UserInfo {
        uint128 index;
        uint128 debt;
        uint112 amount;
        uint32 sCRound;
        uint112 sC; //  current round staked
        uint112 sN; //  next
        uint112 sP; //  prev
    }

    uint256 public constant ROUND_DURATION = 7 days;

    mapping(address => UserInfo) private _userInfos;
    RoundInfo[] private _rounds;

    address public stakeToken;
    uint256 public round1StartAt;
    uint256 public totalStaked;
    uint256 public totalReward;
    uint256 public totalRewardUsed;
    uint256 public rewardIndex;
    int256 public lastRoundStaking;

    function initialize(address stakeToken_, uint256 round1StartAt_) external {
        require(stakeToken_ != address(0), "SharePool: address is empty");
        require(stakeToken == address(0), "SharePool: already initialized");
        require(round1StartAt_ > block.timestamp, "SharePool: bad r1 time");
        stakeToken = stakeToken_;
        round1StartAt = round1StartAt_;
        _rounds.push(RoundInfo(0, 0, 0)); //r0

        _init();
    }

    /**
     * @notice Get the round information
     * @param round The round number, the max uint256 is the current round.
     * @return staked The total amount of stake in the `round`.
     * @return reward The amount of reward in the round
     */
    function getRoundInfo(uint256 round) external view returns (uint256 staked, uint256 reward) {
        uint256 curr = _currentRoundId();
        if (round == type(uint256).max || round == curr) {
            RoundInfo memory info = _getCurrRoundInfo();
            return (info.totalStaked, info.reward);
        } else {
            require(round <= curr, "SharePool: round not found");
            RoundInfo memory info = _rounds[round];
            return (info.totalStaked, info.reward);
        }
    }

    /**
     * @dev Get the current round  number
     */
    function currentRound() public view returns (uint256) {
        uint256 curr = _currentRoundId();
        if (_needGotoNext()) return curr + 1;
        return curr;
    }

    /**
     * @notice Get the pool information
     * @return currRound The current round number
     * @return staked The total amount of stake in the pool
     * @return rewardBalance The amount of reward in the pool
     * @return accruedReward The accrued reward amount.
     * @return accruedUsedReward The accrued distribution out reward.
     * @return nextRoundStartAt Timestamp for the start of the next round.
     */
    function getPoolInfo()
        external
        view
        returns (
            uint256 currRound,
            uint256 staked,
            uint256 rewardBalance,
            uint256 accruedReward,
            uint256 accruedUsedReward,
            uint256 nextRoundStartAt
        )
    {
        currRound = currentRound();
        staked = totalStaked;
        rewardBalance = (totalReward - totalRewardUsed);
        accruedReward = totalReward;
        accruedUsedReward = totalRewardUsed;
        // curr:0 ,next: r1+7*1
        // curr:1 ,next: r1+7*1
        // curr:2, next: r1+7*2
        nextRoundStartAt = round1StartAt + (currRound < 1 ? ROUND_DURATION : ROUND_DURATION * currRound);
    }
    /**
     * @notice Get the stake information of an account
     * @param account The account to get the stake information
     * @return staking The amount of staking in the pool
     * @return inQueue The amount of stake in the current round
     * @return rewards The amount of reward in the pool
     * @return pendingReward The amount of reward in the previous round.
     */

    function getStakeInfo(address account)
        external
        view
        returns (uint256 staking, uint256 inQueue, uint256 rewards, uint256 pendingReward)
    {
        uint256 curr = currentRound();
        UserInfo memory info = _userInfos[account];

        (,, uint256 sC, uint256 sN) = _getRealTimeS3(curr, account);

        staking = info.amount - sN;
        inQueue = sN;
        RoundInfo memory prev = _getPrevRoundInfo();
        uint256 rewardStake = info.amount - sC - sN;
        pendingReward = prev.totalStaked == 0 ? 0 : prev.reward * rewardStake / prev.totalStaked;
        rewards = info.debt + (prev.rewardIndex - info.index) * rewardStake / 1e18;
    }

    /**
     * @notice Stake the token to the pool
     * @param amount The amount of token to stake
     */

    function stake(uint256 amount) external beforeDo {
        require(amount > 0, "SharePool: amount must be greater than 0");
        SafeTransferLib.safeTransferFrom(stakeToken, msg.sender, address(this), amount);

        uint256 curr = _currentRoundId();
        UserInfo storage info = _userInfos[msg.sender];
        info.sCRound = curr.toUint32();
        info.sN += amount.toUint112();
        info.amount += amount.toUint112();
        totalStaked += amount;
        lastRoundStaking += amount.toInt256();
        emit Stake(msg.sender, curr, amount);
    }
    /**
     * @notice Unstake the token from the pool
     * @param amount The amount of token to unstake
     * @param force Force unstake the token, even the token is preUnlocked.
     */

    function unstake(uint256 amount, bool force) external beforeDo {
        require(amount > 0, "SharePool: amount must be greater than 0");
        UserInfo memory info = _userInfos[msg.sender];
        require(amount <= info.amount, "SharePool: not enough staked");

        totalStaked -= amount;
        lastRoundStaking -= amount.toInt256();
        _userInfos[msg.sender].amount -= amount.toUint112();

        //use sN->sC->sP+others
        uint112 remaing = uint112(amount);
        (_userInfos[msg.sender].sN, remaing) = _subAmount(info.sN, remaing);
        (_userInfos[msg.sender].sC, remaing) = _subAmount(info.sC, remaing);
        if (remaing > 0) {
            require(force, "SharePool: will be lose pending reward");
            (_userInfos[msg.sender].sP, remaing) = _subAmount(info.sP, remaing);
        }

        uint256 curr = _currentRoundId();
        SafeTransferLib.safeTransfer(stakeToken, msg.sender, amount);
        emit Unstake(msg.sender, curr, amount);
    }

    /**
     * @notice Claim the unclaimed reward from the pool
     */
    function claim() external beforeDo {
        uint256 debt = _userInfos[msg.sender].debt;
        require(debt > 0, "SharePool: reward is zero");
        _userInfos[msg.sender].debt = 0;
        SafeTransferLib.safeTransferETH(msg.sender, debt);
        emit Claim(msg.sender, debt);
    }

    function updateRoundStatus() external {
        require(_updateRound(), "SharePool: round unchanged");

        bool done;
        do {
            done = _updateRound();
        } while (done);
    }

    function _getRealTimeS3(uint256 curr, address account)
        private
        view
        returns (bool changed, uint256 sP, uint256 sC, uint256 sN)
    {
        // +--+--+--+---------------+--------------+---------+
        // |  |  |  |     prev      | current      |  next   |
        // +--+--+--+---------------+--------------+---------+
        // |  |  |  |       sP      |      sC      |    sN   |
        // +--+--+--+---------------+--------------+---------+
        // |  |  |  |               | currentRound | inQueue |
        // +--+--+--+---------------+--------------+---------+
        // |  |  |  | PendingReward |              |         |
        // +--+--+--+---------------+--------------+---------+
        // |  Debt  |               |              |         |
        // +--------+---------------+--------------+---------+

        UserInfo storage info = _userInfos[account];
        (sP, sC, sN) = (info.sP, info.sC, info.sN);
        uint256 sCRound = info.sCRound;
        // round change
        if (sCRound < curr) {
            changed = true;
            if (sCRound + 1 == curr) {
                (sP, sC, sN) = (sC, sN, 0);
            } else if (sCRound + 2 == curr) {
                (sP, sC, sN) = (sN, 0, 0);
            } else {
                sP = sC = sN = 0;
            }
        }
    }

    function _updateRound() private returns (bool) {
        if (_needGotoNext()) {
            uint256 currId = _currentRoundId();
            RoundInfo memory info = _getCurrRoundInfo();
            lastRoundStaking = 0;
            _rounds[currId] = info;
            totalRewardUsed += info.reward;
            rewardIndex = info.rewardIndex;
            // push next round
            _rounds.push(RoundInfo({totalStaked: 0, reward: 0, rewardIndex: 0}));
            emit RoundEnd(
                currId, info.totalStaked, info.reward, info.rewardIndex, totalStaked, totalReward, totalRewardUsed
            );

            return true;
        }
        return false;
    }

    function _updateAccount() private {
        uint256 userStaked = _userInfos[msg.sender].amount;
        if (userStaked == 0) return;

        uint256 curr = _currentRoundId();
        // round change
        (bool changed, uint256 sP, uint256 sC, uint256 sN) = _getRealTimeS3(curr, msg.sender);
        if (changed) {
            UserInfo storage uinfo = _userInfos[msg.sender];
            (uinfo.sCRound, uinfo.sP, uinfo.sC, uinfo.sN) = (curr.toUint32(), uint112(sP), uint112(sC), uint112(sN));
        }
        // update debt(can claimable)
        if (curr < 2) return;

        uint256 userIndex = _userInfos[msg.sender].index;
        uint256 claimIndex = _rounds[curr - 2].rewardIndex;
        if (claimIndex <= userIndex) return;

        uint256 unclaimStaked = userStaked - (sC + sP + sN);
        uint256 unclaimReward = unclaimStaked * (claimIndex - userIndex) / 1e18;
        // update
        _userInfos[msg.sender].index = claimIndex.toUint128();
        _userInfos[msg.sender].debt += unclaimReward.toUint128();
        emit UserUpdated(msg.sender, unclaimReward, claimIndex, unclaimStaked);
    }

    function _getPrevRoundInfo() private view returns (RoundInfo memory) {
        uint256 curr = _currentRoundId();
        if (_needGotoNext()) {
            return _getCurrRoundInfo();
        } else if (curr == 0) {
            return RoundInfo(0, 0, 0);
        } else {
            return _rounds[curr - 1];
        }
    }

    function _getCurrRoundInfo() private view returns (RoundInfo memory) {
        uint256 currId = _currentRoundId();
        uint256 reward = currId == 0 ? 0 : _rewardForCurrentRound();
        uint256 staked = lastRoundStaking < 0 ? totalStaked : totalStaked - uint256(lastRoundStaking);
        uint256 newRewarwIndex = rewardIndex + (staked == 0 ? 0 : 1e18 * reward / staked);
        return RoundInfo({reward: reward.toUint128(), totalStaked: staked.toUint128(), rewardIndex: newRewarwIndex});
    }

    function _needGotoNext() private view returns (bool) {
        uint256 rounds = _rounds.length;
        uint256 nextRoundAt = round1StartAt + ROUND_DURATION * (rounds - 1);
        // update last round
        return block.timestamp >= nextRoundAt;
    }

    function _currentRoundId() private view returns (uint256) {
        return _rounds.length - 1;
    }

    function _rewardForCurrentRound() private view returns (uint256) {
        return (totalReward - totalRewardUsed) / 2; // 50% of the reward
    }

    function _subAmount(uint112 a, uint112 b) private pure returns (uint112 a1, uint112 b1) {
        return a >= b ? (a - b, uint112(0)) : (uint112(0), b - a);
    }

    modifier beforeDo() {
        _updateRound();
        _updateAccount();
        _;
    }

    receive() external payable {
        _updateRound();
        totalReward += msg.value;
    }
}

