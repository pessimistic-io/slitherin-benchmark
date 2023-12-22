// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./State.sol";
import "./Administration.sol";
import "./Math.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./IStaking.sol";
import "./IWhitelist.sol";

abstract contract Base is State, Administration {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint constant public PRICE_DENOMINATOR = 10 ** 18;
    uint constant public MINIMUM_DURATION = 3600; // 1 hour in seconds
    uint constant public GLOBAL_MINIMUM_FILL_PERCENTAGE = 10; // 10%
    uint constant public SENDBACK_THRESHOLD = 10 ** 14; // 0.0001 ETH

    IERC20 public token; 
    uint public tokenAmountToSell;
    uint public startTime;
    uint public endTime;
    uint public minimumFillPercentage;
    uint public minimumFill;
    uint public fundRaised;
    uint public tokenAmountSold;
    uint public tokenAmountLeft;
    uint public minimumOrderSize;   // in wei
    uint[] public maximumAllocation;
    uint public totalWithdrawnAmount;

    uint public maximumFunding;
    uint public stakingTokenReward;
    IERC20 public stakingToken;
    bool public RemainingStakingTokenWithdrawnByPlatformAdmin;

    // currently ClaimLockDuration is not used, claiming is availible only after endTime
    uint public claimLockDuration;  // in seconds

    uint public claimAvailableTimestamp;

    uint[] public minimumStakeTiers;
    IStaking public stakingContract;

    IWhitelist public whitelistContract;

    mapping (address => uint) public userToReserve;
    mapping (address => uint) public amountPaid;

    event Refund(address user, uint refundAmount);
    event Claim(address user, uint claimAmount, uint stakingTokenRewardAmount);

    event ChangeClaimAvailableTimestamp(uint newClaimAvailableTimestamp);

    constructor(IERC20 _token, 
                uint _tokenAmountToSell, 
                uint _startTime, 
                uint _endTime, 
                uint _minimumFillPercentage, 
                uint _minimumOrderSize, 
                uint[] memory _maximumAllocation, 
                uint[] memory _minimumStakeTiers,
                uint _claimLockDuration,
                address payable _assetManager, 
                address _projectAdmin, 
                address _platformAdmin,
                IStaking _stakingContract,
                IWhitelist _whitelistContract) 
    {
        _checkTime(_startTime, _endTime);
        _checkMinimumFillPercentage(_minimumFillPercentage);
        
        token = _token;
        tokenAmountToSell = _tokenAmountToSell;
        startTime = _startTime;
        endTime = _endTime;
        minimumFillPercentage = _minimumFillPercentage;
        minimumOrderSize = _minimumOrderSize;
        maximumAllocation = _maximumAllocation;
        minimumStakeTiers = _minimumStakeTiers;
        claimLockDuration = _claimLockDuration;
        assetManager = _assetManager;
        projectAdmin = _projectAdmin;
        platformAdmin = _platformAdmin;

        fundRaised = 0;
        tokenAmountSold = 0;
        tokenAmountLeft = tokenAmountToSell;

        stakingTokenReward = 0;
        RemainingStakingTokenWithdrawnByPlatformAdmin = false;

        stakingContract = IStaking(_stakingContract);
        whitelistContract = IWhitelist(_whitelistContract);
        
        claimAvailableTimestamp = _endTime;
        emit ChangeClaimAvailableTimestamp(claimAvailableTimestamp);
    }

    function changeToken(address newToken) public onlyProjectAdmin onlyDuringInitialized{
        token = IERC20(newToken);
    }

    function _checkTime(uint _startTime, uint _endTime) internal view {
        require(_endTime.sub(_startTime) >= MINIMUM_DURATION, "Base: DURATION_SHORT");
        require(_startTime > block.timestamp, "Base: START_TIME_PASSED");
    }

    function changeTime(uint newStartTime, uint newEndTime) public onlyProjectAdmin onlyDuringInitialized {
        _checkTime(newStartTime, newEndTime);
        startTime = newStartTime;
        endTime = newEndTime;
        claimAvailableTimestamp = endTime;
        emit ChangeClaimAvailableTimestamp(claimAvailableTimestamp);
    }

    function changeTokenAmountToSell(uint newTokenAmountToSell) public onlyProjectAdmin onlyDuringInitialized {
        tokenAmountToSell = newTokenAmountToSell;
        tokenAmountLeft = newTokenAmountToSell;
    }

    function _checkMinimumFillPercentage(uint _minimumFillPercentage) internal pure {
        require(_minimumFillPercentage >= GLOBAL_MINIMUM_FILL_PERCENTAGE, "Base: MIN_FILL_PERCENTAGE_LOW");
        require(_minimumFillPercentage <= 100, "Base: MIN_FILL_PERCENTAGE_HIGH");
    }

    function _checkStakeTiers() internal view{
        require(minimumStakeTiers.length == maximumAllocation.length, "Base: STAKE_TIERS_AND_MAX_ALLOCATIONS_NOT_SAME_LENGTH");
        for (uint index = 1; index < minimumStakeTiers.length; index++) {
            require(minimumStakeTiers[index - 1] > minimumStakeTiers[index], "Base: STAKE_TIERS_NOT_SORTED");
            require(maximumAllocation[index - 1] >= maximumAllocation[index], "Base: MAX_ALLOCATIONS_NOT_SORTED");
        }
        require(minimumStakeTiers[minimumStakeTiers.length - 1] == 0, "Base: NO_ZERO_STAKE_TIER");
    }

    function changeMinimumFillPercentage(uint newMinimumFillPercentage) public onlyProjectAdmin onlyDuringInitialized {
        _checkMinimumFillPercentage(newMinimumFillPercentage);
        minimumFillPercentage = newMinimumFillPercentage;
    }

    function changeMinimumOrderSize(uint newMinimumOrderSize) public onlyProjectAdmin onlyDuringInitialized {
        minimumOrderSize = newMinimumOrderSize;
    }

    function changeClaimLockDuration(uint newClaimLockDuration) public onlyProjectAdmin onlyDuringInitialized {
        claimLockDuration = newClaimLockDuration;
    }

    function changeTiersAndMaximumAllocation(uint[] memory newMinimumStakeTiers, uint[] memory newMaximumAllocation) public onlyPlatformAdmin onlyDuringInitialized {
        maximumAllocation = newMaximumAllocation;
        minimumStakeTiers = newMinimumStakeTiers;
    }

    function changeStakingContract(IStaking newStakingContract) public onlyPlatformAdmin onlyDuringInitialized {
        stakingContract = newStakingContract;
    } 

    function changeWhitelistContract(IWhitelist newWhitelistContract) public onlyPlatformAdmin onlyDuringInitialized {
        whitelistContract = newWhitelistContract;
    }

    function setStakingTokenReward(uint _stakingTokenReward, IERC20 _stakingToken) public onlyPlatformAdmin {
        require(state == StateType.INITIALIZED || state == StateType.READY, "ONLY_DURING_INITIALIZED_OR_READY");
        stakingTokenReward = _stakingTokenReward;
        stakingToken = _stakingToken;
    }

    function setPoolReady() public virtual onlyProjectAdmin onlyDuringInitialized {
        _checkTime(startTime, endTime);
        _checkMinimumFillPercentage(minimumFillPercentage);
        _checkStakeTiers();
        require(token.balanceOf(address(this)) >= tokenAmountToSell, "Base: NOT_ENOUGH_PROJECT_TOKENS");
        minimumFill = tokenAmountToSell.mul(minimumFillPercentage).div(100);

        claimAvailableTimestamp = endTime;
        emit ChangeClaimAvailableTimestamp(claimAvailableTimestamp);
        
        state = StateType.READY;
    }

    function setPoolOngoing() public onlyPlatformAdmin onlyDuringReady {
        require(block.timestamp >= startTime, "Base: TOO_EARLY");
        if (stakingTokenReward > 0) {
            require(stakingToken.balanceOf(address(this)) >= stakingTokenReward, "Base: NOT_ENOUGH_STAKING_TOKEN");
        }
        state = StateType.ONGOING;
    }

    function _setPoolSuccess() internal {
        state = StateType.SUCCESS;
    }

    function _setPoolFail() internal {
        state = StateType.FAIL;
    }

    function setPoolFinish() public onlyDuringOngoing {
        if (block.timestamp > endTime) {
            if (tokenAmountSold >= minimumFill) {
                _setPoolSuccess();
            } else {
                _setPoolFail();
            }
        }
        else {
            if (tokenAmountSold == tokenAmountToSell) {
                _setPoolSuccess();
            }
        }
    }

    function _getUserTier() internal view returns (uint) {
        uint tier = whitelistContract.getTier(msg.sender);
        require(tier > 0, "Base: NOT_WHITELISTED");
        return tier;
    }

    function _getStakeTierMaxAllocation(uint tier) internal view returns (uint){
            uint tierStakeAlloc = maximumAllocation[tier - 1];

            /* uint stake = stakingContract.getStake(msg.sender);
            uint stakingAlloc;
            for (uint index = 0; index < minimumStakeTiers.length; index++) {
                if(stake >= minimumStakeTiers[index]){
                    stakingAlloc = maximumAllocation[index];
                    break;
                }
            } */

           /*  return Math.min(stakingAlloc, tierStakeAlloc); */
           return tierStakeAlloc;
    }

    function withdrawFund() public virtual onlyDuringSuccess onlyAssetManager {
        assetManager.transfer(address(this).balance);
    }

    function withdrawTokenAfterFail() public onlyDuringFail onlyAssetManager {
        token.transfer(assetManager, token.balanceOf(address(this)));
    }

    function withdrawRemainingTokens() public virtual onlyDuringSuccess onlyAssetManager {
        uint tokenRemainingToDistribute = tokenAmountSold.sub(totalWithdrawnAmount);
        uint remaining = token.balanceOf(address(this)).sub(tokenRemainingToDistribute);
        token.transfer(assetManager, remaining);
    }

    function withdrawRemainingStakingToken(address stakingTokenWallet) public onlyPlatformAdmin onlyDuringSuccess {
        if (!RemainingStakingTokenWithdrawnByPlatformAdmin) {
            uint totalReward = stakingTokenReward.mul(fundRaised).div(maximumFunding);
            uint remaining = stakingTokenReward.sub(totalReward);
            RemainingStakingTokenWithdrawnByPlatformAdmin = true;
            stakingToken.safeTransfer(stakingTokenWallet, remaining);
        }
    }

    function withdrawStakingTokenAfterFail(address stakingTokenWallet) public onlyPlatformAdmin onlyDuringFail {
        stakingToken.safeTransfer(stakingTokenWallet, stakingToken.balanceOf(address(this)));
    }

    function refund() public virtual onlyDuringFail {
        uint returnAmount = amountPaid[msg.sender];
        require(returnAmount > 0, "Base: ALREADY_REFUNDED");
        amountPaid[msg.sender] = 0;
        userToReserve[msg.sender] = 0;
        msg.sender.transfer(returnAmount);
        emit Refund(msg.sender, returnAmount);
    }

    function withdrawReservedTokens() public virtual onlyDuringSuccess {
        require(block.timestamp >= claimAvailableTimestamp, "Base: CLAIMING_NOT_STARTED");
        uint reservedAmount = userToReserve[msg.sender];
        uint userAmountPaid = amountPaid[msg.sender];
        require(reservedAmount > 0, "Base: RESERVE_BALANCE_ZERO");
        userToReserve[msg.sender] = 0;
        amountPaid[msg.sender] = 0;
        token.safeTransfer(msg.sender, reservedAmount);
        totalWithdrawnAmount = totalWithdrawnAmount.add(reservedAmount);
 
        uint rewardForUser = 0;
        if (stakingTokenReward > 0) {
            rewardForUser = stakingTokenReward.mul(userAmountPaid).div(maximumFunding);
            stakingToken.safeTransfer(msg.sender, rewardForUser);
        } 

        emit Claim(msg.sender, reservedAmount, rewardForUser);
    }

    function emergencyChangeClaimAvailable(uint newClaimAvailableTimestamp) public onlyPlatformAdmin {
        claimAvailableTimestamp = newClaimAvailableTimestamp;
        emit ChangeClaimAvailableTimestamp(claimAvailableTimestamp);
    }

    function emergencyPause() public onlyPlatformAdmin {
        require(state != StateType.SUCCESS && state != StateType.FAIL && state != StateType.PAUSED, "Base: STATE_IS_FINAL");
        stateBeforePause = state;
        state = StateType.PAUSED;
    }

    function emergencyUnpause() public onlyPlatformAdmin onlyDuringPaused {
        state = stateBeforePause;
    }

    function emergencyCancel() public onlyPlatformAdmin onlyDuringPaused {
        state = StateType.FAIL;
    }
}
