// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./Math.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./IVlQuoV2.sol";
import "./IBribeManager.sol";

contract VlQuoV2 is
    IVlQuoV2,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public override quo;

    IBribeManager public bribeManager;

    address public treasury;

    uint256 public maxLockLength;

    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public override unlockGracePeriod;
    uint256 public override unlockPunishment;

    uint256 public constant WEEK = 86400 * 7;
    uint256 public constant MAX_LOCK_WEEKS = 52;

    struct LockInfo {
        uint256 quoAmount;
        uint256 vlQuoAmount;
        uint256 lockTime;
        uint256 unlockTime;
    }

    mapping(address => LockInfo[]) public userLocks;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    mapping(uint256 => uint256) public weeklyTotalWeight;
    mapping(address => mapping(uint256 => uint256)) public weeklyUserWeight;

    // when set to true, other accounts cannot call `lock` on behalf of an account
    mapping(address => bool) public override blockThirdPartyActions;

    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;

    // reward token address => queued rewards
    mapping(address => uint256) public queuedRewards;

    // reward token address => week => rewards
    mapping(address => mapping(uint256 => uint256)) public weeklyRewards;

    // user address => last claimed week
    mapping(address => uint256) public lastClaimedWeek;

    mapping(address => bool) public access;

    mapping(address => bool) public allowedLocker;

    mapping(address => uint256) private _lockerTotalSupply;
    mapping(address => mapping(address => uint256)) private _lockerBalances;

    modifier onlyAllowedLocker() {
        require(allowedLocker[msg.sender], "!auth");
        _;
    }

    function initialize() external initializer {
        __Ownable_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
    }

    function setParams(
        address _quo,
        address _bribeManager,
        address _treasury
    ) external onlyOwner {
        require(address(quo) == address(0), "params have already been set");

        require(_quo != address(0), "invalid _quo!");
        require(_bribeManager != address(0), "invalid _bribeManager!");
        require(_treasury != address(0), "invalid _treasury!");

        quo = IERC20(_quo);
        bribeManager = IBribeManager(_bribeManager);
        treasury = _treasury;

        maxLockLength = 10000;

        unlockGracePeriod = 14 days;
        unlockPunishment = 300;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setMaxLockLength(uint256 _maxLockLength) external onlyOwner {
        maxLockLength = _maxLockLength;
    }

    function setUnlockGracePeriod(uint256 _unlockGracePeriod)
        external
        onlyOwner
    {
        unlockGracePeriod = _unlockGracePeriod;
    }

    function setUnlockPunishment(uint256 _unlockPunishment) external onlyOwner {
        unlockPunishment = _unlockPunishment;
    }

    // Allow or block third-party calls on behalf of the caller
    function setBlockThirdPartyActions(bool _block) external {
        blockThirdPartyActions[msg.sender] = _block;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _user) public view override returns (uint256) {
        return _balances[_user];
    }

    function getUserLocks(address _user)
        external
        view
        returns (LockInfo[] memory)
    {
        return userLocks[_user];
    }

    function lock(
        address _user,
        uint256 _amount,
        uint256 _weeks
    ) external override nonReentrant whenNotPaused {
        require(_user != address(0), "invalid _user!");
        require(
            msg.sender == _user || !blockThirdPartyActions[_user],
            "Cannot lock on behalf of this account"
        );

        require(_weeks > 0, "Min 1 week");
        require(_weeks <= MAX_LOCK_WEEKS, "Exceeds MAX_LOCK_WEEKS");
        require(_amount > 0, "Amount must be nonzero");

        require(userLocks[_user].length < maxLockLength, "locks too much");

        quo.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 vlQuoAmount = _amount.mul(_weeks);
        uint256 unlockTime = _getNextWeek().add(_weeks.mul(WEEK));
        userLocks[_user].push(
            LockInfo(_amount, vlQuoAmount, block.timestamp, unlockTime)
        );

        _increaseBalance(address(0), _user, vlQuoAmount);

        for (uint256 week = _getNextWeek(); week < unlockTime; week += WEEK) {
            weeklyTotalWeight[week] = weeklyTotalWeight[week].add(vlQuoAmount);
            weeklyUserWeight[_user][week] = weeklyUserWeight[_user][week].add(
                vlQuoAmount
            );
        }

        if (lastClaimedWeek[_user] == 0) {
            lastClaimedWeek[_user] = _getCurWeek();
        }

        emit Locked(_user, _amount, _weeks);
    }

    function unlock(uint256 _slot) external nonReentrant whenNotPaused {
        uint256 length = userLocks[msg.sender].length;
        require(_slot < length, "wut?");

        LockInfo memory lockInfo = userLocks[msg.sender][_slot];
        require(lockInfo.unlockTime <= block.timestamp, "not yet meh");

        uint256 punishment;
        if (block.timestamp > lockInfo.unlockTime.add(unlockGracePeriod)) {
            punishment = block
                .timestamp
                .sub(lockInfo.unlockTime.add(unlockGracePeriod))
                .div(WEEK)
                .add(1)
                .mul(unlockPunishment)
                .mul(lockInfo.quoAmount)
                .div(FEE_DENOMINATOR);
            punishment = Math.min(punishment, lockInfo.quoAmount);
        }

        // remove slot
        if (_slot != length - 1) {
            userLocks[msg.sender][_slot] = userLocks[msg.sender][length - 1];
        }
        userLocks[msg.sender].pop();

        if (punishment > 0) {
            quo.safeTransfer(treasury, punishment);
        }
        quo.safeTransfer(msg.sender, lockInfo.quoAmount.sub(punishment));

        _decreaseBalance(address(0), msg.sender, lockInfo.vlQuoAmount);

        emit Unlocked(
            msg.sender,
            lockInfo.unlockTime,
            lockInfo.quoAmount,
            lockInfo.vlQuoAmount
        );
    }

    function getReward() external nonReentrant {
        uint256 userLastClaimedWeek = lastClaimedWeek[msg.sender];
        if (
            userLastClaimedWeek == 0 ||
            userLastClaimedWeek >= _getCurWeek().sub(WEEK)
        ) {
            return;
        }
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            uint256 reward = earned(msg.sender, rewardToken);
            if (reward > 0) {
                IERC20(rewardToken).safeTransfer(msg.sender, reward);

                emit RewardPaid(msg.sender, rewardToken, reward);
            }
        }

        lastClaimedWeek[msg.sender] = _getCurWeek().sub(WEEK);
    }

    function getRewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    function _addRewardToken(address _rewardToken) internal {
        if (isRewardToken[_rewardToken]) {
            return;
        }
        rewardTokens.push(_rewardToken);
        isRewardToken[_rewardToken] = true;

        emit RewardTokenAdded(_rewardToken);
    }

    function earned(address _user, address _rewardToken)
        public
        view
        returns (uint256)
    {
        // return 0 if user has never locked
        if (lastClaimedWeek[_user] == 0) {
            return 0;
        }

        uint256 startWeek = lastClaimedWeek[_user].add(WEEK);
        uint256 finishedWeek = _getCurWeek().sub(WEEK);
        uint256 amount = 0;

        for (
            uint256 cur = startWeek;
            cur <= finishedWeek;
            cur = cur.add(WEEK)
        ) {
            uint256 totalW = weeklyTotalWeight[cur];
            if (totalW == 0) {
                continue;
            }
            amount = amount.add(
                weeklyRewards[_rewardToken][cur]
                    .mul(weeklyUserWeight[_user][cur])
                    .div(totalW)
            );
        }
        return amount;
    }

    function donate(address _rewardToken, uint256 _amount) external {
        require(isRewardToken[_rewardToken], "invalid token");
        IERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        queuedRewards[_rewardToken] = queuedRewards[_rewardToken].add(_amount);
    }

    function queueNewRewards(address _rewardToken, uint256 _rewards) external {
        require(access[msg.sender], "!auth");

        _addRewardToken(_rewardToken);

        IERC20(_rewardToken).safeTransferFrom(
            msg.sender,
            address(this),
            _rewards
        );

        uint256 curWeek = _getCurWeek();
        uint256 totalWeight = weeklyTotalWeight[curWeek];
        if (totalWeight == 0) {
            queuedRewards[_rewardToken] = queuedRewards[_rewardToken].add(
                _rewards
            );
            return;
        }

        _rewards = _rewards.add(queuedRewards[_rewardToken]);
        queuedRewards[_rewardToken] = 0;

        weeklyRewards[_rewardToken][curWeek] = weeklyRewards[_rewardToken][
            curWeek
        ].add(_rewards);
        emit RewardAdded(_rewardToken, _rewards);
    }

    function setAccess(address _address, bool _status) external onlyOwner {
        require(_address != address(0), "invalid _address!");

        access[_address] = _status;
        emit AccessSet(_address, _status);
    }

    function setAllowedLocker(address _locker, bool _allowed)
        external
        onlyOwner
    {
        require(_locker != address(0), "invalid _address!");

        allowedLocker[_locker] = _allowed;
        emit AllowedLockerSet(_locker, _allowed);
    }

    function increaseBalance(address _user, uint256 _amount)
        external
        override
        onlyAllowedLocker
    {
        _increaseBalance(msg.sender, _user, _amount);
    }

    function decreaseBalance(address _user, uint256 _amount)
        external
        override
        onlyAllowedLocker
    {
        _decreaseBalance(msg.sender, _user, _amount);
    }

    function _increaseBalance(
        address _locker,
        address _user,
        uint256 _amount
    ) internal {
        if (_locker != address(0)) {
            _lockerTotalSupply[_locker] = _lockerTotalSupply[_locker].add(
                _amount
            );
            _lockerBalances[_locker][_user] = _lockerBalances[_locker][_user]
                .add(_amount);
        }
        _totalSupply = _totalSupply.add(_amount);
        uint256 newBal = _balances[_user].add(_amount);
        _balances[_user] = newBal;
        emit BalanceUpdated(_user, newBal);
    }

    function _decreaseBalance(
        address _locker,
        address _user,
        uint256 _amount
    ) internal {
        if (_locker != address(0)) {
            _lockerTotalSupply[_locker] = _lockerTotalSupply[_locker].sub(
                _amount
            );
            _lockerBalances[_locker][_user] = _lockerBalances[_locker][_user]
                .sub(_amount);
        }
        _totalSupply = _totalSupply.sub(_amount);
        uint256 newBal = _balances[_user].sub(_amount);
        _balances[_user] = newBal;
        require(
            bribeManager.getUserTotalVote(_user) <= newBal,
            "Too much vote cast"
        );
        emit BalanceUpdated(_user, newBal);
    }

    function _getCurWeek() internal view returns (uint256) {
        return block.timestamp.div(WEEK).mul(WEEK);
    }

    function _getNextWeek() internal view returns (uint256) {
        return _getCurWeek().add(WEEK);
    }
}

