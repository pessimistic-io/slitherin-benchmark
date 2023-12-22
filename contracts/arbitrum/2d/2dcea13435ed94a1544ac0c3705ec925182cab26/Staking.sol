// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./Math.sol";
import "./Ownable.sol";
import "./ISwapRouter.sol";

contract Staking is Ownable {
    struct Staker {
        uint256 balance;
        uint256 rewardIndex;
        uint256 pendingReward;
    }
    struct StakerResponse {
        uint256 balance;
        uint256 pendingReward;
        uint256 claimableReward;
    }
    struct Unbonding {
        uint256 amount;
        uint256 endTimestamp;
    }
    struct DistributionSchedule {
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
    }

    ISwapRouter public uniswapV3Router;
    address public constant DCA = 0x965F298E4ade51C0b0bB24e3369deB6C7D5b3951;
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    uint256 public totalStakedBalance;
    uint256 public lastDistributed;
    uint256 private constant globalRewardIndexPrecision = 1e24;
    uint256 private globalRewardIndex;
    DistributionSchedule public rewardDistributionSchedule;
    uint256 public unbondingDuration;
    uint256 public feeOnClaiming; // 1e6 precision
    mapping(address => Staker) public stakers;
    mapping(address => Unbonding) public unbondings;

    event Stake(address tokensFrom, address indexed account, uint256 amount);
    event Claim(address indexed account, uint256 amount);
    event Compound(address indexed account, uint256 amount);
    event Unstake(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event EmergencyWithdraw(IERC20 tokenToWithdraw, uint256 amountToWithdraw);
    event SetUnbondingDuration(uint256 newUnbondingDuration);
    event SetFeeOnClaiming(uint256 newFeeOnClaiming);
    event SetDistributionSchedule(
        DistributionSchedule newRewardDistributionSchedule
    );

    constructor(
        ISwapRouter uniswapV3Router_,
        IERC20 stakingToken_,
        IERC20 rewardToken_,
        uint256 feeOnClaiming_,
        uint256 unbondingDuration_,
        uint256 startTimestamp_,
        uint256 endTimestamp_,
        uint256 rewardToDistribute_
    ) {
        uniswapV3Router = uniswapV3Router_;
        stakingToken = stakingToken_;
        rewardToken = rewardToken_;
        feeOnClaiming = feeOnClaiming_;
        unbondingDuration = unbondingDuration_;
        rewardDistributionSchedule = DistributionSchedule(
            startTimestamp_,
            endTimestamp_,
            rewardToDistribute_
        );
    }

    function setUnbondingDuration(uint256 unbondingDuration_) public onlyOwner {
        unbondingDuration = unbondingDuration_;
        emit SetUnbondingDuration(unbondingDuration_);
    }

    function setFeeOnClaiming(uint feeOnClaiming_) public onlyOwner {
        feeOnClaiming = feeOnClaiming_;
        emit SetFeeOnClaiming(feeOnClaiming_);
    }

    function setDistributionSchedule(
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 rewardToDistribute
    ) public onlyOwner {
        require(startTimestamp < endTimestamp, "Invalid timestamps");
        uint256 _globalRewardIndex = _computeReward();
        lastDistributed = block.timestamp;
        globalRewardIndex = _globalRewardIndex;
        rewardDistributionSchedule = DistributionSchedule(
            startTimestamp,
            endTimestamp,
            rewardToDistribute
        );
        emit SetDistributionSchedule(rewardDistributionSchedule);
    }

    function emergencyWithdraw(
        IERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) public onlyOwner {
        tokenToWithdraw.transfer(msg.sender, amountToWithdraw);
        emit EmergencyWithdraw(tokenToWithdraw, amountToWithdraw);
    }

    function stakeFor(uint256 amount, address user) public {
        _stake(amount, user, msg.sender);
    }

    function stake(uint256 amount) public {
        _stake(amount, msg.sender, msg.sender);
    }

    function claim() public {
        Staker storage st = stakers[msg.sender];

        uint256 _globalRewardIndex = _computeReward();
        lastDistributed = block.timestamp;
        globalRewardIndex = _globalRewardIndex;

        uint256 pendingReward_ = _computeStakerReward(
            msg.sender,
            _globalRewardIndex
        );
        require(pendingReward_ > 0, "Nothing to claim");
        st.rewardIndex = _globalRewardIndex;
        st.pendingReward = 0;

        uint256 claimableAmountToTransfer = _computeClaimableReward(
            pendingReward_
        );
        if (claimableAmountToTransfer > 0) {
            rewardToken.transfer(msg.sender, claimableAmountToTransfer);
        }
        emit Claim(msg.sender, claimableAmountToTransfer);
    }

    function compound(uint256 beliefPrice) public {
        Staker storage st = stakers[msg.sender];

        uint256 _globalRewardIndex = _computeReward();
        lastDistributed = block.timestamp;
        globalRewardIndex = _globalRewardIndex;

        uint256 pendingReward_ = _computeStakerReward(
            msg.sender,
            _globalRewardIndex
        );
        require(pendingReward_ > 0, "Nothing to compound");
        uint256 stakingTokenAmount = _swapForStakingToken(
            pendingReward_,
            beliefPrice
        );
        st.rewardIndex = _globalRewardIndex;
        st.pendingReward = 0;
        st.balance += stakingTokenAmount;

        totalStakedBalance += stakingTokenAmount;
        emit Compound(msg.sender, stakingTokenAmount);
    }

    function unstake(uint256 amountToUnstake) public {
        Staker storage st = stakers[msg.sender];
        require(st.balance > 0, "No staked tokens");

        uint256 _globalRewardIndex = _computeReward();
        lastDistributed = block.timestamp;
        globalRewardIndex = _globalRewardIndex;

        uint256 pendingReward_ = _computeStakerReward(
            msg.sender,
            _globalRewardIndex
        );

        require(
            amountToUnstake <= st.balance,
            "You cannot unstake more then you are staking"
        );

        st.rewardIndex = _globalRewardIndex;
        st.pendingReward = pendingReward_;
        st.balance -= amountToUnstake;

        Unbonding storage un = unbondings[msg.sender];
        un.amount += amountToUnstake;
        un.endTimestamp = block.timestamp + unbondingDuration;

        totalStakedBalance -= amountToUnstake;
        emit Unstake(msg.sender, amountToUnstake);
    }

    function withdraw() public {
        Unbonding storage un = unbondings[msg.sender];
        uint256 amount = un.amount;
        require(amount > 0, "Nothing to withdraw");
        require(
            un.endTimestamp <= block.timestamp,
            "You cannot withraw before unbonding ends"
        );
        delete unbondings[msg.sender];
        stakingToken.transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function getStaker(
        address staker
    ) public view returns (StakerResponse memory) {
        Staker memory st = stakers[staker];
        uint256 globalRewardIndex_ = _computeReward();
        uint256 pendingReward_ = _computeStakerReward(
            staker,
            globalRewardIndex_
        );
        StakerResponse memory stakerResponse = StakerResponse({
            balance: st.balance,
            pendingReward: pendingReward_,
            claimableReward: _computeClaimableReward(pendingReward_)
        });

        return stakerResponse;
    }

    function getUnbonding(
        address staker
    ) public view returns (Unbonding memory) {
        return unbondings[staker];
    }

    function _computeClaimableReward(
        uint256 pendingReward
    ) internal view returns (uint256) {
        return ((1e6 - feeOnClaiming) * pendingReward) / 1e6;
    }

    function _computeReward() internal view returns (uint256) {
        if (totalStakedBalance == 0) {
            return globalRewardIndex;
        }

        DistributionSchedule memory schedule = rewardDistributionSchedule;
        if (
            schedule.endTime < lastDistributed ||
            schedule.startTime > block.timestamp
        ) {
            return globalRewardIndex;
        }

        uint256 end = Math.min(schedule.endTime, block.timestamp);
        uint256 start = Math.max(schedule.startTime, lastDistributed);

        uint256 secondsFromLastDistribution = end - start;
        uint256 totalSecondsInDistributionSchedule = schedule.endTime -
            schedule.startTime;

        uint256 rewardDistributedAmount = (schedule.amount *
            secondsFromLastDistribution) / totalSecondsInDistributionSchedule;

        return
            globalRewardIndex +
            ((globalRewardIndexPrecision * rewardDistributedAmount) /
                totalStakedBalance);
    }

    function _computeStakerReward(
        address staker,
        uint256 globalRewardIndex_
    ) internal view returns (uint256) {
        uint256 pendingReward = stakers[staker].balance *
            globalRewardIndex_ -
            stakers[staker].balance *
            stakers[staker].rewardIndex;

        return
            stakers[staker].pendingReward +
            pendingReward /
            globalRewardIndexPrecision;
    }

    function _stake(
        uint256 amount,
        address staker,
        address transferTokensFrom
    ) internal {
        require(amount > 0, "Amount must be greater than 0");

        uint256 balance = stakingToken.balanceOf(transferTokensFrom);
        require(amount <= balance, "Insufficient balance");

        uint256 _globalRewardIndex = _computeReward();
        lastDistributed = block.timestamp;
        globalRewardIndex = _globalRewardIndex;

        Staker storage st = stakers[staker];

        uint256 pendingReward_ = _computeStakerReward(
            staker,
            _globalRewardIndex
        );
        st.rewardIndex = _globalRewardIndex;
        st.pendingReward = pendingReward_;
        st.balance += amount;

        totalStakedBalance += amount;
        stakingToken.transferFrom(transferTokensFrom, address(this), amount);

        emit Stake(transferTokensFrom, staker, amount);
    }

    function _swapForStakingToken(
        uint256 amount,
        uint256 beliefPrice
    ) internal returns (uint256) {
        IERC20(USDC).approve(address(uniswapV3Router), amount);
        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(USDC, WETH, DCA),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: (amount * beliefPrice) / 1e6
            });
        uint256 received = uniswapV3Router.exactInput(params);
        return received;
    }
}

