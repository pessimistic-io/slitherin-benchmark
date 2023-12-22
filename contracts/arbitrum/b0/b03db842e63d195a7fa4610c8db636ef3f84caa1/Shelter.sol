// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

import "./ContractGuard.sol";
import "./IBasisAsset.sol";
import "./ITreasury.sol";
import "./Operator.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public share;

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
        share.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 andrasShare = _balances[msg.sender];
        require(andrasShare >= amount, "Shelter: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = andrasShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}

contract Shelter is ShareWrapper, ContractGuard, Operator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Ecclesiaseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct ShelterSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    // flags
    bool public initialized = false;

    IERC20 public aur;
    ITreasury public treasury;

    mapping(address => Ecclesiaseat) public demos;
    ShelterSnapshot[] public shelterHistory;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier andrasExists() {
        require(balanceOf(msg.sender) > 0, "Shelter: The andras does not exist");
        _;
    }

    modifier updateReward(address andras) {
        if (andras != address(0)) {
            Ecclesiaseat memory seat = demos[andras];
            seat.rewardEarned = earned(andras);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            demos[andras] = seat;
        }
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Shelter: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(IERC20 _aur, IERC20 _share, ITreasury _treasury) public notInitialized onlyOperator {
        aur = _aur;
        share = _share;
        treasury = _treasury;

        ShelterSnapshot memory genesisSnapshot =
            ShelterSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        shelterHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 4; // Lock for 4 epochs (24h) before release withdraw
        rewardLockupEpochs = 2; // Lock for 2 epochs (12h) before release claimReward

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        transferOperator(_operator);
    }

    function renounceOperator() external onlyOperator {
        _renounceOperator();
    }

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(
            _withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 56,
            "_withdrawLockupEpochs: out of range"
        ); // <= 2 week
        require(_withdrawLockupEpochs > 0 && _rewardLockupEpochs > 0);
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters =========== //

    function latestSnapshotIndex() public view returns (uint256) {
        return shelterHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (ShelterSnapshot memory) {
        return shelterHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address andras) public view returns (uint256) {
        return demos[andras].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address andras) internal view returns (ShelterSnapshot memory) {
        return shelterHistory[getLastSnapshotIndexOf(andras)];
    }

    function canWithdraw(address andras) external view returns (bool) {
        return demos[andras].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch();
    }

    function canClaimReward(address andras) external view returns (bool) {
        return demos[andras].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getAurPrice() external view returns (uint256) {
        return treasury.getAurPrice();
    }

    // =========== Andras getters =========== //

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address andras) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(andras).rewardPerShare;

        return balanceOf(andras).mul(latestRPS.sub(storedRPS)).div(1e18).add(demos[andras].rewardEarned);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) public override onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Shelter: Cannot stake 0");
        super.stake(amount);
        demos[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock andrasExists updateReward(msg.sender) {
        require(amount > 0, "Shelter: Cannot withdraw 0");
        require(
            demos[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch(),
            "Shelter: still in withdraw lockup"
        );
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = demos[msg.sender].rewardEarned;
        if (reward > 0) {
            require(
                demos[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch(),
                "Shelter: still in reward lockup"
            );
            demos[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
            demos[msg.sender].rewardEarned = 0;
            aur.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external onlyOneBlock onlyOperator {
        require(amount > 0, "Shelter: Cannot allocate 0");
        require(totalSupply() > 0, "Shelter: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        ShelterSnapshot memory newSnapshot =
            ShelterSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        shelterHistory.push(newSnapshot);

        aur.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(aur), "aur");
        require(address(_token) != address(share), "share");
        _token.safeTransfer(_to, _amount);
    }
}

