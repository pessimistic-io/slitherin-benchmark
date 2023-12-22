// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./library_Math.sol";
import "./SafeMath.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./WhitelistUpgradeable.sol";
import "./SafeToken.sol";
import "./Constant.sol";

import "./ILocker.sol";
import "./IRebateDistributor.sol";
import "./IGRVDistributor.sol";

contract Locker is ILocker, WhitelistUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    uint256 public constant LOCK_UNIT_BASE = 7 days;
    uint256 public constant LOCK_UNIT_MAX = 2 * 365 days; // 2 years
    uint256 public constant LOCK_UNIT_MIN = 4 weeks; // 4 weeks = 1 month

    /* ========== STATE VARIABLES ========== */

    address public GRV;
    IGRVDistributor public grvDistributor;
    IRebateDistributor public rebateDistributor;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public expires;

    uint256 public override totalBalance;

    uint256 private _lastTotalScore;
    uint256 private _lastSlope;
    uint256 private _lastTimestamp;
    mapping(uint256 => uint256) private _slopeChanges; // Timestamp => Expire amount / Max Period
    mapping(address => Constant.LockInfo[]) private _lockHistory;
    mapping(address => uint256) private _firstLockTime;

    /* ========== VARIABLE GAP ========== */

    uint256[49] private __gap;

    /* ========== INITIALIZER ========== */

    function initialize(address _grvTokenAddress) external initializer {
        __WhitelistUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _lastTimestamp = block.timestamp;

        require(_grvTokenAddress != address(0), "Locker: GRV address can't be zero");
        GRV = _grvTokenAddress;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /// @notice grvDistributor 변경
    /// @dev owner address 에서만 요청 가능
    /// @param _grvDistributor 새로운 grvDistributor address
    function setGRVDistributor(address _grvDistributor) external override onlyOwner {
        require(_grvDistributor != address(0), "Locker: invalid grvDistributor address");
        grvDistributor = IGRVDistributor(_grvDistributor);
        emit GRVDistributorUpdated(_grvDistributor);
    }

    /// @notice Rebate distributor 변경
    /// @dev owner address 에서만 요청 가능
    /// @param _rebateDistributor 새로운 rebate distributor address
    function setRebateDistributor(address _rebateDistributor) external override onlyOwner {
        require(_rebateDistributor != address(0), "Locker: invalid grvDistributor address");
        rebateDistributor = IRebateDistributor(_rebateDistributor);
        emit RebateDistributorUpdated(_rebateDistributor);
    }

    /// @notice 긴급상황시 Deposit, Withdraw를 막기 위한 pause
    function pause() external override onlyOwner {
        _pause();
        emit Pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
        emit Unpause();
    }

    /* ========== VIEWS ========== */

    /// @notice View amount of locked GRV
    /// @param account Account address
    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    /// @notice View lock expire time of account
    /// @param account Account address
    function expiryOf(address account) external view override returns (uint256) {
        return expires[account];
    }

    /// @notice View withdrawable amount that lock had been expired
    /// @param account Account address
    function availableOf(address account) external view override returns (uint256) {
        return expires[account] < block.timestamp ? balances[account] : 0;
    }

    /// @notice View Lock Unit Max value
    function getLockUnitMax() external view override returns (uint256) {
        return LOCK_UNIT_MAX;
    }

    /// @notice View total score
    /// @dev 마지막 계산된 total score 시점에서부터 지난 시간 만큼의 deltaScore을 구한 뒤 차감하여, 현재의 total score 값을 구하여 반환한다.
    function totalScore() public view override returns (uint256 score, uint256 slope) {
        score = _lastTotalScore;
        slope = _lastSlope;

        uint256 prevTimestamp = _lastTimestamp;
        uint256 nextTimestamp = _onlyTruncateExpiry(_lastTimestamp).add(LOCK_UNIT_BASE);
        while (nextTimestamp < block.timestamp) {
            uint256 deltaScore = nextTimestamp.sub(prevTimestamp).mul(slope);
            score = score < deltaScore ? 0 : score.sub(deltaScore);
            slope = slope.sub(_slopeChanges[nextTimestamp]);

            prevTimestamp = nextTimestamp;
            nextTimestamp = nextTimestamp.add(LOCK_UNIT_BASE);
        }
        uint256 deltaScore = block.timestamp > prevTimestamp ? block.timestamp.sub(prevTimestamp).mul(slope) : 0;
        score = score > deltaScore ? score.sub(deltaScore) : 0;
    }

    /// @notice Calculate time-weighted balance of account (유저의 현재 score 반환)
    /// @dev 남은시간 대비 현재까지의 score 계산
    ///      Expiry time 에 가까워질수록 score 감소
    ///      if 만료일 = 현재시간, score = 0
    /// @param account Account of which the balance will be calculated
    function scoreOf(address account) external view override returns (uint256) {
        if (expires[account] < block.timestamp) return 0;
        return expires[account].sub(block.timestamp).mul(balances[account].div(LOCK_UNIT_MAX));
    }

    /// @notice 남은 만료 기간 반환
    /// @param account user address
    function remainExpiryOf(address account) external view override returns (uint256) {
        if (expires[account] < block.timestamp) return 0;
        return expires[account].sub(block.timestamp);
    }

    /// @notice 예상 만료일에 따른 남은 만료 기간 반환
    /// @param expiry lock period
    function preRemainExpiryOf(uint256 expiry) external view override returns (uint256) {
        if (expiry <= block.timestamp) return 0;
        expiry = _truncateExpiry(expiry);
        require(
            expiry > block.timestamp && expiry <= _truncateExpiry(block.timestamp + LOCK_UNIT_MAX),
            "Locker: preRemainExpiryOf: invalid expiry"
        );
        return expiry.sub(block.timestamp);
    }

    /// @notice Pre-Calculate time-weighted balance of account (유저의 예상 score 반환)
    /// @dev 주어진 GRV수량과 연장만료일에 따라 사전에 미리 veGrv점수를 구하기 위함
    /// @param account Account of which the balance will be calculated
    /// @param amount Amount of GRV, Lock GRV 또는 Claim GRV수량을 전달받는다.
    /// @param expiry Extended expiry, 연장될 만료일을 전달 받는다.
    /// @param option 0 = lock, 1 = claim, 2 = extend, 3 = lock more
    function preScoreOf(
        address account,
        uint256 amount,
        uint256 expiry,
        Constant.EcoScorePreviewOption option
    ) external view override returns (uint256) {
        if (option == Constant.EcoScorePreviewOption.EXTEND && expires[account] < block.timestamp) return 0;
        uint256 expectedAmount = balances[account];
        uint256 expectedExpires = expires[account];

        if (option == Constant.EcoScorePreviewOption.LOCK) {
            expectedAmount = expectedAmount.add(amount);
            expectedExpires = _truncateExpiry(expiry);
        } else if (option == Constant.EcoScorePreviewOption.LOCK_MORE) {
            expectedAmount = expectedAmount.add(amount);
        } else if (option == Constant.EcoScorePreviewOption.EXTEND) {
            expectedExpires = _truncateExpiry(expiry);
        }
        if (expectedExpires <= block.timestamp) {
            return 0;
        }
        return expectedExpires.sub(block.timestamp).mul(expectedAmount.div(LOCK_UNIT_MAX));
    }

    /// @notice account 의 특정 시점의 score 를 계산
    /// @param account account address
    /// @param timestamp timestamp
    function scoreOfAt(address account, uint256 timestamp) external view override returns (uint256) {
        uint256 count = _lockHistory[account].length;
        if (count == 0 || _lockHistory[account][count - 1].expiry <= timestamp) return 0;

        for (uint256 i = count - 1; i < uint256(-1); i--) {
            Constant.LockInfo storage lock = _lockHistory[account][i];

            if (lock.timestamp <= timestamp) {
                return lock.expiry <= timestamp ? 0 : lock.expiry.sub(timestamp).mul(lock.amount).div(LOCK_UNIT_MAX);
            }
        }
        return 0;
    }

    function lockInfoOf(address account) external view override returns (Constant.LockInfo[] memory) {
        return _lockHistory[account];
    }

    function firstLockTimeInfoOf(address account) external view override returns (uint256) {
        return _firstLockTime[account];
    }

    /// @notice 전달받은 expiry 기간과 가까운 목요일을 기준 만료일로 정한 후 7일 더 추가하여 최종 만료일을 반환한다.
    /// @param time expiry time
    function truncateExpiry(uint256 time) external view override returns (uint256) {
        return _truncateExpiry(time);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice Deposit GRV (Lock)
    /// @dev deposit amount와 만료일을 받아 해당 내용 업데이트, total score 업데이트, total balance 업데이트 , 유저 정보 업데이트
    /// @param amount GRV token amount to deposit
    /// @param expiry Lock expire time
    function deposit(uint256 amount, uint256 expiry) external override nonReentrant whenNotPaused {
        require(amount > 0, "Locker: invalid amount");
        expiry = balances[msg.sender] == 0 ? _truncateExpiry(expiry) : expires[msg.sender];
        require(
            block.timestamp < expiry && expiry <= _truncateExpiry(block.timestamp + LOCK_UNIT_MAX),
            "Locker: deposit: invalid expiry"
        );
        if (balances[msg.sender] == 0) {
            uint256 lockPeriod = expiry > block.timestamp ? expiry.sub(block.timestamp) : 0;
            require(lockPeriod >= LOCK_UNIT_MIN, "Locker: The expiry does not meet the minimum period");
            _firstLockTime[msg.sender] = block.timestamp;
        }
        _slopeChanges[expiry] = _slopeChanges[expiry].add(amount.div(LOCK_UNIT_MAX));
        _updateTotalScore(amount, expiry);

        GRV.safeTransferFrom(msg.sender, address(this), amount);
        totalBalance = totalBalance.add(amount);

        balances[msg.sender] = balances[msg.sender].add(amount);
        expires[msg.sender] = expiry;

        _updateGRVDistributorBoostedInfo(msg.sender);

        _lockHistory[msg.sender].push(
            Constant.LockInfo({timestamp: block.timestamp, amount: balances[msg.sender], expiry: expires[msg.sender]})
        );

        emit Deposit(msg.sender, amount, expiry);
    }

    /**
     * @notice Extend for expiry of `msg.sender`
     * @param nextExpiry New Lock expire time
     */
    function extendLock(uint256 nextExpiry) external override nonReentrant whenNotPaused {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Locker: zero balance");

        uint256 prevExpiry = expires[msg.sender];
        nextExpiry = _truncateExpiry(nextExpiry);
        require(block.timestamp < prevExpiry, "Locker: expired lock");
        require(
            Math.max(prevExpiry, block.timestamp) < nextExpiry &&
                nextExpiry <= _truncateExpiry(block.timestamp + LOCK_UNIT_MAX),
            "Locker: invalid expiry time"
        );

        uint256 slopeChange = (_slopeChanges[prevExpiry] < amount.div(LOCK_UNIT_MAX))
            ? _slopeChanges[prevExpiry]
            : amount.div(LOCK_UNIT_MAX);
        _slopeChanges[prevExpiry] = _slopeChanges[prevExpiry].sub(slopeChange);
        _slopeChanges[nextExpiry] = _slopeChanges[nextExpiry].add(slopeChange);
        _updateTotalScoreExtendingLock(amount, prevExpiry, nextExpiry);
        expires[msg.sender] = nextExpiry;

        _updateGRVDistributorBoostedInfo(msg.sender);

        _lockHistory[msg.sender].push(
            Constant.LockInfo({timestamp: block.timestamp, amount: balances[msg.sender], expiry: expires[msg.sender]})
        );

        emit ExtendLock(msg.sender, nextExpiry);
    }

    /**
     * @notice Withdraw all tokens for `msg.sender`
     * @dev Only possible if the lock has expired
     */
    function withdraw() external override nonReentrant whenNotPaused {
        require(balances[msg.sender] > 0 && block.timestamp >= expires[msg.sender], "Locker: invalid state");
        _updateTotalScore(0, 0);

        uint256 amount = balances[msg.sender];
        totalBalance = totalBalance.sub(amount);
        delete balances[msg.sender];
        delete expires[msg.sender];
        delete _firstLockTime[msg.sender];
        GRV.safeTransfer(msg.sender, amount);

        _updateGRVDistributorBoostedInfo(msg.sender);

        emit Withdraw(msg.sender);
    }

    /**
     * @notice Withdraw all tokens for `msg.sender` and Lock again until given expiry
     *  @dev Only possible if the lock has expired
     * @param expiry Lock expire time
     */
    function withdrawAndLock(uint256 expiry) external override nonReentrant whenNotPaused {
        uint256 amount = balances[msg.sender];
        require(amount > 0 && block.timestamp >= expires[msg.sender], "Locker: invalid state");

        expiry = _truncateExpiry(expiry);
        require(
            block.timestamp < expiry && expiry <= _truncateExpiry(block.timestamp + LOCK_UNIT_MAX),
            "Locker: withdrawAndLock: invalid expiry"
        );

        _slopeChanges[expiry] = _slopeChanges[expiry].add(amount.div(LOCK_UNIT_MAX));
        _updateTotalScore(amount, expiry);

        expires[msg.sender] = expiry;

        _updateGRVDistributorBoostedInfo(msg.sender);
        _firstLockTime[msg.sender] = block.timestamp;

        _lockHistory[msg.sender].push(
            Constant.LockInfo({timestamp: block.timestamp, amount: balances[msg.sender], expiry: expires[msg.sender]})
        );

        emit WithdrawAndLock(msg.sender, expiry);
    }

    /// @notice whiteList 유저가 타인의 Deposit을 대신 해주는 함수
    function depositBehalf(
        address account,
        uint256 amount,
        uint256 expiry
    ) external override onlyWhitelisted nonReentrant whenNotPaused {
        require(amount > 0, "Locker: invalid amount");

        expiry = balances[account] == 0 ? _truncateExpiry(expiry) : expires[account];
        require(
            block.timestamp < expiry && expiry <= _truncateExpiry(block.timestamp + LOCK_UNIT_MAX),
            "Locker: depositBehalf: invalid expiry"
        );

        if (balances[account] == 0) {
            uint256 lockPeriod = expiry > block.timestamp ? expiry.sub(block.timestamp) : 0;
            require(lockPeriod >= LOCK_UNIT_MIN, "Locker: The expiry does not meet the minimum period");
            _firstLockTime[account] = block.timestamp;
        }

        _slopeChanges[expiry] = _slopeChanges[expiry].add(amount.div(LOCK_UNIT_MAX));
        _updateTotalScore(amount, expiry);

        GRV.safeTransferFrom(msg.sender, address(this), amount);
        totalBalance = totalBalance.add(amount);

        balances[account] = balances[account].add(amount);
        expires[account] = expiry;

        _updateGRVDistributorBoostedInfo(account);
        _lockHistory[account].push(
            Constant.LockInfo({timestamp: block.timestamp, amount: balances[account], expiry: expires[account]})
        );

        emit DepositBehalf(msg.sender, account, amount, expiry);
    }

    /// @notice WhiteList 유저가 타인의 Withdraw 를 대신 해주는 함수
    function withdrawBehalf(address account) external override onlyWhitelisted nonReentrant whenNotPaused {
        require(balances[account] > 0 && block.timestamp >= expires[account], "Locker: invalid state");
        _updateTotalScore(0, 0);

        uint256 amount = balances[account];
        totalBalance = totalBalance.sub(amount);
        delete balances[account];
        delete expires[account];
        delete _firstLockTime[account];
        GRV.safeTransfer(account, amount);

        _updateGRVDistributorBoostedInfo(account);

        emit WithdrawBehalf(msg.sender, account);
    }

    /**
     * @notice Withdraw and Lock 을 대신해주는 함수
     *  @dev Only possible if the lock has expired
     * @param expiry Lock expire time
     */
    function withdrawAndLockBehalf(
        address account,
        uint256 expiry
    ) external override onlyWhitelisted nonReentrant whenNotPaused {
        uint256 amount = balances[account];
        require(amount > 0 && block.timestamp >= expires[account], "Locker: invalid state");

        expiry = _truncateExpiry(expiry);
        require(
            block.timestamp < expiry && expiry <= _truncateExpiry(block.timestamp + LOCK_UNIT_MAX),
            "Locker: withdrawAndLockBehalf: invalid expiry"
        );

        _slopeChanges[expiry] = _slopeChanges[expiry].add(amount.div(LOCK_UNIT_MAX));
        _updateTotalScore(amount, expiry);

        expires[account] = expiry;

        _updateGRVDistributorBoostedInfo(account);
        _firstLockTime[account] = block.timestamp;

        _lockHistory[account].push(
            Constant.LockInfo({timestamp: block.timestamp, amount: balances[account], expiry: expires[account]})
        );

        emit WithdrawAndLockBehalf(msg.sender, account, expiry);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @notice total score update
    /// @dev 2년기준으로 deposit amount에 해당하는 unit score을 계산한뒤 선택한 expiry 기간 만큼의 score로 계산하여 total score에 추가, slop은 2년 기준으로 나눴을때 시간단위의 amount양을 나타내는것으로 보임
    /// @param newAmount GRV amount
    /// @param nextExpiry lockup period
    function _updateTotalScore(uint256 newAmount, uint256 nextExpiry) private {
        (uint256 score, uint256 slope) = totalScore();

        if (newAmount > 0) {
            uint256 slopeChange = newAmount.div(LOCK_UNIT_MAX);
            uint256 newAmountDeltaScore = nextExpiry.sub(block.timestamp).mul(slopeChange);

            slope = slope.add(slopeChange);
            score = score.add(newAmountDeltaScore);
        }

        _lastTotalScore = score;
        _lastSlope = slope;
        _lastTimestamp = block.timestamp;

        rebateDistributor.checkpoint();
    }

    function _updateTotalScoreExtendingLock(uint256 amount, uint256 prevExpiry, uint256 nextExpiry) private {
        (uint256 score, uint256 slope) = totalScore();

        uint256 deltaScore = nextExpiry.sub(prevExpiry).mul(amount.div(LOCK_UNIT_MAX));
        score = score.add(deltaScore);

        _lastTotalScore = score;
        _lastSlope = slope;
        _lastTimestamp = block.timestamp;

        rebateDistributor.checkpoint();
    }

    function _updateGRVDistributorBoostedInfo(address user) private {
        grvDistributor.updateAccountBoostedInfo(user);
    }

    function _truncateExpiry(uint256 time) private view returns (uint256) {
        if (time > block.timestamp.add(LOCK_UNIT_MAX)) {
            time = block.timestamp.add(LOCK_UNIT_MAX);
        }
        return (time.div(LOCK_UNIT_BASE).mul(LOCK_UNIT_BASE)).add(LOCK_UNIT_BASE);
    }

    function _onlyTruncateExpiry(uint256 time) private pure returns (uint256) {
        return time.div(LOCK_UNIT_BASE).mul(LOCK_UNIT_BASE);
    }
}

