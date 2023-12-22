// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ISharplabs.sol";

import "./ContractGuard.sol";
import "./ReentrancyGuard.sol";

import "./Operator.sol";
import "./Blacklistable.sol";
import "./Pausable.sol";

import "./IGLPRouter.sol";
import "./ITreasury.sol";
import "./IRewardTracker.sol";
import "./IGlpManager.sol";

import "./Abs.sol";
import "./SafeCast.sol";

import "./ShareWrapper.sol";

contract RiskOffPool is ShareWrapper, ContractGuard, ReentrancyGuard, Operator, Blacklistable, Pausable {

    using SafeERC20 for IERC20;
    using Address for address;
    using Abs for int256;
    using SafeCast for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        int256 rewardEarned;
        uint256 lastSnapshotIndex;
        uint256 epochTimerStart;
    }

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

    // reward
    uint256 public totalWithdrawRequest;

    address public token;
    address public treasury;

    uint256 public gasthreshold;
    uint256 public minimumRequest;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => StakeInfo) public stakeRequest;
    mapping(address => WithdrawInfo) public withdrawRequest;

    mapping (address => address) public pendingReceivers;

    uint256 public withdrawLockupEpochs;
    uint256 public userExitEpochs;

    uint256 public glpInFee;
    uint256 public glpOutFee;
    uint256 public capacity;

    // flags
    bool public initialized = false;

    address public glpRouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public rewardRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address public glpManager = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    address public rewardTracker = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event WithdrawRequest(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);
    event StakedByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event StakedETHByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event WithdrawnByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event RewardPaid(address indexed user, int256 reward);
    event RewardAdded(uint256 indexed atEpoch, uint256 period, uint256 totalStakedAmount, int256 reward);
    event Exit(address indexed user, uint256 amount);
    event StakeRequestIgnored(address indexed ignored, uint256 atEpoch);
    event WithdrawRequestIgnored(address indexed ignored, uint256 atEpoch);
    event HandledStakeRequest(uint256 indexed atEpoch, address[] _address);
    event HandledWithdrawRequest(uint256 indexed atEpoch, address[] _address);
    event HandledReward(uint256 indexed atEpoch, uint256 time);
    event CapacityUpdated(uint256 indexed atEpoch, uint256 _capacity);
    event GlpFeeUpdated(uint256 indexed atEpoch, uint256 _glpInFee, uint256 _glpOutFee);
    event WithdrawLockupEpochsUpdated(uint256 indexed atEpoch, uint256 _withdrawLockupEpochs);
    event UserExitEpochsUpdated(uint256 indexed atEpoch, uint256 _userExitEpochs);
    event FeeUpdated(uint256 indexed atEpoch, uint256 _fee);
    event FeeToUpdated(uint256 indexed atEpoch, address _feeTo);
    event RouterUpdated(uint256 indexed atEpoch, address _glpRouter, address _rewardRouter);
    event GlpManagerUpdated(uint256 indexed atEpoch, address _glpManager);
    event RewardTrackerUpdated(uint256 indexed atEpoch, address _rewardTracker);
    event TreasuryUpdated(uint256 indexed atEpoch, address _treasury);
    event GasthresholdUpdated(uint256 indexed atEpoch, uint256 _gasthreshold);
    event MinimumRequestUpdated(uint256 indexed atEpoch, uint256 _minimumRequest);

    /* ========== Modifiers =============== */

    modifier onlyTreasury() {
        require(treasury == msg.sender, "caller is not the treasury");
        _;
    }

    modifier memberExists() {
        require(balance_withdraw(msg.sender) > 0, "The member does not exist");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "already initialized");
        _;
    }

    receive() payable external {}
    
    /* ========== GOVERNANCE ========== */

    function initialize (
        address _token,
        address _share,
        uint256 _fee,
        address _feeTo,
        uint256 _glpInFee,
        uint256 _glpOutFee,
        uint256 _gasthreshold,
        uint256 _minimumRequset,
        address _treasury
    ) public notInitialized {
        require(_token != address(0), "token address can not be zero address");
        require(_share != address(0), "share address can not be zero address");
        require(_feeTo != address(0), "feeTo address can not be zero address");
        require(_treasury != address(0), "treasury address can not be zero address");

        token = _token;
        share = _share;
        fee = _fee;
        feeTo = _feeTo;
        glpInFee = _glpInFee;
        glpOutFee = _glpOutFee;
        gasthreshold = _gasthreshold;
        minimumRequest = _minimumRequset;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 2; // Lock for 2 epochs (48h) before release withdraw
        userExitEpochs = 4;
        capacity = 1e12;
        initialized = true;

        emit Initialized(msg.sender, block.number);
    }

    /* ========== CONFIG ========== */

    function pause() external onlyTreasury {
        super._pause();
    }

    function unpause() external onlyTreasury {
        super._unpause();
    }

    function setLockUp(uint256 _withdrawLockupEpochs) external onlyOperator {
        withdrawLockupEpochs = _withdrawLockupEpochs;
        emit WithdrawLockupEpochsUpdated(epoch(), _withdrawLockupEpochs);
    }

    function setExitEpochs(uint256 _userExitEpochs) external onlyOperator {
        require(_userExitEpochs > 0, "userExitEpochs must be greater than zero");
        userExitEpochs = _userExitEpochs;
        emit UserExitEpochsUpdated(epoch(), _userExitEpochs);
    }

    function setFee(uint256 _fee) external onlyOperator {
        require(_fee <= 500, "fee: out of range");
        fee = _fee;
        emit FeeUpdated(epoch(), _fee);
    }

    function setFeeTo(address _feeTo) external onlyOperator {
        require(_feeTo != address(0), "feeTo can not be zero address");
        feeTo = _feeTo;
        emit FeeToUpdated(epoch(), _feeTo);
    }

    function setCapacity(uint256 _capacity) external onlyTreasury {
        capacity = _capacity;
        emit CapacityUpdated(epoch(), _capacity);
    }

    function setGlpFee(uint256 _glpInFee, uint256 _glpOutFee) external onlyTreasury {
        require(_glpInFee <= 500, "glpInFee: out of range");
        require(_glpOutFee <= 500, "glpOutFee: out of range");
        glpInFee = _glpInFee;
        glpOutFee = _glpOutFee;
        emit GlpFeeUpdated(epoch(), _glpInFee, _glpOutFee);
    }

    function setRouter(address _glpRouter, address _rewardRouter) external onlyOperator {
        require(_glpRouter != address(0), "glpRouter address can not be zero address");
        require(_rewardRouter != address(0), "rewardRouter address can not be zero address");
        glpRouter = _glpRouter;
        rewardRouter = _rewardRouter;
        emit RouterUpdated(epoch(), _glpRouter, _rewardRouter);
    }

    function setGlpManager(address _glpManager) external onlyOperator {
        require(_glpManager != address(0), "glpManager address can not be zero address");
        glpManager = _glpManager;
        emit GlpManagerUpdated(epoch(), _glpManager);
    }

    function setRewardTracker(address _rewardTracker) external onlyOperator {
        require(_rewardTracker != address(0), "rewardTracker address can not be zero address");
        rewardTracker = _rewardTracker;
        emit RewardTrackerUpdated(epoch(), _rewardTracker);
    }

    function setTreasury(address _treasury) external onlyOperator {
        require(_treasury != address(0), "treasury address can not be zero address");
        treasury = _treasury;
        emit TreasuryUpdated(epoch(), _treasury);
    }

    function setGasThreshold(uint256 _gasthreshold) external onlyOperator {
        gasthreshold = _gasthreshold;
        emit GasthresholdUpdated(epoch(), _gasthreshold);
    }    

    function setMinimumRequest(uint256 _minimumRequest) external onlyOperator {
        minimumRequest = _minimumRequest;
        emit MinimumRequestUpdated(epoch(), _minimumRequest);
    }   

    /* ========== VIEW FUNCTIONS ========== */

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
        return members[member].epochTimerStart + withdrawLockupEpochs <= epoch();
    }

    function epoch() public view returns (uint256) {
        return ITreasury(treasury).epoch();
    }

    function nextEpochPoint() public view returns (uint256) {
        return ITreasury(treasury).nextEpochPoint();
    }
    // =========== Member getters

    function rewardPerShare() public view returns (int256) {
        return getLatestSnapshot().rewardPerShare;
    }

    // calculate earned reward of specified user
    function earned(address member) public view returns (int256) {
        int256 latestRPS = getLatestSnapshot().rewardPerShare;
        int256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return balance_staked(member).toInt256() * (latestRPS - storedRPS) / 1e18 + members[member].rewardEarned;
    }

    // required usd collateral in the contract
    function getRequiredCollateral() public view returns (uint256) {
        if (_totalSupply.reward > 0) {
            return _totalSupply.wait + _totalSupply.staked + _totalSupply.withdrawable + _totalSupply.reward.abs();
        } else {
            return _totalSupply.wait + _totalSupply.staked + _totalSupply.withdrawable - _totalSupply.reward.abs();
        }
    }

    // glp price
    function getGLPPrice(bool _maximum) public view returns (uint256) {
        return IGlpManager(glpManager).getPrice(_maximum);
    }

    // staked glp amount
    function getStakedGLP() public view returns (uint256) {
        return IRewardTracker(rewardTracker).balanceOf(address(this));
    }

    // staked glp usd value
    function getStakedGLPUSDValue(bool _maximum) public view returns (uint256) {
        return getGLPPrice(_maximum) * getStakedGLP() / 1e42;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _amount) public payable override onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        require(_amount >= minimumRequest, "stake amount too low");
        require(_totalSupply.staked + _totalSupply.wait + _amount <= capacity, "stake no capacity");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        if (fee > 0) {
            uint tax = _amount * fee / 10000;
            _amount = _amount - tax;
            IERC20(share).safeTransferFrom(msg.sender, feeTo, tax);
        }
        if (glpInFee > 0) {
            uint _glpInFee = _amount * glpInFee / 10000;
            _amount = _amount - _glpInFee;
            IERC20(share).safeTransferFrom(msg.sender, address(this), _glpInFee);
        }
        super.stake(_amount);
        stakeRequest[msg.sender].amount += _amount;
        stakeRequest[msg.sender].requestTimestamp = block.timestamp;
        stakeRequest[msg.sender].requestEpoch = epoch();
        ISharplabs(token).mint(msg.sender, _amount * 1e12);
        emit Staked(msg.sender, _amount);
    }

    function withdraw_request(uint256 _amount) external payable notBlacklisted(msg.sender) whenNotPaused {
        require(_amount + withdrawRequest[msg.sender].amount <= _balances[msg.sender].staked, "withdraw amount out of range");
        require(members[msg.sender].epochTimerStart + withdrawLockupEpochs <= epoch(), "still in withdraw lockup");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        withdrawRequest[msg.sender].amount += _amount;
        withdrawRequest[msg.sender].requestTimestamp = block.timestamp;
        withdrawRequest[msg.sender].requestEpoch = epoch();
        totalWithdrawRequest += _amount;
        emit WithdrawRequest(msg.sender, _amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists notBlacklisted(msg.sender) whenNotPaused {
        require(amount != 0, "cannot withdraw 0");
        super.withdraw(amount);
        ISharplabs(token).burn(msg.sender, amount * 1e12);   
        emit Withdrawn(msg.sender, amount);
    }

    function redeem() external onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        uint256 _epoch = epoch();
        require(_epoch == stakeRequest[msg.sender].requestEpoch, "can not redeem");
        uint amount = balance_wait(msg.sender);
        _totalSupply.wait -= amount;
        _balances[msg.sender].wait -= amount;
        IERC20(share).safeTransfer(msg.sender, amount);  
        ISharplabs(token).burn(msg.sender, amount * 1e12);   
        delete stakeRequest[msg.sender];
        emit Redeemed(msg.sender, amount);   
    }

    function exit() onlyOneBlock external notBlacklisted(msg.sender) whenNotPaused {
        require(withdrawRequest[msg.sender].requestTimestamp != 0, "no request");
        require(nextEpochPoint() + ITreasury(treasury).period() * userExitEpochs <= block.timestamp, "cannot exit");
        uint amount = _balances[msg.sender].staked;
        uint _glpAmount = amount * 1e42 / getGLPPrice(false);
        uint amountOut = IGLPRouter(glpRouter).unstakeAndRedeemGlp(share, _glpAmount, 0, address(this));
        require(amountOut <= amount, "withdraw overflow");
        updateReward(msg.sender);
        _totalSupply.reward -= members[msg.sender].rewardEarned;
        members[msg.sender].rewardEarned = 0;
        _totalSupply.staked -= amount;
        _balances[msg.sender].staked -= amount;
        _totalSupply.withdrawable += amount;
        _balances[msg.sender].withdrawable += amount;
        totalWithdrawRequest -= withdrawRequest[msg.sender].amount;
        delete withdrawRequest[msg.sender];
        emit Exit(msg.sender, amount);
    }

    function handleStakeRequest(address[] memory _address) external onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = stakeRequest[user].amount;
            if (stakeRequest[user].requestEpoch == _epoch) { // check latest epoch
                emit StakeRequestIgnored(user, _epoch);
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
            members[user].epochTimerStart = _epoch - 1;  // reset timer   
            delete stakeRequest[user];
        }
        emit HandledStakeRequest(_epoch, _address);
    }

    function handleWithdrawRequest(address[] memory _address) external onlyTreasury {
        uint256 _epoch = epoch();
        for (uint i = 0; i < _address.length; i++) {
            address user = _address[i];
            uint amount = withdrawRequest[user].amount;
            uint amountReceived = amount; // user real received amount
            if (withdrawRequest[user].requestEpoch == _epoch) { // check latest epoch
                emit WithdrawRequestIgnored(user, _epoch);
                continue;  
            }
            if (withdrawRequest[user].requestTimestamp == 0) {
                continue;
            }
            claimReward(user);
            if (glpOutFee > 0) {
                uint _glpOutFee = amount * glpOutFee / 10000;
                amountReceived = amount - _glpOutFee;
            }
            _balances[user].staked -= amount;
            _balances[user].withdrawable += amountReceived;
            _totalSupply.staked -= amount;
            _totalSupply.withdrawable += amountReceived;
            totalWithdrawRequest -= amount;
            members[user].epochTimerStart = _epoch - 1; // reset timer
            delete withdrawRequest[user];
        }
        emit HandledWithdrawRequest(_epoch, _address);
    }

    function removeWithdrawRequest(address[] memory _address) external onlyTreasury {
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

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external onlyTreasury returns (uint256) {
        IERC20(_token).safeApprove(glpManager, 0);
        IERC20(_token).safeApprove(glpManager, _amount);
        uint256 glpAmount = IGLPRouter(glpRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        emit StakedByGov(epoch(), _amount, block.timestamp);
        return glpAmount;
    }

    function stakeETHByGov(uint256 amount, uint256 _minUsdg, uint256 _minGlp) external onlyTreasury returns (uint256) {
        require(amount <= address(this).balance, "not enough funds");
        uint256 glpAmount = IGLPRouter(glpRouter).mintAndStakeGlpETH{value: amount}(_minUsdg, _minGlp);
        emit StakedETHByGov(epoch(), amount, block.timestamp);
        return glpAmount;
    }

    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external onlyTreasury returns (uint256) {
        uint256 glpAmount = IGLPRouter(glpRouter).unstakeAndRedeemGlp(_tokenOut, _glpAmount, _minOut, _receiver);
        emit WithdrawnByGov(epoch(), _minOut, block.timestamp);
        return glpAmount;
    }

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external onlyTreasury {
        uint256 _epoch = epoch();
        IGLPRouter(rewardRouter).handleRewards(
            _shouldClaimGmx,
            _shouldStakeGmx,
            _shouldClaimEsGmx,
            _shouldStakeEsGmx,
            _shouldStakeMultiplierPoints,
            _shouldClaimWeth,
            _shouldConvertWethToEth);
        emit HandledReward(_epoch, block.timestamp);
    }

    function allocateReward(int256 amount) external onlyOneBlock onlyTreasury {
        require(amount >= 0, "Rewards cannot be less than 0");
        require(total_supply_staked() > 0, "rewards cannot be allocated when totalSupply is 0");

        // Create & add new snapshot
        int256 prevRPS = getLatestSnapshot().rewardPerShare;
        int256 nextRPS = prevRPS + amount * 1e18 / total_supply_staked().toInt256();

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        _totalSupply.reward += amount;
        emit RewardAdded(epoch(), ITreasury(treasury).period(), total_supply_staked(), amount);
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(stakeRequest[msg.sender].amount == 0, "Pool: sender has stakeRequest");
        require(withdrawRequest[msg.sender].amount == 0, "Pool: sender has withdrawRequest");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(stakeRequest[_sender].amount == 0, "Pool: sender has stakeRequest");
        require(withdrawRequest[_sender].amount == 0, "Pool: sender has withdrawRequest");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "Pool: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);

        uint256 wait_balance = balance_wait(_sender);
        if (wait_balance > 0) {
            _balances[_sender].wait -= wait_balance;
            _balances[receiver].wait += wait_balance;
        }

        uint256 staked_balance = balance_staked(_sender);
        if (staked_balance > 0) {
            _balances[_sender].staked -= staked_balance;
            _balances[receiver].staked += staked_balance;
        }

        uint256 withdraw_balance = balance_withdraw(_sender);
        if (withdraw_balance > 0) {
            _balances[_sender].withdrawable -= withdraw_balance;
            _balances[receiver].withdrawable += withdraw_balance;
        }

        int256 reward_balance = balance_reward(_sender);
        if (reward_balance != 0) {
            _balances[_sender].reward -= reward_balance;
            _balances[receiver].reward += reward_balance;
        }

        uint256 share_balance = IERC20(token).balanceOf(_sender);
        if (share_balance > 0) {
            ISharplabs(token).burn(_sender, share_balance);
            ISharplabs(token).mint(receiver, share_balance);
        }

        members[receiver].rewardEarned = members[_sender].rewardEarned;
        members[receiver].lastSnapshotIndex = members[_sender].lastSnapshotIndex;
        members[receiver].epochTimerStart = members[_sender].epochTimerStart;

        delete members[_sender];
    }

    function _validateReceiver(address _receiver) private view {
        require(balance_wait(_receiver) == 0, "invalid receiver: receiver wait_balance is not equal to zero");
        require(balance_staked(_receiver) == 0, "invalid receiver: receiver staked_balance is not equal to zero");
        require(balance_withdraw(_receiver) == 0, "invalid receiver: receiver withdraw_balance is not equal to zero");
        require(balance_reward(_receiver) == 0, "invalid receiver: receiver reward_balance is not equal to zero");
    }

    function treasuryWithdrawFunds(address _token, uint256 amount, address to) external onlyTreasury {
        require(to != address(0), "to address can not be zero address");
        IERC20(_token).safeTransfer(to, amount);
    }

    function treasuryWithdrawFundsETH(uint256 amount, address to) external onlyTreasury {
        require(to != address(0), "to address can not be zero address");
        Address.sendValue(payable(to), amount);
    }
}
