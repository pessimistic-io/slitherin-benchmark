// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ContractGuard.sol";
import "./ReentrancyGuard.sol";

import "./Operator.sol";
import "./Blacklistable.sol";
import "./Pausable.sol";

import "./Abs.sol";
import "./SafeCast.sol";

contract ShareWrapper {

    using SafeERC20 for IERC20;
    using Abs for int256;

    address public share;

    struct TotalSupply {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
        int256 reward;
    }

    struct Balances {
        uint256 wait;
        uint256 staked;
        uint256 withdrawable;
        int256 reward;
    }

    mapping(address => Balances) internal _balances;
    TotalSupply internal _totalSupply;

    function total_supply_wait() public view returns (uint256) {
        return _totalSupply.wait;
    }

    function total_supply_staked() public view returns (uint256) {
        return _totalSupply.staked;
    }

    function total_supply_withdraw() public view returns (uint256) {
        return _totalSupply.withdrawable;
    }

    function total_supply_reward() public view returns (int256) {
        return _totalSupply.reward;
    }

    function balance_wait(address account) public view returns (uint256) {
        return _balances[account].wait;
    }

    function balance_staked(address account) public view returns (uint256) {
        return _balances[account].staked;
    }

    function balance_withdraw(address account) public view returns (uint256) {
        return _balances[account].withdrawable;
    }

    function balance_reward(address account) public view returns (int256) {
        return _balances[account].reward;
    }

    function stake(uint256 amount) public payable virtual {
        _totalSupply.wait += amount;
        _balances[msg.sender].wait += amount;
        IERC20(share).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        require(_balances[msg.sender].withdrawable >= amount, "withdraw request greater than withdrawable amount");
        _totalSupply.withdrawable -= amount;
        _balances[msg.sender].withdrawable -= amount;
        int _reward = balance_reward(msg.sender);
        if (_reward > 0) {
            _balances[msg.sender].reward = 0;
            _totalSupply.reward -= _reward;
            IERC20(share).safeTransfer(msg.sender, amount + _reward.abs());
        } else if (_reward < 0) {
            _balances[msg.sender].reward = 0;
            _totalSupply.reward -= _reward;
            IERC20(share).safeTransfer(msg.sender, amount - _reward.abs());            
        } else {
            IERC20(share).safeTransfer(msg.sender, amount);
        }
    }
}

contract FundingRateVault is ShareWrapper, ContractGuard, ReentrancyGuard, Operator, Blacklistable, Pausable {

    using SafeERC20 for IERC20;
    using Address for address;
    using Abs for int256;
    using SafeCast for uint256;

    /* ========== DATA STRUCTURES ========== */

    // @dev Record the deposit information of each user in the system.
    // @param rewardEarned: The total earnings of the user.
    // @param lastSnapshotIndex: The starting time for calculating the user's earnings.
    // @param epochTimerStart: Record the epoch when the user's request is handled.
    struct Memberseat {
        int256 rewardEarned;
        uint256 lastSnapshotIndex;
        uint256 epochTimerStart;
    }

    // @dev Record the information of rewards distributed for each epoch in the system.
    // @param rewardReceived: The total reward of the epoch.
    // @param rewardPerShare: The reward for each share.
    // @param time: block.number
    struct BoardroomSnapshot {
        int256 rewardReceived;
        int256 rewardPerShare;
        uint256 time;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }

    struct WithdrawInfo {
        uint256 amount;
        uint256 requestTimestamp;
        uint256 requestEpoch;
    }

    /* ========== STATE VARIABLES ========== */

    // The total amount of withdrawals per epoch.
    uint256 public totalWithdrawRequest;

    // @dev Users will be charged a certain amount of gas fees when making deposits and withdrawals, 
    // which will be used to handle the deposit and withdrawal requests.
    uint256 public gasthreshold;

    // The minimum required amount for deposits and withdrawals.
    uint256 public minimumRequest;

    address public governance;

    // @dev feeIn and feeOut are charged by cex.
    uint256 public feeIn;
    uint256 public feeOut;

    uint256 public protocolFee;
    address public protocolFeeTo;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => StakeInfo) public stakeRequest;
    mapping(address => WithdrawInfo) public withdrawRequest;

    mapping(address => bool) public governanceWithdrawWhiteList;

    uint256 public withdrawLockupEpochs;

    // flags
    bool public initialized;

    uint256 public epoch;
    uint256 public startTime;
    uint256 public period = 7 days;
    uint256 public lastEpochPoint;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event WithdrawRequest(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, int256 reward);
    event RewardAdded(uint256 indexed atEpoch, uint256 period, uint256 totalStakedAmount, int256 reward);
    event StakeRequestIgnored(address indexed ignored, uint256 atEpoch);
    event WithdrawRequestIgnored(address indexed ignored, uint256 atEpoch);
    event HandledStakeRequest(uint256 indexed atEpoch, address[] _address);
    event HandledWithdrawRequest(uint256 indexed atEpoch, address[] _address);
    event WithdrawLockupEpochsUpdated(uint256 indexed atEpoch, uint256 _withdrawLockupEpochs);
    event ProtocolFeeUpdated(uint256 indexed atEpoch, uint256 _protocolFee);
    event ProtocolFeeToUpdated(uint256 indexed atEpoch, address _protocolFeeTo);
    event FeeUpdated(uint256 indexed atEpoch, uint256 _feeIn, uint256 _feeOut);
    event PeriodUpdated(uint256 indexed atEpoch, uint256 _period);
    event GasthresholdUpdated(uint256 indexed atEpoch, uint256 _gasthreshold);
    event MinimumRequestUpdated(uint256 indexed atEpoch, uint256 _minimumRequest);
    event EpochUpdated(uint256 indexed atEpoch, uint256 timestamp);
    event GovernanceWithdrawWhiteListUpdated(uint256 indexed atEpoch, address _whitelistAddress, bool _status);
    event GovernanceUpdated(uint256 indexed atEpoch, address _governance);

    /* ========== Modifiers =============== */

    modifier onlyGovernance() {
        require(governance == msg.sender, "caller is not the governance");
        _;
    }

    modifier memberExists() {
        require(balance_staked(msg.sender) > 0, "The member does not exist");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    receive() payable external {}
    
    /* ========== GOVERNANCE ========== */

    function initialize (
        address _governance,
        address _share,
        uint256 _protocolFee,
        address _protocolFeeTo,
        uint256 _feeIn,
        uint256 _feeOut,
        uint256 _gasthreshold,
        uint256 _minimumRequset,
        uint256 _startTime
    ) public notInitialized {
        require(_share != address(0), "share address can not be zero address");
        require(_protocolFeeTo != address(0), "protocolFeeTo address can not be zero address");

        governance = _governance;
        share = _share;
        protocolFee = _protocolFee;
        protocolFeeTo = _protocolFeeTo;
        feeIn = _feeIn;
        feeOut = _feeOut;
        gasthreshold = _gasthreshold;
        minimumRequest = _minimumRequset;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 2; // Lock for 2 epochs (14days) before release withdraw
        startTime = _startTime;
        lastEpochPoint = _startTime;
        initialized = true;

        emit Initialized(msg.sender, block.number);
    }

    /* ========== CONFIG ========== */

    // @dev In case of an emergency, the administrator has the authority to temporarily pause the system. 
    // This pause may impact certain functionalities such as user deposits, withdrawals, redemptions.
    function pause() external onlyGovernance {
        super._pause();
    }

    function unpause() external onlyGovernance {
        super._unpause();
    }

    function setLockUp(uint256 _withdrawLockupEpochs) external onlyGovernance {
        withdrawLockupEpochs = _withdrawLockupEpochs;
        emit WithdrawLockupEpochsUpdated(epoch, _withdrawLockupEpochs);
    }

    function setProtocolFee(uint256 _protocolFee) external onlyGovernance {
        require(_protocolFee <= 500, "fee: out of range");
        protocolFee = _protocolFee;
        emit ProtocolFeeUpdated(epoch, _protocolFee);
    }

    function setProtocolFeeTo(address _protocolFeeTo) external onlyGovernance {
        require(_protocolFeeTo != address(0), "feeTo can not be zero address");
        protocolFeeTo = _protocolFeeTo;
        emit ProtocolFeeToUpdated(epoch, _protocolFeeTo);
    }

    function setFee(uint256 _feeIn, uint256 _feeOut) external onlyGovernance {
        require(_feeIn <= 500, "feeIn: out of range");
        require(_feeOut <= 500, "feeOut: out of range");
        feeIn = _feeIn;
        feeOut = _feeOut;
        emit FeeUpdated(epoch, _feeIn, _feeOut);
    }

    function setPeriod(uint256 _period) external onlyGovernance {
        period = _period;
        emit PeriodUpdated(epoch, _period);
    }

    function setGasThreshold(uint256 _gasthreshold) external onlyGovernance {
        gasthreshold = _gasthreshold;
        emit GasthresholdUpdated(epoch, _gasthreshold);
    }    

    function setMinimumRequest(uint256 _minimumRequest) external onlyGovernance {
        minimumRequest = _minimumRequest;
        emit MinimumRequestUpdated(epoch, _minimumRequest);
    }   

    function setGovernanceWithdrawWhiteList(address _whitelistAddress, bool _status) external onlyGovernance {
        require(_whitelistAddress != address(0), "whitelist address cannot be zero address");
        governanceWithdrawWhiteList[_whitelistAddress] = _status;
        emit GovernanceWithdrawWhiteListUpdated(epoch, _whitelistAddress, _status);
    }

    function setGovernance(address _governance) external onlyOperator {
        require(_governance != address(0), "governance address cannot be zero address");
        governance = _governance;
        emit GovernanceUpdated(epoch, _governance);
    }

    /* ========== VIEW FUNCTIONS ========== */

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
        return members[member].epochTimerStart + withdrawLockupEpochs <= epoch;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return lastEpochPoint + period;
    }

    function rewardPerShare() public view returns (int256) {
        return getLatestSnapshot().rewardPerShare;
    }

    // calculate earned reward of specified user
    function earned(address member) public view returns (int256) {
        int256 latestRPS = getLatestSnapshot().rewardPerShare;
        int256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return balance_staked(member).toInt256() * (latestRPS - storedRPS) / 1e18 + members[member].rewardEarned;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // @dev user stake function.
    // Protocol fees will be charged.
    // Additional gas fees will also be charged.
    // The number of multiple stake requests will be accumulated.
    // @param _amount: The amount of deposited tokens.
    function stake(uint256 _amount) public payable override onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        require(_amount >= minimumRequest, "stake amount too low");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        if (protocolFee > 0) {
            uint tax = _amount * protocolFee / 10000;
            _amount = _amount - tax;
            IERC20(share).safeTransferFrom(msg.sender, protocolFeeTo, tax);
        }
        if (feeIn > 0) {
            uint _feeIn = _amount * feeIn / 10000;
            _amount = _amount - _feeIn;
            IERC20(share).safeTransferFrom(msg.sender, address(this), _feeIn);
        }
        super.stake(_amount);
        stakeRequest[msg.sender].amount += _amount;
        stakeRequest[msg.sender].requestTimestamp = block.timestamp;
        stakeRequest[msg.sender].requestEpoch = epoch;
        emit Staked(msg.sender, _amount);
    }

    // @dev user withdraw request function.
    // The number of multiple withdrawal requests will be accumulated.
    // @param _amount: The amount of withdraw tokens.
    function withdraw_request(uint256 _amount) public payable memberExists notBlacklisted(msg.sender) whenNotPaused {
        require(_amount != 0, "withdraw request cannot be equal to 0");
        require(_amount + withdrawRequest[msg.sender].amount <= _balances[msg.sender].staked, "withdraw amount exceeds the staked balance");
        require(members[msg.sender].epochTimerStart + withdrawLockupEpochs <= epoch, "still in withdraw lockup");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        withdrawRequest[msg.sender].amount += _amount;
        withdrawRequest[msg.sender].requestTimestamp = block.timestamp;
        withdrawRequest[msg.sender].requestEpoch = epoch;
        totalWithdrawRequest += _amount;
        emit WithdrawRequest(msg.sender, _amount);
    }

    // @dev user withdraw functions.
    // After a user's withdrawal request has been handled, 
    // the user can invoke this function to retrieve their tokens.
    // @param amount: withdraw token amount.
    function withdraw(uint256 amount) public override onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        require(amount != 0, "cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function handleStakeRequest(address[] memory _address) external onlyGovernance {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = stakeRequest[user].amount;
            if (stakeRequest[user].requestEpoch == epoch) { // check latest epoch
                emit StakeRequestIgnored(user, epoch);
                continue;  
            }
            if (stakeRequest[user].requestTimestamp == 0) {
                continue;
            }
            updateReward(user);
            _balances[user].wait -= amount;
            _balances[user].staked += amount;
            _totalSupply.wait -= amount;
            _totalSupply.staked += amount;    
            members[user].epochTimerStart = epoch - 1;  // reset timer   
            delete stakeRequest[user];
        }
        emit HandledStakeRequest(epoch, _address);
    }

    function handleWithdrawRequest(address[] memory _address) external onlyGovernance {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            uint amountReceived = amount; // user real received amount
            if (withdrawRequest[user].requestEpoch == epoch) { // check latest epoch
                emit WithdrawRequestIgnored(user, epoch);
                continue;  
            }
            if (withdrawRequest[user].requestTimestamp == 0) {
                continue;
            }
            claimReward(user);
            if (feeOut > 0) {
                uint _feeOut = amount * feeOut / 10000;
                amountReceived = amount - _feeOut;
            }
            _balances[user].staked -= amount;
            _balances[user].withdrawable += amountReceived;
            _totalSupply.staked -= amount;
            _totalSupply.withdrawable += amountReceived;
            totalWithdrawRequest -= amount;
            members[user].epochTimerStart = epoch - 1; // reset timer
            delete withdrawRequest[user];
        }
        emit HandledWithdrawRequest(epoch, _address);
    }

    function removeWithdrawRequest(address[] memory _address) external onlyGovernance {
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            totalWithdrawRequest -= amount;
            delete withdrawRequest[user];
        }      
    }

    function updateReward(address member) internal {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
    }

    function claimReward(address member) internal returns (int) {
        updateReward(member);
        int256 reward = members[member].rewardEarned;
        members[member].rewardEarned = 0;
        _balances[member].reward += reward;
        emit RewardPaid(member, reward);
        return reward;
    }

    function allocateReward(int256 amount) external onlyOneBlock onlyGovernance {
        require(total_supply_staked() > 0, "rewards cannot be allocated when totalSupply is 0");

        // Create & add new snapshot
        int256 prevRPS = getLatestSnapshot().rewardPerShare;
        int256 nextRPS = prevRPS + amount * 1e18 / total_supply_staked().toInt256();

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        _totalSupply.reward += amount;
        emit RewardAdded(epoch, period, total_supply_staked(), amount);
    }

    // trigger by the governance wallet at the end of each epoch
    function updateEpoch() external onlyGovernance {
        require(block.timestamp >= nextEpochPoint(), "not opened yet");
        epoch += 1;
        lastEpochPoint += period;
        emit EpochUpdated(epoch, block.timestamp);
    }

    function governanceWithdrawFunds(address _token, uint256 amount, address to) external onlyGovernance {
        require(governanceWithdrawWhiteList[to] == true, "to address is not in the whitelist");
        IERC20(_token).safeTransfer(to, amount);
    }

    function governanceWithdrawFundsETH(uint256 amount, address to) external nonReentrant onlyGovernance {
        require(governanceWithdrawWhiteList[to] == true, "to address is not in the whitelist");
        Address.sendValue(payable(to), amount);
    }
}
