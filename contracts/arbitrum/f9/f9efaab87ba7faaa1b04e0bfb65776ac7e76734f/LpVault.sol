// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "./Math.sol";
import "./SafeMath.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IBEP20.sol";
import "./ILpVault.sol";
import "./ILocker.sol";
import "./IEcoScore.sol";

import "./SafeToken.sol";
import "./Constant.sol";

contract LpVault is ILpVault, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    uint256 public constant MAX_HARVEST_FEE = 6000; // 60%
    uint256 public constant MAX_HARVEST_FEE_PERIOD = 30 days;
    uint256 public constant MAX_LOCKUP_PERIOD = 21 days;

    /* ========== STATE VARIABLES ========== */

    address public treasury;

    uint256 public harvestFee;
    uint256 public override harvestFeePeriod;
    uint256 public override lockupPeriod;

    uint256 public accTokenPerShare;
    uint256 public bonusEndTimestamp;
    uint256 public startTimestamp;
    uint256 public lastRewardTimestamp;

    uint256 public override rewardPerInterval;

    IBEP20 public rewardToken;
    IBEP20 public stakedToken;
    ILocker public locker;
    IEcoScore public ecoScore;

    mapping(address => UserInfo) public override userInfo;

    /* ========== INITIALIZER ========== */

    function initialize(
        IBEP20 _stakedToken,
        IBEP20 _rewardToken,
        ILocker _locker,
        IEcoScore _ecoScore,
        uint256 _rewardPerInterval,
        uint256 _startTimestamp,
        uint256 _bonusEndTimestamp,
        address _treasury
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerInterval = _rewardPerInterval;
        startTimestamp = _startTimestamp;
        bonusEndTimestamp = _bonusEndTimestamp;

        // Set the lastRewardTimestamp as the startTimestamp
        lastRewardTimestamp = startTimestamp;
        treasury = _treasury;
        locker = _locker;
        ecoScore = _ecoScore;

        harvestFee = 5000; // 50%
        harvestFeePeriod = 14 days; // 14 days
        lockupPeriod = 7 days; // 7 days

        rewardToken.approve(address(locker), uint256(-1));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        address(rewardToken).safeTransfer(address(msg.sender), _amount);
    }

    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(stakedToken), "Cannot be staked token");
        require(_tokenAddress != address(rewardToken), "Cannot be reward token");

        _tokenAddress.safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    function stopReward() external onlyOwner {
        bonusEndTimestamp = block.timestamp;
    }

    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        require(block.timestamp < _startTimestamp, "startTimestamp lower than current timestamp");
        startTimestamp = _startTimestamp;
        emit NewStartTimestamp(_startTimestamp);
    }

    function setBonusEndTimestamp(uint256 _bonusEndTimestamp) external onlyOwner {
        require(startTimestamp < _bonusEndTimestamp, "bonusEndTimestamp lower than start timestamp");
        bonusEndTimestamp = _bonusEndTimestamp;
        emit NewBonusEndTimestamp(_bonusEndTimestamp);
    }

    function updateRewardPerInterval(uint256 _rewardPerInterval) external onlyOwner {
        require(block.timestamp < startTimestamp, "Pool has started");
        rewardPerInterval = _rewardPerInterval;
        emit NewRewardPerInterval(_rewardPerInterval);
    }

    function setHarvestFee(uint256 _harvestFee) external onlyOwner {
        require(_harvestFee <= MAX_HARVEST_FEE, "LpVault::setHarvestFee::harvestFee cannot be mor than MAX");
        emit LogSetHarvestFee(harvestFee, _harvestFee);
        harvestFee = _harvestFee;
    }

    function setHarvestFeePeriod(uint256 _harvestFeePeriod) external onlyOwner {
        require(
            _harvestFeePeriod <= MAX_HARVEST_FEE_PERIOD,
            "LpVault::setHarvestFeePeriod::harvestFeePeriod cannot be more than MAX_HARVEST_FEE_PERIOD"
        );

        emit LogSetHarvestFeePeriod(harvestFeePeriod, _harvestFeePeriod);

        harvestFeePeriod = _harvestFeePeriod;
    }

    function setLockupPeriod(uint256 _lockupPeriod) external onlyOwner {
        require(
            _lockupPeriod <= MAX_LOCKUP_PERIOD,
            "LpVault::setLockupPeriod::lockupPeriod cannot be more than MAX_HARVEST_PERIOD"
        );
        require(
            _lockupPeriod <= harvestFeePeriod,
            "LpVault::setLockupPeriod::lockupPeriod cannot be more than harvestFeePeriod"
        );

        emit LogSetLockupPeriod(lockupPeriod, _lockupPeriod);

        lockupPeriod = _lockupPeriod;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "LpVault::setTreasury::cannot be zero address");

        treasury = _treasury;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint256 _amount) external override nonReentrant {
        require(_amount > 0, "amount must be greater than 0");

        _updatePool();

        UserInfo storage user = userInfo[msg.sender];

        if (user.amount > 0) {
            uint256 _userAmount = _getAdjustedAmount(address(stakedToken), user.amount);
            uint256 _pending = _userAmount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);

            if (_pending > 0) {
                user.pendingGrvAmount = user.pendingGrvAmount.add(_pending);
                user.lastClaimTime = block.timestamp;
            }
        }

        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            address(stakedToken).safeTransferFrom(address(msg.sender), address(this), _amount);
        }

        user.rewardDebt = _getAdjustedAmount(address(stakedToken), user.amount).mul(accTokenPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external override nonReentrant {
        require(_amount > 0, "amount must be greater than 0");

        _updatePool();

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        uint256 _userAmount = _getAdjustedAmount(address(stakedToken), user.amount);
        uint256 _pending = _userAmount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            address(stakedToken).safeTransfer(address(msg.sender), _amount);
        }

        if (_pending > 0) {
            user.pendingGrvAmount = user.pendingGrvAmount.add(_pending);
            user.lastClaimTime = block.timestamp;
        }

        user.rewardDebt = _getAdjustedAmount(address(stakedToken), user.amount).mul(accTokenPerShare).div(1e18);
        emit Withdraw(msg.sender, _amount);
    }

    function claim() external override {
        _updatePool();

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "nothing to claim");

        uint256 _userAmount = _getAdjustedAmount(address(stakedToken), user.amount);
        uint256 pending = _userAmount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);

        if (pending > 0) {
            user.pendingGrvAmount = user.pendingGrvAmount.add(pending);
            user.lastClaimTime = block.timestamp;
        }

        user.rewardDebt = _getAdjustedAmount(address(stakedToken), user.amount).mul(accTokenPerShare).div(1e18);
        emit Claim(msg.sender, pending);
    }

    function harvest() external override nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.pendingGrvAmount > 0, "pending grv amount is zero");
        require(block.timestamp > user.lastClaimTime.add(lockupPeriod), "not harvest period"); // 7days

        uint256 _pendingAmount = user.pendingGrvAmount;

        if (block.timestamp < user.lastClaimTime.add(harvestFeePeriod)) {
            // 14days
            uint256 currentHarvestFee = _pendingAmount.mul(harvestFee).div(10000);
            address(rewardToken).safeTransfer(treasury, currentHarvestFee);
            _pendingAmount = _pendingAmount.sub(currentHarvestFee);
        }
        address(rewardToken).safeTransfer(address(msg.sender), _pendingAmount);
        user.pendingGrvAmount = 0;

        ecoScore.updateUserClaimInfo(msg.sender, _pendingAmount);

        emit Harvest(msg.sender, _pendingAmount);
    }

    function compound() external override nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 _pendingAmount = user.pendingGrvAmount;
        require(_pendingAmount > 0, "pending grv amount is zero");

        uint256 expiryOfAccount = locker.expiryOf(msg.sender);
        require(
            user.lastClaimTime.add(harvestFeePeriod) < expiryOfAccount,
            "The expiry date is less than the harvest fee period"
        );

        locker.depositBehalf(msg.sender, _pendingAmount, expiryOfAccount);
        ecoScore.updateUserCompoundInfo(msg.sender, _pendingAmount);

        user.pendingGrvAmount = 0;
        emit Compound(msg.sender, _pendingAmount);
    }

    function emergencyWithdraw() external override nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        if (amountToTransfer > 0) {
            address(stakedToken).safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, amountToTransfer);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _updatePool() private {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        stakedTokenSupply = _getAdjustedAmount(address(stakedToken), stakedTokenSupply);

        if (stakedTokenSupply == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 timeDiff = _getTimeDiff(lastRewardTimestamp, block.timestamp);
        uint256 rewardAmount = timeDiff.mul(rewardPerInterval);

        accTokenPerShare = accTokenPerShare.add(rewardAmount.mul(1e18).div(stakedTokenSupply));
        lastRewardTimestamp = block.timestamp;
    }

    /* ========== VIEWS ========== */

    function claimableGrvAmount(address userAddress) external view override returns (uint256) {
        UserInfo memory user = userInfo[userAddress];
        uint256 _accTokenPerShare = accTokenPerShare;
        uint256 _stakedTokenSupply = stakedToken.balanceOf(address(this));
        _stakedTokenSupply = _getAdjustedAmount(address(stakedToken), _stakedTokenSupply);

        if (block.timestamp > lastRewardTimestamp && _stakedTokenSupply != 0) {
            uint256 multiplier = _getTimeDiff(lastRewardTimestamp, block.timestamp);
            uint256 rewardAmount = multiplier.mul(rewardPerInterval);
            _accTokenPerShare = _accTokenPerShare.add(rewardAmount.mul(1e18).div(_stakedTokenSupply));
        }

        uint256 _userAmount = _getAdjustedAmount(address(stakedToken), user.amount);
        return _userAmount.mul(_accTokenPerShare).div(1e18).sub(user.rewardDebt);
    }

    function depositLpAmount(address userAddress) external view override returns (uint256) {
        UserInfo memory user = userInfo[userAddress];
        return user.amount;
    }

    function _getTimeDiff(uint256 _from, uint256 _to) private view returns (uint256) {
        if (_to <= bonusEndTimestamp) {
            return _to.sub(_from);
        } else if (_from >= bonusEndTimestamp) {
            return 0;
        } else {
            return bonusEndTimestamp.sub(_from);
        }
    }

    function _getAdjustedAmount(address _token, uint256 _amount) private view returns (uint256) {
        uint256 defaultDecimal = 18;
        uint256 tokenDecimal = IBEP20(_token).decimals();

        if(defaultDecimal == tokenDecimal) {
            return _amount;
        } else if(defaultDecimal > tokenDecimal) {
            return _amount.mul(10**(defaultDecimal.sub(tokenDecimal)));
        } else {
            return _amount.div(10**(tokenDecimal.sub(defaultDecimal)));
        }
    }
}

