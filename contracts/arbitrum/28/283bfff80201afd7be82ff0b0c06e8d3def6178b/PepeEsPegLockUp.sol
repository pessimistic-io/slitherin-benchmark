//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable2Step } from "./Ownable2Step.sol";
import { ERC20 } from "./ERC20.sol";
import { Group, Contract, FeeDistributorInfo } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { Math } from "./Math.sol";
import { IPepeEsPegLockUp } from "./IPepeEsPegLockUp.sol";
import { IPepeEsPegRewardPoolV2 } from "./IPepeEsPegRewardPoolV2.sol";
import { IEsPepeToken } from "./IEsPepeToken.sol";
import { IPepeFeeDistributorV2 } from "./IPepeFeeDistributorV2.sol";
import { EsPegLock } from "./Structs.sol";
import { PepeEsPegLPHelper } from "./PepeEsPegLPHelper.sol";

contract PepeEsPegLockUp is ERC20, IPepeEsPegLockUp, Ownable2Step, PepeEsPegLPHelper {
    ///@dev users can lockup their $esPEG tokens for a 1.5 months.

    using Math for uint256;
    using Math for int256;

    /********** IMMUTABLES ************/
    IERC20 public immutable pegToken;
    IERC20 public immutable wethToken;
    IERC20 public immutable usdcToken;
    IEsPepeToken public immutable esPegToken;

    /*****VARIABLES******/
    IPepeEsPegRewardPoolV2 public rewardPoolV2; // rewardPoolV2 contract.
    IPepeFeeDistributorV2 public feeDistributorV2; ///@dev distributes usdc rewards to this contract.

    address[] public allUsers; ///@dev all users who have locked up.
    uint256 public totalEsPegLocked; ///@dev total EsPeg locked.
    uint256 public totalWethLocked; ///@dev total weth locked.
    uint256 public totalLpShares; ///@dev total lp shares.
    uint256 public accumulatedUsdcPerLpShare; ///@dev accumulated usdc per lp share.
    uint48 public lockUpDuration; ///@dev lock duration in seconds.
    uint48 public lastUpdateRewardsTimestamp; ///@dev last timestamp when rewards were updated.
    uint8 public lockGroupId; ///@dev the id of the lock group in feeDistributorV2.

    mapping(address user => mapping(uint256 lockId => EsPegLock lock)) public lockUpDetails; ///@dev lock up details.
    mapping(address user => uint256 lockId) public userLockCount; ///@dev user lock count.
    mapping(address user => uint256 index) public userIndex; ///@dev user index in allUsers array.
    mapping(address => bool) public isUser; ///@dev is user who has locked up.

    /*********EVENTS ***********/
    event RewardPoolChanged(address indexed poolAddress);
    event LockDurationChanged(uint48 indexed previousLockDuration, uint48 indexed lockDuration);
    event Locked(
        address indexed user,
        uint256 wethAmount,
        uint256 esPegAmount,
        uint256 lpAmount,
        uint48 indexed duration
    );
    event Unlocked(address indexed user, uint256 wethAmount, uint256 pegAmount, uint256 lpAmount);
    event ClaimedUsdcRewards(address user, uint256 amountClaimed);
    event LockGroupIdChanged(uint8 indexed previousLockGroupId, uint8 indexed lockGroupId);
    event FeeDistributorUpdated(address indexed previousFeeDistributor, address indexed newFeeDistributor);

    constructor(
        address pegToken_,
        address esPegToken_,
        address wethToken_,
        address usdcToken_,
        address rewardPool_,
        address feeDistributorV2_
    ) ERC20("Locked PepeEsPeg Token", "lEsPeg") {
        pegToken = IERC20(pegToken_);
        esPegToken = IEsPepeToken(esPegToken_);
        wethToken = IERC20(wethToken_);
        usdcToken = IERC20(usdcToken_);
        rewardPoolV2 = IPepeEsPegRewardPoolV2(rewardPool_);
        feeDistributorV2 = IPepeFeeDistributorV2(feeDistributorV2_);
        lockUpDuration = 45 days;
        lockGroupId = 2;
    }

    ///@notice lock weth with esPeg tokens to receive usdc rewards.
    ///@param wethAmount amount of weth to lock.
    ///@param esPegAmount amount of esPeg to lock.
    ///@param minBlpOut minimum amount of blp tokens to receive.
    function lock(uint256 wethAmount, uint256 esPegAmount, uint256 minBlpOut) external override {
        require(wethAmount != 0 && esPegAmount != 0, "zero amount");
        require(esPegToken.transferFrom(msg.sender, address(this), esPegAmount), "esPeg transferFrom failed");
        require(wethToken.transferFrom(msg.sender, address(this), wethAmount), "weth transferFrom failed");

        updateRewards();
        uint256 userLockCount_ = ++userLockCount[msg.sender];

        rewardPoolV2.fundContractOperation(esPegAmount);

        uint256 currentBlpBalance = IERC20(LP_TOKEN).balanceOf(address(this));
        _joinPool(wethAmount, esPegAmount, minBlpOut);

        ///check blp balance and calculate blp received, update user blp balance
        uint256 newBlpBalance = IERC20(LP_TOKEN).balanceOf(address(this));

        uint256 lpShare = newBlpBalance - currentBlpBalance;

        lockUpDetails[msg.sender][userLockCount_] = EsPegLock({
            esPegLocked: esPegAmount,
            wethLocked: wethAmount,
            totalLpShare: lpShare,
            rewardDebt: int256(lpShare.mulDiv(accumulatedUsdcPerLpShare, 1e18)),
            lockedAt: uint48(block.timestamp),
            unlockTimestamp: uint48(block.timestamp + lockUpDuration)
        });

        if (!isUser[msg.sender]) {
            userIndex[msg.sender] = allUsers.length;
            allUsers.push(msg.sender);
            isUser[msg.sender] = true;
        }

        totalLpShares += lpShare;
        totalEsPegLocked += esPegAmount;
        totalWethLocked += wethAmount;

        _mint(msg.sender, lpShare); ///mint lPeg to the user.

        ///@dev user provides $esPeg + $WETH and we provide liquidity on their behalf $PEG + $WETH.
        emit Locked(msg.sender, wethAmount, esPegAmount, lpShare, lockUpDuration);
    }

    ///@notice unlock lp tokens and claim all rewards.
    ///@param lockId the id of the lock.
    function unlock(uint256 lockId) external override {
        EsPegLock memory _userLockDetails = lockUpDetails[msg.sender][lockId];
        require(_userLockDetails.totalLpShare != 0, "no lock found");
        require(_userLockDetails.unlockTimestamp <= uint48(block.timestamp), "lock period not expired");

        claimUsdcRewards(lockId);

        totalLpShares -= _userLockDetails.totalLpShare;
        totalEsPegLocked -= _userLockDetails.esPegLocked;
        totalWethLocked -= _userLockDetails.wethLocked;

        _burn(msg.sender, _userLockDetails.totalLpShare);
        esPegToken.burn(address(this), _userLockDetails.esPegLocked);

        delete lockUpDetails[msg.sender][lockId];
        isUser[msg.sender] = false;

        uint256 i = 1;
        uint256 userLockCount_ = userLockCount[msg.sender];
        for (; i <= userLockCount_; ) {
            if (lockUpDetails[msg.sender][i].totalLpShare != 0) {
                isUser[msg.sender] = true;
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (!isUser[msg.sender]) {
            uint256 userIndex_ = userIndex[msg.sender];
            allUsers[userIndex_] = allUsers[allUsers.length - 1];

            if (userIndex_ != allUsers.length - 1) {
                userIndex[allUsers[userIndex_]] = userIndex_;
            } else {
                delete userIndex[msg.sender];
            }

            allUsers.pop();
        }

        // call exit pool
        _exitPool(_userLockDetails.totalLpShare);

        emit Unlocked(
            msg.sender,
            _userLockDetails.wethLocked,
            _userLockDetails.esPegLocked,
            _userLockDetails.totalLpShare
        );
    }

    ///@notice update rewards accumulated to this contract.
    function updateRewards() public override {
        if (totalLpShares == 0) {
            lastUpdateRewardsTimestamp = uint48(block.timestamp);
            return;
        }
        if (uint48(block.timestamp) > lastUpdateRewardsTimestamp) {
            uint256 sharableUsdc = feeDistributorV2.transferUsdcToContract(lockGroupId, address(this));
            if (sharableUsdc != 0) {
                uint256 usdcPerLp = sharableUsdc.mulDiv(1e18, totalLpShares);
                accumulatedUsdcPerLpShare += usdcPerLp;
            }
            lastUpdateRewardsTimestamp = uint48(block.timestamp);
        }
    }

    ///@notice claim usdc rewards for a specific lock.
    ///@param lockId the id of the lock.
    function claimUsdcRewards(uint256 lockId) public override {
        EsPegLock memory _userLockDetails = lockUpDetails[msg.sender][lockId];
        if (_userLockDetails.totalLpShare == 0) return;
        updateRewards();

        int256 accumulatedUsdc = int256(_userLockDetails.totalLpShare.mulDiv(accumulatedUsdcPerLpShare, 1e18));
        uint256 pendingUsdc = uint256(accumulatedUsdc - _userLockDetails.rewardDebt);
        lockUpDetails[msg.sender][lockId].rewardDebt = accumulatedUsdc;

        if (pendingUsdc != 0) {
            require(usdcToken.transfer(msg.sender, pendingUsdc), "transfer failed");
            emit ClaimedUsdcRewards(msg.sender, pendingUsdc);
        }
    }

    ///@notice claim usdc rewards for all locks.
    function claimAllUsdcRewards() external override {
        uint256 userLockCount_ = userLockCount[msg.sender];
        for (uint256 i = 1; i <= userLockCount_; ) {
            claimUsdcRewards(i);

            unchecked {
                ++i;
            }
        }
    }

    ///@notice get pending usdc rewards for a specific lock.
    ///@param user the user address.
    ///@param lockId the id of the lock.
    function pendingUsdcRewards(address user, uint256 lockId) public view override returns (uint256) {
        EsPegLock memory _userLockDetails = lockUpDetails[user][lockId];
        if (_userLockDetails.totalLpShare == 0) return 0;

        uint256 pendingUsdcFromFeeDistributor = feeDistributorV2.contractPendingUsdcRewards(address(this), lockGroupId);

        uint256 accumulatedUsdcPerLpShare_ = accumulatedUsdcPerLpShare;

        if (pendingUsdcFromFeeDistributor != 0) {
            accumulatedUsdcPerLpShare_ += pendingUsdcFromFeeDistributor.mulDiv(1e18, totalLpShares);
        }

        int256 accumulatedUsdcForUser = int256(_userLockDetails.totalLpShare.mulDiv(accumulatedUsdcPerLpShare_, 1e18));
        return uint256(accumulatedUsdcForUser - _userLockDetails.rewardDebt);
    }

    ///@notice get total pending usdc rewards for a user.
    ///@param user the user address.
    function getTotalPendingUsdcRewards(address user) external view override returns (uint256) {
        uint256 userLockCount_ = userLockCount[user];
        uint256 totalPendingUsdc;
        for (uint256 i = 1; i <= userLockCount_; ) {
            totalPendingUsdc += pendingUsdcRewards(user, i);

            unchecked {
                ++i;
            }
        }

        return totalPendingUsdc;
    }

    ///@notice update the Peg reward pool address.
    function setRewardPool(address _rewardPool) external override onlyOwner {
        require(_rewardPool != address(0), "!rewardPoolV2");
        rewardPoolV2 = IPepeEsPegRewardPoolV2(_rewardPool);
        emit RewardPoolChanged(_rewardPool);
    }

    ///@notice update the lock group id if changed is in the fee distributor.
    ///@param _lockGroupId the new lock group id in Fee distributor.
    function updateLockGroupId(uint8 _lockGroupId) external onlyOwner {
        require(_lockGroupId != 0, "!lockGroupId");
        emit LockGroupIdChanged(lockGroupId, _lockGroupId);
        lockGroupId = _lockGroupId;
    }

    ///@notice update the lock duration.
    ///@param _lockDuration the new lock duration.
    function setLockDuration(uint48 _lockDuration) external onlyOwner {
        require(_lockDuration != 0, "!lockDuration");

        uint48 prevlockDuration = lockUpDuration;
        lockUpDuration = _lockDuration;

        emit LockDurationChanged(prevlockDuration, _lockDuration);
    }

    ///@notice update the fee distributor address.
    ///@param _feeDistributor the new fee distributor address.
    function setFeeDistributor(address _feeDistributor) external override onlyOwner {
        require(_feeDistributor != address(0), "!address");
        emit FeeDistributorUpdated(address(feeDistributorV2), _feeDistributor);
        feeDistributorV2 = IPepeFeeDistributorV2(_feeDistributor);
    }

    ///@notice transfer is not allowed.
    function _transfer(address, address, uint256) internal pure override {
        require(false, "transfer not allowed");
    }

    ///@notice get the details of the lock of a user.
    function getLockDetails(address _user, uint256 lockId) external view override returns (EsPegLock memory) {
        return lockUpDetails[_user][lockId];
    }

    ///@notice an array of all lockers.
    function getAllUsers() external view override returns (address[] memory) {
        return allUsers;
    }
}

