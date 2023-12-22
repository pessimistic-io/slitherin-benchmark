// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./SafeERC20.sol";
import "./SafeMath.sol";

contract ContractGuard {
    mapping(uint256 => mapping(address => bool)) private _status;

    function checkSameOriginReentranted() internal view returns (bool) {
        return _status[block.number][tx.origin];
    }

    function checkSameSenderReentranted() internal view returns (bool) {
        return _status[block.number][msg.sender];
    }

    modifier onlyOneBlock() {
        require(!checkSameOriginReentranted(), "ContractGuard: one block, one function");
        require(!checkSameSenderReentranted(), "ContractGuard: one block, one function");

        _;

        _status[block.number][tx.origin] = true;
        _status[block.number][msg.sender] = true;
    }
}

interface ITreasury {

    function epoch() external view returns (uint256);
    function nextEpochPoint() external view returns (uint256);
    function getHopePrice() external view returns (uint256);
    function buyBonds(uint256 amount, uint256 targetPrice) external;
    function redeemBonds(uint256 amount, uint256 targetPrice) external;
}

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public dream;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        dream.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 boardroomShare = _balances[msg.sender];
        require(boardroomShare >= amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = boardroomShare.sub(amount);
        dream.safeTransfer(msg.sender, amount);
    }
}

contract Boardroom is ShareWrapper, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Boardseat {
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

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    IERC20 public hope;
    ITreasury public treasury;

    mapping(address => Boardseat) public boards;
    BoardroomSnapshot[] public boardroomHistory;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Boardroom: caller is not the operator");
        _;
    }

    modifier boardExists {
        require(balanceOf(msg.sender) > 0, "Boardroom: The board does not exist");
        _;
    }

    modifier updateReward(address board) {
        if (board != address(0)) {
            Boardseat memory seat = boards[board];
            seat.rewardEarned = earned(board);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            boards[board] = seat;
        }
        _;
    }

    modifier notInitialized {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        IERC20 _hope,
        IERC20 _dream,
        ITreasury _treasury
    ) public notInitialized {
        hope = _hope;
        dream = _dream;
        treasury = _treasury;
        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time : block.number, rewardReceived : 0, rewardPerShare : 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 6; // Lock for 6 epochs (36h) before release withdraw
        rewardLockupEpochs = 3; // Lock for 3 epochs (18h) before release claimReward

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 56, "_withdrawLockupEpochs: out of range"); // <= 2 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address board) public view returns (uint256) {
        return boards[board].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address board) internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[getLastSnapshotIndexOf(board)];
    }

    function canWithdraw(address board) external view returns (bool) {
        return boards[board].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch();
    }

    function canClaimReward(address board) external view returns (bool) {
        return boards[board].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getHopePrice() external view returns (uint256) {
        return treasury.getHopePrice();
    }

    // =========== board getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address board) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(board).rewardPerShare;

        return balanceOf(board).mul(latestRPS.sub(storedRPS)).div(1e18).add(boards[board].rewardEarned);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) public override onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot stake 0");
        super.stake(amount);
        boards[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock boardExists updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        require(boards[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch(), "Boardroom: still in withdraw lockup");
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = boards[msg.sender].rewardEarned;
        if (reward > 0) {
            require(boards[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch(), "Boardroom: still in reward lockup");
            boards[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
            boards[msg.sender].rewardEarned = 0;
            hope.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external onlyOneBlock onlyOperator {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(totalSupply() > 0, "Boardroom: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerShare: nextRPS
        });
        boardroomHistory.push(newSnapshot);

        hope.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(hope), "hope");
        require(address(_token) != address(dream), "dream");
        _token.safeTransfer(_to, _amount);
    }
}
