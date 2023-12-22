// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ReentrancyGuard.sol";

import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract FbDaoRoom is ReentrancyGuard, PausableUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    // epoch
    uint256 public startTime;
    uint256 public lastEpochTime;
    uint256 private epoch_ = 0;
    uint256 private epochLength_ = 0;

    // reward
    uint256 public epochReward;
    uint256 public nextEpochReward;

    address public share; // FBDAO
    address public reward; // USDC

    address public treasury;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    uint256 public withdrawLockupEpochs;

    mapping(address => bool) public authorizer;

    uint256 public totalDistributedReward;

    /* ========== Modifiers =============== */
    modifier checkEpoch() {
        uint256 _nextEpochPoint = nextEpochPoint();
        require(block.timestamp >= _nextEpochPoint, "!opened");

        _;

        lastEpochTime = _nextEpochPoint;
        epoch_ += 1;
    }

    modifier onlyAuthorizer() {
        require(authorizer[msg.sender], "!authorizer");
        _;
    }

    modifier memberExists() {
        require(_balances[msg.sender] > 0, "The member does not exist");
        _;
    }

    modifier updateReward(address member) {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
        _;
    }

    /* ========== GOVERNANCE ========== */
    function initialize(
        address _share,
        address _reward,
        address _treasury,
        uint256 _startTime,
        uint256 _epochLength
    ) external initializer {
        PausableUpgradeable.__Pausable_init();
        OwnableUpgradeable.__Ownable_init();

        share = _share;
        reward = _reward;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        startTime = _startTime;
        epochLength_ = _epochLength; // should be 1 week
        lastEpochTime = _startTime - _epochLength;

        withdrawLockupEpochs = 1; // Lock for 1 epochs

        nextEpochReward = epochReward = 1000 * (10 ** 6); // 1000 USDC
        authorizer[msg.sender] = true;
    }

    function setNextEpochPoint(uint256 _nextEpochPoint) external onlyOwner {
        require(_nextEpochPoint >= block.timestamp, "nextEpochPoint could not be the past");
        lastEpochTime = _nextEpochPoint - epochLength_;
    }

    function setEpochLength(uint256 _epochLength) external onlyOwner {
        require(_epochLength >= 1 days && _epochLength <= 28 days, "out of range");
        epochLength_ = _epochLength;
    }

    function setLockUp(uint256 _withdrawLockupEpochs) external onlyOwner {
        require(_withdrawLockupEpochs <= 4, "out of range"); // <= 4 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
    }

    function setEpochReward(uint256 _epochReward) external onlyOwner {
        epochReward = _epochReward;
    }

    function setNextEpochReward(uint256 _nextEpochReward) external onlyAuthorizer {
        require(msg.sender == owner() || _nextEpochReward <= 20000 ether, "only owner can set big amount");
        nextEpochReward = _nextEpochReward;
    }

    function setAuthorizer(address _address, bool _on) external onlyOwner {
        authorizer[_address] = _on;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "zero");
        treasury = _treasury;
    }

    function setNewReward(address _newReward) external onlyOwner {
        IERC20 _oldReward = IERC20(reward);
        _oldReward.safeTransfer(owner(), _oldReward.balanceOf(address(this)));
        reward = _newReward;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function epoch() public view returns (uint256) {
        return epoch_;
    }

    function nextEpochPoint() public view returns (uint256) {
        return lastEpochTime + nextEpochLength();
    }

    function nextEpochLength() public view returns (uint256) {
        return epochLength_;
    }

    // =========== Snapshot getters
    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length - 1;
    }

    function getLatestSnapshot() internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address member) public view returns (uint256) {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address member) internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[getLastSnapshotIndexOf(member)];
    }

    function canWithdraw(address member) external view returns (bool) {
        return members[member].epochTimerStart + withdrawLockupEpochs <= epoch_;
    }

    // =========== Member getters
    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address member) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return _balances[member] * (latestRPS - storedRPS) / 1e18 + members[member].rewardEarned;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function _stake(uint256 _amount) internal virtual {
        IERC20 _share = IERC20(share);
        uint256 _shareBal = _share.balanceOf(address(this));
        _share.safeTransferFrom(msg.sender, address(this), _amount);
        _amount = _share.balanceOf(address(this)) - _shareBal; // recheck for deflation tokens
        _totalSupply += _amount;
        _balances[msg.sender] += _amount;
        emit Staked(msg.sender, _amount);
    }

    function _withdraw(uint256 _amount) internal virtual {
        uint256 memberShare = _balances[msg.sender];
        require(memberShare >= _amount, "FbDaoRoom: withdraw request greater than staked amount");
        _totalSupply -= _amount;
        _balances[msg.sender] = 0;
        IERC20(share).safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function stake(uint256 _amount) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(_amount > 0, "FbDaoRoom: Cannot stake 0");
        if (members[msg.sender].rewardEarned > 0) {
            claimReward();
        }
        _stake(_amount);
        members[msg.sender].epochTimerStart = epoch_; // reset timer
    }

    function withdraw(uint256 _amount) public nonReentrant memberExists whenNotPaused updateReward(msg.sender) {
        require(_amount > 0, "FbDaoRoom: Nothing to withdraw");
        require(members[msg.sender].epochTimerStart + withdrawLockupEpochs <= epoch_, "still in withdraw lockup");
        _taxReward();
        _withdraw(_amount);
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
    }

    function _taxReward() internal updateReward(msg.sender) {
        uint256 _earned = members[msg.sender].rewardEarned;
        if (_earned > 0) {
            members[msg.sender].rewardEarned = 0;
            _safeRewardTransfer(treasury, _earned);
            emit RewardTaxed(msg.sender, _earned);
        }
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 _earned = members[msg.sender].rewardEarned;
        if (_earned > 0) {
            members[msg.sender].epochTimerStart = epoch_; // reset timer
            members[msg.sender].rewardEarned = 0;
            _safeRewardTransfer(msg.sender, _earned);
            emit RewardPaid(msg.sender, _earned);
        }
    }

    function _safeRewardTransfer(address _to, uint256 _amount) internal {
        IERC20 _reward = IERC20(reward);
        uint256 _rewardBal = _reward.balanceOf(address(this));
        if (_rewardBal > 0) {
            if (_amount > _rewardBal) {
                _reward.safeTransfer(_to, _rewardBal);
            } else {
                _reward.safeTransfer(_to, _amount);
            }
        }
    }

    function allocateReward() external nonReentrant checkEpoch whenNotPaused {
        uint256 _amount = epochReward;

        require(_amount > 0, "Cannot allocate 0");
        require(_totalSupply > 0, "Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS + (_amount * 1e18 / _totalSupply);

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: _amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        epochReward = nextEpochReward;
        totalDistributedReward += _amount;

        IERC20(reward).safeTransferFrom(treasury, address(this), _amount);
        emit RewardAdded(msg.sender, _amount);
    }

    /* ========== EMERGENCY ========== */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        require(address(_token) != share, "staked share");
        require(address(_token) != reward, "reward");
        _token.safeTransfer(treasury, _token.balanceOf(address(this)));
    }

    /* ========== EVENTS ========== */
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 earned);
    event RewardTaxed(address indexed user, uint256 taxed);
    event RewardAdded(address indexed user, uint256 amount);
}

