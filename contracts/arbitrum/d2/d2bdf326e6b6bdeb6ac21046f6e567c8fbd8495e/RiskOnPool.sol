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
import "./ShareWrapper.sol";

contract RiskOnPool is ShareWrapper, ContractGuard, ReentrancyGuard, Operator, Blacklistable, Pausable {

    using SafeERC20 for IERC20;
    using Address for address;
    using Abs for int256;

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
    address public RewardTracker = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;

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
    event RewardAdded(address indexed user, int256 reward);
    event Exit(address indexed user, uint256 amount);
    event StakeRequestIgnored(address indexed ignored, uint256 atEpoch);
    event WithdrawRequestIgnored(address indexed ignored, uint256 atEpoch);
    event HandledStakeRequest(uint256 indexed atEpoch, address[] _address);
    event HandledWithdrawRequest(uint256 indexed atEpoch, address[] _address);
    event HandledReward(uint256 indexed atEpoch, uint256 time);


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
        require(_withdrawLockupEpochs > 0, "withdrawLockupEpochs must be greater than zero");
        withdrawLockupEpochs = _withdrawLockupEpochs;
    }

    function setExitEpochs(uint256 _userExitEpochs) external onlyOperator {
        require(_userExitEpochs > 0, "userExitEpochs must be greater than zero");
        userExitEpochs = _userExitEpochs;
    }

    function setShareToken(address _share) external onlyOperator {
        require(_share != address(0), "share token can not be zero address");
        share = _share;
    }

    function setFee(uint256 _fee) external onlyOperator {
        require(_fee >= 0 && _fee <= 10000, "fee: out of range");
        fee = _fee;
    }

    function setFeeTo(address _feeTo) external onlyOperator {
        require(_feeTo != address(0), "feeTo can not be zero address");
        feeTo = _feeTo;
    }

    function setCapacity(uint256 _capacity) external onlyTreasury {
        require(_capacity >= 0, "capacity must be greater than or equal to 0");
        capacity = _capacity;
    }

    function setGlpFee(uint256 _glpInFee, uint256 _glpOutFee) external onlyTreasury {
        require(_glpInFee >= 0 && _glpInFee <= 10000, "fee: out of range");
        require(_glpOutFee >= 0 && _glpOutFee <= 10000, "fee: out of range");
        _glpInFee = _glpInFee;
        glpOutFee = _glpOutFee;
    }


    function setRouter(address _glpRouter, address _rewardRouter) external onlyOperator {
        glpRouter = _glpRouter;
        rewardRouter = _rewardRouter;
    }

    function setGlpManager(address _glpManager) external onlyOperator {
        glpManager = _glpManager;
    }

    function setRewardTracker(address _RewardTracker) external onlyOperator {
        RewardTracker = _RewardTracker;
    }

    function setTreasury(address _treasury) external onlyOperator {
        treasury = _treasury;
    }

    function setGasThreshold(uint256 _gasthreshold) external onlyOperator {
        require(_gasthreshold >= 0, "gasthreshold below zero");
        gasthreshold = _gasthreshold;
    }    

    function setMinimumRequest(uint256 _minimumRequest) external onlyOperator {
        require(_minimumRequest >= 0, "minimumRequest below zero");
        minimumRequest = _minimumRequest;
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

        return int(balance_staked(member)) * (latestRPS - storedRPS) / 1e18 + members[member].rewardEarned;
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
        return IRewardTracker(RewardTracker).balanceOf(address(this));
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
        require(_amount >= minimumRequest, "withdraw amount too low");
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
        _totalSupply.staked -= amount;
        _balances[msg.sender].staked -= amount;
        _totalSupply.withdrawable += amount;
        _balances[msg.sender].withdrawable += amount;
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
            int reward = claimReward(user);
            if (glpOutFee > 0) {
                uint _glpOutFee = amount * glpOutFee / 10000;
                amountReceived = amount - _glpOutFee;
            }
            _balances[user].staked -= amount;
            _balances[user].withdrawable += amountReceived;
            _balances[user].reward += reward;
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
        if (reward > 0) {
            members[member].epochTimerStart = epoch() - 1; // reset timer
            members[member].rewardEarned = 0;
            _balances[msg.sender].reward += reward;
            emit RewardPaid(member, reward);
        }
        return reward;
    }

    function stakeByGov(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external onlyTreasury {
        IERC20(_token).safeApprove(glpManager, 0);
        IERC20(_token).safeApprove(glpManager, _amount);
        IGLPRouter(glpRouter).mintAndStakeGlp(_token, _amount, _minUsdg, _minGlp);
        emit StakedByGov(epoch(), _amount, block.timestamp);
    }

    function stakeETHByGov(uint256 amount, uint256 _minUsdg, uint256 _minGlp) external onlyTreasury {
        require(amount <= address(this).balance, "not enough funds");
        IGLPRouter(glpRouter).mintAndStakeGlpETH{value: amount}(_minUsdg, _minGlp);
        emit StakedETHByGov(epoch(), amount, block.timestamp);
    }

    function withdrawByGov(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external onlyTreasury {
        IGLPRouter(glpRouter).unstakeAndRedeemGlp(_tokenOut, _glpAmount, _minOut, _receiver);
        emit WithdrawnByGov(epoch(), _minOut, block.timestamp);
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
        require(total_supply_staked() > 0, "rewards cannot be allocated when totalSupply is 0");

        // Create & add new snapshot
        int256 prevRPS = getLatestSnapshot().rewardPerShare;
        int256 nextRPS = prevRPS + amount * 1e18 / int(total_supply_staked());

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        _totalSupply.reward += amount;
        emit RewardAdded(msg.sender, amount);
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(stakeRequest[msg.sender].amount == 0, "RiskOffPool: sender has stakeRequest");
        require(withdrawRequest[msg.sender].amount == 0, "RiskOffPool: sender has withdrawRequest");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(stakeRequest[_sender].amount == 0, "RiskOffPool: sender has stakeRequest");
        require(withdrawRequest[_sender].amount == 0, "RiskOffPool: sender has withdrawRequest");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RiskOffPool: transfer not signalled");
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
        if (reward_balance > 0) {
            _balances[_sender].reward -= reward_balance;
            _balances[receiver].reward += reward_balance;
        }

        uint256 share_balance = IERC20(token).balanceOf(_sender);
        if (share_balance > 0) {
            ISharplabs(token).burn(_sender, share_balance);
            ISharplabs(token).mint(receiver, share_balance);
        }
    }

    function _validateReceiver(address _receiver) private view {
        require(balance_wait(_receiver) == 0, "invalid receiver: receiver wait_balance is not equal to zero");
        require(balance_staked(_receiver) == 0, "invalid receiver: receiver staked_balance is not equal to zero");
        require(balance_withdraw(_receiver) == 0, "invalid receiver: receiver withdraw_balance is not equal to zero");
        require(balance_reward(_receiver) == 0, "invalid receiver: receiver reward_balance is not equal to zero");
    }

    function treasuryWithdrawFunds(address _token, uint256 amount, address to) external onlyTreasury {
        IERC20(_token).safeTransfer(to, amount);
    }

    function treasuryWithdrawFundsETH(uint256 amount, address to) external onlyTreasury {
        payable(to).transfer(amount);
    }
}
