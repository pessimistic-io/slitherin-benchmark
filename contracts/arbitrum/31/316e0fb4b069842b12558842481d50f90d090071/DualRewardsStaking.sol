// SPDX-License-Identifier: UNLICENSED
// © Copyright AutoDCA. All Rights Reserved
pragma solidity 0.8.9;

import "./IERC20.sol";
import "./Math.sol";
import "./Ownable2Step.sol";
import "./AccessControl.sol";

import "./ICustomSwapRouter.sol";
import "./IFeeCollector.sol";
import "./CollectFees.sol";

contract DualRewardsStaking is AccessControl, CollectFees {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct Staker {
        uint256 balance;
        uint256 usdcRewardIndex;
        uint256 xdcaRewardIndex;
        uint256 pendingUsdcReward;
        uint256 pendingXdcaReward;
    }
    struct StakerResponse {
        uint256 balance;
        uint256 pendingUsdcReward;
        uint256 pendingXdcaReward;
        uint256 claimableUsdcReward;
        uint256 claimableXdcaReward;
    }
    struct DistributionSchedule {
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
    }

    IERC20 public stakingToken;
    IERC20 public usdcRewardToken;
    IERC20 public xdcaRewardToken;
    ICustomSwapRouter public usdcToXdcaSwapRouter;
    uint256 public totalStakedBalance;
    uint256 public usdcLastDistributed;
    uint256 public usdcGlobalRewardIndex;
    uint256 public xdcaLastDistributed;
    uint256 public xdcaGlobalRewardIndex;
    uint256 private constant globalRewardIndexPrecision = 1e24;
    DistributionSchedule public usdcRewardDistributionSchedule;
    DistributionSchedule public xdcaRewardDistributionSchedule;
    uint256 public feeOnClaiming; // 1e6 precision
    mapping(address => Staker) public stakers;

    event Stake(address tokensFrom, address indexed account, uint256 amount);
    event Claim(
        address indexed account,
        uint256 usdcAmount,
        uint256 xdcaAmount
    );
    event Compound(address indexed account, uint256 amount);
    event Unstake(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event EmergencyWithdraw(IERC20 tokenToWithdraw, uint256 amountToWithdraw);
    event SetUnbondingDuration(uint256 newUnbondingDuration);
    event SetFeeOnClaiming(uint256 newFeeOnClaiming);
    event SetUsdcDistributionSchedule(
        DistributionSchedule newUsdcRewardDistributionSchedule
    );
    event SetXdcaDistributionSchedule(
        DistributionSchedule newXdcaRewardDistributionSchedule
    );

    constructor(
        ICustomSwapRouter usdcToXdcaSwapRouter_,
        address feeCollectorAddress_,
        address feeOracleAddress_,
        IERC20 stakingToken_,
        IERC20 usdcRewardToken_,
        IERC20 xdcaRewardToken_,
        uint256 feeOnClaiming_,
        DistributionSchedule memory usdcRewardDistributionSchedule_,
        DistributionSchedule memory xdcaRewardDistributionSchedule_
    ) CollectFees(feeCollectorAddress_, feeOracleAddress_) {
        usdcToXdcaSwapRouter = usdcToXdcaSwapRouter_;
        stakingToken = stakingToken_;
        usdcRewardToken = usdcRewardToken_;
        xdcaRewardToken = xdcaRewardToken_;
        feeOnClaiming = feeOnClaiming_;
        usdcRewardDistributionSchedule = usdcRewardDistributionSchedule_;
        xdcaRewardDistributionSchedule = xdcaRewardDistributionSchedule_;
    }

    function grantOperator(address to) public onlyOwner {
        _grantRole(OPERATOR_ROLE, to);
    }

    function revokeOperator(address to) public onlyOwner {
        _revokeRole(OPERATOR_ROLE, to);
    }

    function setFeeOnClaiming(uint feeOnClaiming_) public onlyOwner {
        feeOnClaiming = feeOnClaiming_;
        emit SetFeeOnClaiming(feeOnClaiming_);
    }

    function setUsdcDistributionSchedule(
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 rewardToDistribute
    ) public onlyOwner {
        require(startTimestamp < endTimestamp, "Invalid timestamps");
        usdcGlobalRewardIndex = _computeUsdcReward();
        usdcLastDistributed = block.timestamp;
        usdcRewardDistributionSchedule = DistributionSchedule(
            startTimestamp,
            endTimestamp,
            rewardToDistribute
        );
        emit SetUsdcDistributionSchedule(usdcRewardDistributionSchedule);
    }

    function setXdcaDistributionSchedule(
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 rewardToDistribute
    ) public onlyOwner {
        require(startTimestamp < endTimestamp, "Invalid timestamps");
        xdcaGlobalRewardIndex = _computeXdcaReward();
        xdcaLastDistributed = block.timestamp;
        xdcaRewardDistributionSchedule = DistributionSchedule(
            startTimestamp,
            endTimestamp,
            rewardToDistribute
        );
        emit SetXdcaDistributionSchedule(xdcaRewardDistributionSchedule);
    }

    function emergencyWithdraw(
        IERC20 tokenToWithdraw,
        uint256 amountToWithdraw
    ) public onlyOwner {
        if (address(tokenToWithdraw) == address(0)) {
            address payable to = payable(msg.sender);
            to.transfer(amountToWithdraw);
        } else {
            tokenToWithdraw.transfer(msg.sender, amountToWithdraw);
        }
        emit EmergencyWithdraw(tokenToWithdraw, amountToWithdraw);
    }

    function stakeForMany(
        uint256[] calldata amounts,
        address[] calldata users
    ) public onlyRole(OPERATOR_ROLE) {
        require(
            amounts.length == users.length,
            "Amount and users length mismatch"
        );
        for (uint256 i = 0; i < amounts.length; i++) {
            _stake(amounts[i], users[i], msg.sender);
        }
    }

    function stakeFor(
        uint256 amount,
        address user
    ) public onlyRole(OPERATOR_ROLE) {
        _stake(amount, user, msg.sender);
    }

    function stake(uint256 amount) public payable collectFee {
        _stake(amount, msg.sender, msg.sender);
    }

    function claim() public payable collectFee {
        Staker storage st = stakers[msg.sender];

        _updateRewards();

        (
            uint256 pendingUsdcReward_,
            uint256 pendingXdcaReward_
        ) = _computeStakerRewards(
                msg.sender,
                usdcGlobalRewardIndex,
                xdcaGlobalRewardIndex
            );
        require(
            pendingUsdcReward_ > 0 || pendingXdcaReward_ > 0,
            "Nothing to claim"
        );
        st.usdcRewardIndex = usdcGlobalRewardIndex;
        st.xdcaRewardIndex = xdcaGlobalRewardIndex;
        st.pendingUsdcReward = 0;
        st.pendingXdcaReward = 0;

        (
            uint256 claimableUsdcAmountToTransfer,
            uint256 claimableXdcaAmountToTransfer
        ) = _computeClaimableRewards(pendingUsdcReward_, pendingXdcaReward_);
        uint256 usdcFee = pendingUsdcReward_ - claimableUsdcAmountToTransfer;
        uint256 xdcaFee = pendingXdcaReward_ - claimableXdcaAmountToTransfer;
        if (usdcFee > 0) {
            usdcRewardToken.approve(feeCollectorAddress, usdcFee);
            IFeeCollector(feeCollectorAddress).receiveToken(
                address(usdcRewardToken),
                usdcFee
            );
        }
        if (xdcaFee > 0) {
            xdcaRewardToken.approve(feeCollectorAddress, xdcaFee);
            IFeeCollector(feeCollectorAddress).receiveToken(
                address(xdcaRewardToken),
                xdcaFee
            );
        }
        if (claimableUsdcAmountToTransfer > 0) {
            usdcRewardToken.transfer(msg.sender, claimableUsdcAmountToTransfer);
        }
        if (claimableXdcaAmountToTransfer > 0) {
            xdcaRewardToken.transfer(msg.sender, claimableXdcaAmountToTransfer);
        }
        emit Claim(
            msg.sender,
            claimableUsdcAmountToTransfer,
            claimableXdcaAmountToTransfer
        );
    }

    function compound(uint256 beliefPrice) public payable collectFee {
        Staker storage st = stakers[msg.sender];

        _updateRewards();

        (
            uint256 pendingUsdcReward_,
            uint256 pendingXdcaReward_
        ) = _computeStakerRewards(
                msg.sender,
                usdcGlobalRewardIndex,
                xdcaGlobalRewardIndex
            );
        require(
            pendingUsdcReward_ > 0 || pendingXdcaReward_ > 0,
            "Nothing to compound"
        );
        IERC20(usdcRewardToken).approve(
            address(usdcToXdcaSwapRouter),
            pendingUsdcReward_
        );
        uint256 stakingTokenAmountFromUsdcSwap = usdcToXdcaSwapRouter
            .exchangeToken(pendingUsdcReward_, beliefPrice);
        st.usdcRewardIndex = usdcGlobalRewardIndex;
        st.xdcaRewardIndex = xdcaGlobalRewardIndex;
        st.pendingUsdcReward = 0;
        st.pendingXdcaReward = 0;
        st.balance += stakingTokenAmountFromUsdcSwap + pendingXdcaReward_;

        totalStakedBalance +=
            stakingTokenAmountFromUsdcSwap +
            pendingXdcaReward_;
        emit Compound(
            msg.sender,
            stakingTokenAmountFromUsdcSwap + pendingXdcaReward_
        );
    }

    function unstake(uint256 amountToUnstake) public payable collectFee {
        Staker storage st = stakers[msg.sender];
        require(st.balance > 0, "No staked tokens");

        _updateRewards();

        (
            uint256 pendingUsdcReward_,
            uint256 pendingXdcaReward_
        ) = _computeStakerRewards(
                msg.sender,
                usdcGlobalRewardIndex,
                xdcaGlobalRewardIndex
            );

        require(
            amountToUnstake <= st.balance,
            "You cannot unstake more then you are staking"
        );
        st.usdcRewardIndex = usdcGlobalRewardIndex;
        st.xdcaRewardIndex = xdcaGlobalRewardIndex;
        st.pendingUsdcReward = pendingUsdcReward_;
        st.pendingXdcaReward = pendingXdcaReward_;
        st.balance -= amountToUnstake;

        totalStakedBalance -= amountToUnstake;
        stakingToken.transfer(msg.sender, amountToUnstake);

        emit Unstake(msg.sender, amountToUnstake);
    }

    function getStaker(
        address staker
    ) public view returns (StakerResponse memory) {
        Staker memory st = stakers[staker];
        uint256 _usdcGlobalRewardIndex = _computeUsdcReward();
        uint256 _xdcaGlobalRewardIndex = _computeXdcaReward();
        (
            uint256 pendingUsdcReward_,
            uint256 pendingXdcaReward_
        ) = _computeStakerRewards(
                staker,
                _usdcGlobalRewardIndex,
                _xdcaGlobalRewardIndex
            );

        (
            uint256 claimableUsdcReward_,
            uint256 claimableXdcaReward_
        ) = _computeClaimableRewards(pendingUsdcReward_, pendingXdcaReward_);

        StakerResponse memory stakerResponse = StakerResponse({
            balance: st.balance,
            pendingUsdcReward: pendingUsdcReward_,
            pendingXdcaReward: pendingXdcaReward_,
            claimableUsdcReward: claimableUsdcReward_,
            claimableXdcaReward: claimableXdcaReward_
        });

        return stakerResponse;
    }

    function _updateRewards() internal {
        usdcGlobalRewardIndex = _computeUsdcReward();
        usdcLastDistributed = block.timestamp;
        xdcaGlobalRewardIndex = _computeXdcaReward();
        xdcaLastDistributed = block.timestamp;
    }

    function _computeClaimableRewards(
        uint256 pendingUsdcReward,
        uint256 pendingXdcaReward
    ) internal view returns (uint256, uint256) {
        return (
            ((1e6 - feeOnClaiming) * pendingUsdcReward) / 1e6,
            ((1e6 - feeOnClaiming) * pendingXdcaReward) / 1e6
        );
    }

    function _computeReward(
        DistributionSchedule memory rewardDistributionSchedule,
        uint256 globalRewardIndex,
        uint256 lastDistributed
    ) internal view returns (uint256) {
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

    function _computeUsdcReward() internal view returns (uint256) {
        return
            _computeReward(
                usdcRewardDistributionSchedule,
                usdcGlobalRewardIndex,
                usdcLastDistributed
            );
    }

    function _computeXdcaReward() internal view returns (uint256) {
        return
            _computeReward(
                xdcaRewardDistributionSchedule,
                xdcaGlobalRewardIndex,
                xdcaLastDistributed
            );
    }

    function _computeStakerRewards(
        address staker,
        uint256 usdcGlobalRewardIndex_,
        uint256 xdcaGlobalRewardIndex_
    ) internal view returns (uint256, uint256) {
        uint256 pendingUsdcReward = stakers[staker].balance *
            usdcGlobalRewardIndex_ -
            stakers[staker].balance *
            stakers[staker].usdcRewardIndex;
        uint256 pendingXdcaReward = stakers[staker].balance *
            xdcaGlobalRewardIndex_ -
            stakers[staker].balance *
            stakers[staker].xdcaRewardIndex;
        return (
            stakers[staker].pendingUsdcReward +
                pendingUsdcReward /
                globalRewardIndexPrecision,
            stakers[staker].pendingXdcaReward +
                pendingXdcaReward /
                globalRewardIndexPrecision
        );
    }

    function _stake(
        uint256 amount,
        address staker,
        address transferTokensFrom
    ) internal {
        require(amount > 0, "Amount must be greater than 0");

        uint256 balance = stakingToken.balanceOf(transferTokensFrom);
        require(amount <= balance, "Insufficient balance");

        _updateRewards();

        Staker storage st = stakers[staker];

        (
            uint256 pendingUsdcReward_,
            uint256 pendingXdcaReward_
        ) = _computeStakerRewards(
                msg.sender,
                usdcGlobalRewardIndex,
                xdcaGlobalRewardIndex
            );
        st.usdcRewardIndex = usdcGlobalRewardIndex;
        st.xdcaRewardIndex = xdcaGlobalRewardIndex;
        st.pendingUsdcReward = pendingUsdcReward_;
        st.pendingXdcaReward = pendingXdcaReward_;
        st.balance += amount;

        totalStakedBalance += amount;
        stakingToken.transferFrom(transferTokensFrom, address(this), amount);

        emit Stake(transferTokensFrom, staker, amount);
    }
}

