//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { ERC20 } from "./ERC20.sol";
import { PepeLPHelper } from "./PepeLPHelper.sol";
import { Lock, FeeDistributorInfo } from "./Structs.sol";
import { Math } from "./Math.sol";
import { IERC20 } from "./IERC20.sol";
import { IWeightedPoolFactory } from "./IWeightedPoolFactory.sol";
import { IPepeFeeDistributor } from "./IPepeFeeDistributor.sol";
import { IPepeLockUp } from "./IPepeLockUp.sol";
import { IWeightedPool } from "./IWeightedPoolFactory.sol";

contract PepeLockUp is ERC20, IPepeLockUp, Ownable, PepeLPHelper {
    ///@dev users can lockup their $PEG tokens for a fixed timeline to receive 30% of fees.
    ///@notice create different lockup contracts if more than one lock up period is to be used.
    ///Eg, 1 month lockup, 3 month lockup or 6 month lockup

    using Math for uint256;
    using Math for int256;

    IERC20 public immutable pegToken;
    IERC20 public immutable usdcToken;

    IPepeFeeDistributor public feeDistributor; ///@dev fee distributor contract that will send usdc rewards to this contract.
    uint256 public totalPegLocked; ///@dev total peg locked.
    uint256 public totalWethLocked; ///@dev total weth locked.
    uint256 public totalLpShares; ///@dev total lp shares.
    uint256 public accumulatedUsdcPerLpShare; ///@dev accumulated usdc per lp share.
    uint48 public lockDuration; ///@dev lock duration in seconds.
    uint48 public lastUpdateRewardsTimestamp; ///@dev last timestamp when rewards were updated.

    mapping(address user => Lock lock) public lockDetails;

    event Locked(
        address indexed user,
        uint256 wethAmount,
        uint256 pegAmount,
        uint256 lpAmount,
        uint48 indexed duration
    );
    event Unlocked(address indexed user, uint256 wethAmount, uint256 pegAmount, uint256 lpAmount);
    event ClaimedUsdcRewards(address indexed user, uint256 usdcAmount);
    event LockDurationModified(uint48 previousDuration, uint48 currentDuration);
    event FeeDistributorUpdated(address indexed feeDistributor);

    constructor(
        address _pegToken,
        address _usdcToken,
        address _poolFactory
    ) ERC20("Locked Pepe Token", "lPEG") PepeLPHelper(_pegToken, _poolFactory) {
        pegToken = IERC20(_pegToken);
        usdcToken = IERC20(_usdcToken);
    }

    ///@notice admin fuction to deploy and initialize the balancer pool contract.
    ///@param wethAmount amount of weth to be added to the pool.
    ///@param pegAmount amount of peg to be added to the pool.
    function initializePool(uint256 wethAmount, uint256 pegAmount, address poolAdmin) external override onlyOwner {
        require(wethAmount != 0 && pegAmount != 0, "amount cannot be 0");
        _initializePool(wethAmount, pegAmount, poolAdmin);
    }

    ///@notice update rewards accumulated to this contract.
    function updateRewards() public override {
        if (totalLpShares == 0) {
            lastUpdateRewardsTimestamp = uint48(block.timestamp);
            return;
        }
        if (uint48(block.timestamp) > lastUpdateRewardsTimestamp) {
            uint256 sharableUsdc = feeDistributor.allocateLock();
            if (sharableUsdc != 0) {
                uint256 usdcPerLp = sharableUsdc.mulDiv(1e18, totalLpShares);
                accumulatedUsdcPerLpShare += usdcPerLp;
            }
            lastUpdateRewardsTimestamp = uint48(block.timestamp);
        }
    }

    ///@notice users send weth and peg to this contract which in turn provides liquidity to the pool and locks the received lp tokens.
    ///@notice users earn usdc rewards for locking their lp tokens. The amount of usdc rewards depends on the amount of lp tokens user received.
    ///@param wethAmount amount of weth to be locked.
    ///@param pegAmount amount of peg to be locked.
    ///@param minBlpOut minimum amount of blp tokens to be received.
    function lock(uint256 wethAmount, uint256 pegAmount, uint256 minBlpOut) external override {
        require(wethAmount != 0 && pegAmount != 0, "amount cannot be 0");
        require(address(feeDistributor) != address(0), "fee distributor not set");
        require(lpTokenAddr != address(0), "pool not initialized");
        require(lockDuration != 0, "lock duration not set");
        Lock memory _userLockDetails = lockDetails[msg.sender];

        updateRewards();

        uint256 currentBlpBalance = IERC20(lpTokenAddr).balanceOf(address(this));
        _joinPool(wethAmount, pegAmount, minBlpOut);
        uint256 newBlpBalance = IERC20(lpTokenAddr).balanceOf(address(this));
        ///@dev balancer internally checks for minimum blp out.
        uint256 lpShare = newBlpBalance - currentBlpBalance;

        if (_userLockDetails.lockedAt == 0) {
            lockDetails[msg.sender] = Lock({
                pegLocked: pegAmount,
                wethLocked: wethAmount,
                totalLpShare: lpShare,
                rewardDebt: int256(lpShare.mulDiv(accumulatedUsdcPerLpShare, 1e18)),
                lockedAt: uint48(block.timestamp),
                lastLockedAt: uint48(block.timestamp),
                unlockTimestamp: uint48(block.timestamp + lockDuration)
            });
        } else {
            lockDetails[msg.sender].pegLocked += pegAmount;
            lockDetails[msg.sender].wethLocked += wethAmount;
            lockDetails[msg.sender].totalLpShare += lpShare;
            lockDetails[msg.sender].lastLockedAt = uint48(block.timestamp);
            lockDetails[msg.sender].rewardDebt += int256(lpShare.mulDiv(accumulatedUsdcPerLpShare, 1e18));
        }

        totalLpShares += lpShare;
        totalPegLocked += pegAmount;
        totalWethLocked += wethAmount;

        _mint(msg.sender, lpShare); ///mint lPeg to the user.

        emit Locked(msg.sender, wethAmount, pegAmount, lpShare, lockDuration);
    }

    ///@notice users can unlock their lp tokens after the lock duration is over.
    ///@notice this contract automatically redeems the pool lp rewards and send it to the user along with any usdc rewards.
    function unLock() external override {
        Lock memory _userLockDetails = lockDetails[msg.sender];
        require(_userLockDetails.totalLpShare != 0, "no lock found");
        require(_userLockDetails.unlockTimestamp <= uint48(block.timestamp), "lock period not expired");

        claimUsdcRewards();

        totalLpShares -= _userLockDetails.totalLpShare;
        totalPegLocked -= _userLockDetails.pegLocked;
        totalWethLocked -= _userLockDetails.wethLocked;

        _burn(msg.sender, _userLockDetails.totalLpShare);
        delete lockDetails[msg.sender];

        _exitPool(_userLockDetails.totalLpShare);

        emit Unlocked(
            msg.sender,
            _userLockDetails.wethLocked,
            _userLockDetails.pegLocked,
            _userLockDetails.totalLpShare
        );
    }

    ///@notice users can claim their usdc rewards anytime.
    function claimUsdcRewards() public override {
        Lock memory _userLockDetails = lockDetails[msg.sender];
        require(_userLockDetails.totalLpShare != 0, "no lock found");

        updateRewards();

        int256 accumulatedUsdc = int256(_userLockDetails.totalLpShare.mulDiv(accumulatedUsdcPerLpShare, 1e18));
        uint256 pendingUsdc = uint256(accumulatedUsdc - _userLockDetails.rewardDebt);
        lockDetails[msg.sender].rewardDebt = accumulatedUsdc;

        if (pendingUsdc != 0) {
            require(usdcToken.transfer(msg.sender, pendingUsdc), "transfer failed");
            emit ClaimedUsdcRewards(msg.sender, pendingUsdc);
        }
    }

    ///@notice users can determine the amount of usdc they're going to receive as rewards.
    function pendingUsdcRewards(address _user) external view override returns (uint256) {
        Lock memory _userLockDetails = lockDetails[_user];
        if (_userLockDetails.totalLpShare == 0) {
            return 0;
        }

        FeeDistributorInfo memory feeDistributorInfo;

        feeDistributorInfo.lastUpdateTimestamp = feeDistributor.getLastUpdatedTimestamp();
        feeDistributorInfo.accumulatedUsdcPerContract = feeDistributor.getAccumulatedUsdcPerContract();
        feeDistributorInfo.lastBalance = feeDistributor.getLastBalance();
        feeDistributorInfo.lockContractDebt = feeDistributor.getShareDebt(address(this));
        feeDistributorInfo.currentBalance = usdcToken.balanceOf(address(feeDistributor));

        if (uint48(block.timestamp) > feeDistributorInfo.lastUpdateTimestamp) {
            uint256 diff = feeDistributorInfo.currentBalance - feeDistributorInfo.lastBalance;
            if (diff != 0) {
                feeDistributorInfo.accumulatedUsdcPerContract += diff / 1e4;
            }
        }
        (, uint256 lockContractShare, ) = feeDistributor.getContractShares();

        int256 accumulatedLockUsdc = int256(lockContractShare * feeDistributorInfo.accumulatedUsdcPerContract);
        uint256 pendingLockUsdc = uint256(accumulatedLockUsdc - feeDistributorInfo.lockContractDebt);

        uint256 pepeLockAccumulatedUsdcPerLp = accumulatedUsdcPerLpShare;

        if (pendingLockUsdc != 0) {
            ///@notice sharable usdc = pendingStakingUsdc
            pepeLockAccumulatedUsdcPerLp += pendingLockUsdc.mulDiv(1e18, totalLpShares);
        }

        int256 accumulatedUsdc = int256(_userLockDetails.totalLpShare.mulDiv(pepeLockAccumulatedUsdcPerLp, 1e18));
        uint256 _pendingUsdc = uint256(accumulatedUsdc - _userLockDetails.rewardDebt);
        return _pendingUsdc;
    }

    ///@notice transfer is not allowed.
    function _transfer(address, address, uint256) internal pure override {
        require(false, "transfer not allowed");
    }

    ///@notice get the details of the lock of a user.
    function getLockDetails(address _user) external view override returns (Lock memory) {
        return lockDetails[_user];
    }

    ///@notice admin function to update the lock duration.
    function setLockDuration(uint48 _lockDuration) external override onlyOwner {
        require(_lockDuration != 0, "duration cannot be 0");
        uint48 previousDuration = lockDuration;
        lockDuration = _lockDuration;

        emit LockDurationModified(previousDuration, _lockDuration);
    }

    ///@notice admin function to update the fee distributor.
    function setFeeDistributor(address _feeDistributor) external override onlyOwner {
        require(_feeDistributor != address(0), "!address");
        feeDistributor = IPepeFeeDistributor(_feeDistributor);
        emit FeeDistributorUpdated(_feeDistributor);
    }

    function modifyPoolFee(uint256 newFee) external onlyOwner {
        require(newFee != 0, "fee cannot be 0");
        require(newFee < 100e18, "fee cannot be more than 100%");
        IWeightedPool(lpTokenAddr).setSwapFeePercentage(newFee);
    }
}

