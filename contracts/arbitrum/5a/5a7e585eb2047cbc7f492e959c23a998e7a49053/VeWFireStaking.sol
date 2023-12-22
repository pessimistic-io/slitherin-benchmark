// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./VeWFireToken.sol";
import "./IWFIRE.sol";

/// @title Vote Escrow WFire Staking
/// @author Promethios
/// @notice Stake FIRE to earn veWFIRE, which you can use to earn higher farm yields and gain
/// voting power. Note that unstaking any amount of FIRE will burn all of your existing veWFIRE.
contract VeWFireStaking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Info for each user
    /// `balance`: Amount of FIRE currently staked by user
    /// `rewardDebt`: The reward debt of the user
    /// `lastClaimTimestamp`: The timestamp of user's last claim or withdraw
    /// `speedUpEndTimestamp`: The timestamp when user stops receiving speed up benefits, or
    /// zero if user is not currently receiving speed up benefits
    struct UserInfo {
        uint256 balance;
        uint256 rewardDebt;
        uint256 lastClaimTimestamp;
        uint256 speedUpEndTimestamp;
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of veWFIRE
         * entitled to a user but is pending to be distributed is:
         *
         *   pendingReward = pendingBaseReward + pendingSpeedUpReward
         *
         *   pendingBaseReward = (user.balance * accVeWFirePerShare) - user.rewardDebt
         *
         *   if user.speedUpEndTimestamp != 0:
         *     speedUpCeilingTimestamp = min(block.timestamp, user.speedUpEndTimestamp)
         *     speedUpSecondsElapsed = speedUpCeilingTimestamp - user.lastClaimTimestamp
         *     pendingSpeedUpReward = speedUpSecondsElapsed * user.balance * speedUpVeWFirePerSharePerSec
         *   else:
         *     pendingSpeedUpReward = 0
         */
    }

    IERC20Upgradeable public fire;
    IWFIRE public wfire;
    VeWFireToken public veWFire;

    /// @notice The maximum limit of veWFIRE user can have as percentage points of staked FIRE
    /// For example, if user has `n` FIRE staked, they can own a maximum of `n * maxCapPct / 100` veWFIRE.
    uint256 public maxCapPct;

    /// @notice The upper limit of `maxCapPct`
    uint256 public upperLimitMaxCapPct;

    /// @notice The accrued veWFire per share, scaled to `ACC_VEWFIRE_PER_SHARE_PRECISION`
    uint256 public accVeWFirePerShare;

    /// @notice Precision of `accVeWFirePerShare`
    uint256 public ACC_VEWFIRE_PER_SHARE_PRECISION;

    /// @notice The last time that the reward variables were updated
    uint256 public lastRewardTimestamp;

    /// @notice veWFIRE per sec per FIRE staked, scaled to `VEWFIRE_PER_SHARE_PER_SEC_PRECISION`
    uint256 public veWFirePerSharePerSec;

    /// @notice Speed up veWFIRE per sec per FIRE staked, scaled to `VEWFIRE_PER_SHARE_PER_SEC_PRECISION`
    uint256 public speedUpVeWFirePerSharePerSec;

    /// @notice The upper limit of `veWFirePerSharePerSec` and `speedUpVeWFirePerSharePerSec`
    uint256 public upperLimitVeWFirePerSharePerSec;

    /// @notice Precision of `veWFirePerSharePerSec`
    uint256 public VEWFIRE_PER_SHARE_PER_SEC_PRECISION;

    /// @notice Percentage of user's current staked FIRE user has to deposit in order to start
    /// receiving speed up benefits, in parts per 100.
    /// @dev Specifically, user has to deposit at least `speedUpThreshold/100 * userStakedWFire` FIRE.
    /// The only exception is the user will also receive speed up benefits if they are depositing
    /// with zero balance
    uint256 public speedUpThreshold;

    /// @notice The length of time a user receives speed up benefits
    uint256 public speedUpDuration;

    mapping(address => UserInfo) public userInfos;

    uint256 constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    event Claim(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event UpdateMaxCapPct(address indexed user, uint256 maxCapPct);
    event UpdateRewardVars(uint256 lastRewardTimestamp, uint256 accVeWFirePerShare);
    event UpdateSpeedUpThreshold(address indexed user, uint256 speedUpThreshold);
    event UpdateVeWFirePerSharePerSec(address indexed user, uint256 veWFirePerSharePerSec);
    event Withdraw(address indexed user, uint256 withdrawAmount, uint256 burnAmount);

    /// @notice Initialize with needed parameters
    /// @param _fire Address of the FIRE token contract
    /// @param _wfire Address of the WFIRE token contract
    /// @param _veWFire Address of the veWFIRE token contract
    /// @param _veWFirePerSharePerSec veWFIRE per sec per FIRE staked, scaled to `VEWFIRE_PER_SHARE_PER_SEC_PRECISION`
    /// @param _speedUpVeWFirePerSharePerSec Similar to `_veWFirePerSharePerSec` but for speed up
    /// @param _speedUpThreshold Percentage of total staked FIRE user has to deposit receive speed up
    /// @param _speedUpDuration Length of time a user receives speed up benefits
    /// @param _maxCapPct Maximum limit of veWFIRE user can have as percentage points of staked FIRE
    function initialize(
        IERC20Upgradeable _fire,
        IWFIRE _wfire,
        VeWFireToken _veWFire,
        uint256 _veWFirePerSharePerSec,
        uint256 _speedUpVeWFirePerSharePerSec,
        uint256 _speedUpThreshold,
        uint256 _speedUpDuration,
        uint256 _maxCapPct
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        require(address(_fire) != address(0), "VeWFireStaking: unexpected zero address for _fire");
        require(
            address(_wfire) != address(0),
            "VeWFireStaking: unexpected zero address for _wfire"
        );
        require(
            address(_veWFire) != address(0),
            "VeWFireStaking: unexpected zero address for _veWFire"
        );

        upperLimitVeWFirePerSharePerSec = 1e36;
        require(
            _veWFirePerSharePerSec <= upperLimitVeWFirePerSharePerSec,
            "VeWFireStaking: expected _veWFirePerSharePerSec to be <= 1e36"
        );
        require(
            _speedUpVeWFirePerSharePerSec <= upperLimitVeWFirePerSharePerSec,
            "VeWFireStaking: expected _speedUpVeWFirePerSharePerSec to be <= 1e36"
        );

        require(
            _speedUpThreshold != 0 && _speedUpThreshold <= 100,
            "VeWFireStaking: expected _speedUpThreshold to be > 0 and <= 100"
        );

        require(
            _speedUpDuration <= 365 days,
            "VeWFireStaking: expected _speedUpDuration to be <= 365 days"
        );

        upperLimitMaxCapPct = 10000000;
        require(
            _maxCapPct != 0 && _maxCapPct <= upperLimitMaxCapPct,
            "VeWFireStaking: expected _maxCapPct to be non-zero and <= 10000000"
        );

        maxCapPct = _maxCapPct;
        speedUpThreshold = _speedUpThreshold;
        speedUpDuration = _speedUpDuration;
        fire = _fire;
        wfire = _wfire;
        veWFire = _veWFire;
        veWFirePerSharePerSec = _veWFirePerSharePerSec;
        speedUpVeWFirePerSharePerSec = _speedUpVeWFirePerSharePerSec;
        lastRewardTimestamp = block.timestamp;
        ACC_VEWFIRE_PER_SHARE_PRECISION = 1e18;
        VEWFIRE_PER_SHARE_PER_SEC_PRECISION = 1e18;
    }

    /// @notice Set maxCapPct
    /// @param _maxCapPct The new maxCapPct
    function setMaxCapPct(uint256 _maxCapPct) external onlyOwner {
        require(
            _maxCapPct > maxCapPct,
            "VeWFireStaking: expected new _maxCapPct to be greater than existing maxCapPct"
        );
        require(
            _maxCapPct != 0 && _maxCapPct <= upperLimitMaxCapPct,
            "VeWFireStaking: expected new _maxCapPct to be non-zero and <= 10000000"
        );
        maxCapPct = _maxCapPct;
        emit UpdateMaxCapPct(_msgSender(), _maxCapPct);
    }

    /// @notice Set veWFirePerSharePerSec
    /// @param _veWFirePerSharePerSec The new veWFirePerSharePerSec
    function setVeWFirePerSharePerSec(uint256 _veWFirePerSharePerSec) external onlyOwner {
        require(
            _veWFirePerSharePerSec <= upperLimitVeWFirePerSharePerSec,
            "VeWFireStaking: expected _veWFirePerSharePerSec to be <= 1e36"
        );
        updateRewardVars();
        veWFirePerSharePerSec = _veWFirePerSharePerSec;
        emit UpdateVeWFirePerSharePerSec(_msgSender(), _veWFirePerSharePerSec);
    }

    /// @notice Set speedUpThreshold
    /// @param _speedUpThreshold The new speedUpThreshold
    function setSpeedUpThreshold(uint256 _speedUpThreshold) external onlyOwner {
        require(
            _speedUpThreshold != 0 && _speedUpThreshold <= 100,
            "VeWFireStaking: expected _speedUpThreshold to be > 0 and <= 100"
        );
        speedUpThreshold = _speedUpThreshold;
        emit UpdateSpeedUpThreshold(_msgSender(), _speedUpThreshold);
    }

    /// @notice Deposits WFIRE to start staking for veWFIRE. Note that any pending veWFIRE
    /// will also be claimed in the process.
    /// @param _amount The amount of WFIRE to deposit
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount > 0, "VeWFireStaking: expected deposit amount to be greater than zero");

        _deposit(_amount);

        IERC20Upgradeable(address(wfire)).safeTransferFrom(_msgSender(), address(this), _amount);
    }

    /// @notice Deposits FIRE to start staking for veWFIRE. Note that any pending veWFIRE
    /// will also be claimed in the process.
    /// @param _fireAmount The amount of FIRE to deposit
    function depositFire(uint256 _fireAmount) external nonReentrant {
        require(_fireAmount > 0, "VeWFireStaking: expected deposit amount to be greater than zero");

        uint256 _amount = (_fireAmount * wfire.MAX_WFIRE_SUPPLY()) / fire.totalSupply();

        _deposit(_amount);

        fire.safeTransferFrom(_msgSender(), address(this), _fireAmount);
        if (fire.allowance(address(this), address(wfire)) < _fireAmount) {
            fire.approve(address(wfire), MAX_INT);
        }
        _amount = wfire.deposit(_fireAmount);
    }

    function getTotalFireStaked() external view returns (uint256 fireAmount, uint256 percent) {
        fireAmount =
            (IERC20Upgradeable(address(wfire)).balanceOf(address(this)) * fire.totalSupply()) /
            wfire.MAX_WFIRE_SUPPLY();
        percent = (fireAmount * 10000) / fire.totalSupply();
    }

    function getUserStakedFire(address user) external view returns (uint256 fireAmount) {
        fireAmount = (userInfos[user].balance * fire.totalSupply()) / wfire.MAX_WFIRE_SUPPLY();
    }

    function _deposit(uint256 _amount) internal {
        updateRewardVars();

        UserInfo storage userInfo = userInfos[_msgSender()];

        if (_getUserHasNonZeroBalance(_msgSender())) {
            // Transfer to the user their pending veWFIRE before updating their UserInfo
            _claim();

            // We need to update user's `lastClaimTimestamp` to now to prevent
            // passive veWFIRE accrual if user hit their max cap.
            userInfo.lastClaimTimestamp = block.timestamp;

            uint256 userStakedWFire = userInfo.balance;

            // User is eligible for speed up benefits if `_amount` is at least
            // `speedUpThreshold / 100 * userStakedWFire`
            if (_amount * 100 >= speedUpThreshold * userStakedWFire) {
                userInfo.speedUpEndTimestamp = block.timestamp + speedUpDuration;
            }
        } else {
            // If user is depositing with zero balance, they will automatically
            // receive speed up benefits
            userInfo.speedUpEndTimestamp = block.timestamp + speedUpDuration;
            userInfo.lastClaimTimestamp = block.timestamp;
        }

        userInfo.balance = userInfo.balance + _amount;
        userInfo.rewardDebt =
            (accVeWFirePerShare * userInfo.balance) /
            ACC_VEWFIRE_PER_SHARE_PRECISION;

        emit Deposit(_msgSender(), _amount);
    }

    /// @notice Withdraw staked FIRE. Note that unstaking any amount of FIRE means you will
    /// lose all of your current veWFIRE.
    /// @param _amount The amount of WFIRE to unstake
    /// @param _unwrap unwrap wfire or not
    function withdraw(uint256 _amount, bool _unwrap) external {
        require(_amount > 0, "VeWFireStaking: expected withdraw amount to be greater than zero");

        UserInfo storage userInfo = userInfos[_msgSender()];

        require(
            userInfo.balance >= _amount,
            "VeWFireStaking: cannot withdraw greater amount of WFIRE than currently staked"
        );
        updateRewardVars();

        // Note that we don't need to claim as the user's veWFIRE balance will be reset to 0
        userInfo.balance = userInfo.balance - _amount;
        userInfo.rewardDebt =
            (accVeWFirePerShare * userInfo.balance) /
            ACC_VEWFIRE_PER_SHARE_PRECISION;
        userInfo.lastClaimTimestamp = block.timestamp;
        userInfo.speedUpEndTimestamp = 0;

        // Burn the user's current veWFIRE balance
        uint256 userVeWFireBalance = veWFire.balanceOf(_msgSender());
        veWFire.burnFrom(_msgSender(), userVeWFireBalance);

        // Send user their requested amount of staked FIRE
        if (_unwrap) {
            uint256 fireAmount = wfire.burn(_amount);
            fire.safeTransfer(_msgSender(), fireAmount);
        } else {
            IERC20Upgradeable(address(wfire)).safeTransfer(_msgSender(), _amount);
        }

        emit Withdraw(_msgSender(), _amount, userVeWFireBalance);
    }

    /// @notice Claim any pending veWFIRE
    function claim() external {
        require(
            _getUserHasNonZeroBalance(_msgSender()),
            "VeWFireStaking: cannot claim veWFIRE when no WFIRE is staked"
        );
        updateRewardVars();
        _claim();
    }

    /// @notice Get the pending amount of veWFIRE for a given user
    /// @param _user The user to lookup
    /// @return The number of pending veWFIRE tokens for `_user`
    function getPendingVeWFire(address _user) public view returns (uint256) {
        if (!_getUserHasNonZeroBalance(_user)) {
            return 0;
        }

        UserInfo memory user = userInfos[_user];

        // Calculate amount of pending base veWFIRE
        uint256 _accVeWFirePerShare = accVeWFirePerShare;
        uint256 secondsElapsed = block.timestamp - lastRewardTimestamp;
        if (secondsElapsed > 0) {
            _accVeWFirePerShare =
                _accVeWFirePerShare +
                (secondsElapsed * veWFirePerSharePerSec * ACC_VEWFIRE_PER_SHARE_PRECISION) /
                VEWFIRE_PER_SHARE_PER_SEC_PRECISION;
        }
        uint256 pendingBaseVeWFire = (_accVeWFirePerShare * user.balance) /
            ACC_VEWFIRE_PER_SHARE_PRECISION -
            user.rewardDebt;

        // Calculate amount of pending speed up veWFIRE
        uint256 pendingSpeedUpVeWFire;
        if (user.speedUpEndTimestamp != 0) {
            uint256 speedUpCeilingTimestamp = block.timestamp > user.speedUpEndTimestamp
                ? user.speedUpEndTimestamp
                : block.timestamp;
            uint256 speedUpSecondsElapsed = speedUpCeilingTimestamp - user.lastClaimTimestamp;
            uint256 speedUpAccVeWFirePerShare = speedUpSecondsElapsed *
                speedUpVeWFirePerSharePerSec;
            pendingSpeedUpVeWFire =
                (speedUpAccVeWFirePerShare * user.balance) /
                VEWFIRE_PER_SHARE_PER_SEC_PRECISION;
        }

        uint256 pendingVeWFire = pendingBaseVeWFire + pendingSpeedUpVeWFire;

        // Get the user's current veWFIRE balance
        uint256 userVeWFireBalance = veWFire.balanceOf(_user);

        // This is the user's max veWFIRE cap multiplied by 100
        uint256 scaledUserMaxVeWFireCap = user.balance * maxCapPct;

        if (userVeWFireBalance * 100 >= scaledUserMaxVeWFireCap) {
            // User already holds maximum amount of veWFIRE so there is no pending veWFIRE
            return 0;
        } else if ((userVeWFireBalance + pendingVeWFire) * 100 > scaledUserMaxVeWFireCap) {
            return (scaledUserMaxVeWFireCap - userVeWFireBalance * 100) / 100;
        } else {
            return pendingVeWFire;
        }
    }

    /// @notice Update reward variables
    function updateRewardVars() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (IERC20Upgradeable(address(wfire)).balanceOf(address(this)) == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 secondsElapsed = block.timestamp - lastRewardTimestamp;
        accVeWFirePerShare =
            accVeWFirePerShare +
            (secondsElapsed * veWFirePerSharePerSec * ACC_VEWFIRE_PER_SHARE_PRECISION) /
            VEWFIRE_PER_SHARE_PER_SEC_PRECISION;
        lastRewardTimestamp = block.timestamp;

        emit UpdateRewardVars(lastRewardTimestamp, accVeWFirePerShare);
    }

    /// @notice Checks to see if a given user currently has staked FIRE
    /// @param _user The user address to check
    /// @return Whether `_user` currently has staked FIRE
    function _getUserHasNonZeroBalance(address _user) private view returns (bool) {
        return userInfos[_user].balance > 0;
    }

    /// @dev Helper to claim any pending veWFIRE
    function _claim() private {
        uint256 veWFireToClaim = getPendingVeWFire(_msgSender());

        UserInfo storage userInfo = userInfos[_msgSender()];

        userInfo.rewardDebt =
            (accVeWFirePerShare * userInfo.balance) /
            ACC_VEWFIRE_PER_SHARE_PRECISION;

        // If user's speed up period has ended, reset `speedUpEndTimestamp` to 0
        if (userInfo.speedUpEndTimestamp != 0 && block.timestamp >= userInfo.speedUpEndTimestamp) {
            userInfo.speedUpEndTimestamp = 0;
        }

        if (veWFireToClaim > 0) {
            userInfo.lastClaimTimestamp = block.timestamp;

            veWFire.mint(_msgSender(), veWFireToClaim);
            emit Claim(_msgSender(), veWFireToClaim);
        }
    }
}

