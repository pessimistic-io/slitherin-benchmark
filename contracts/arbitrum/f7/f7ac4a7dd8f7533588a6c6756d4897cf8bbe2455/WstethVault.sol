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

import "./ITreasury.sol";
import "./IRiskVault.sol";
import "./IAavePoolV3.sol";

import "./Abs.sol";
import "./SafeCast.sol";

import "./ShareWrapper.sol";

contract WstethVault is ShareWrapper, ContractGuard, ReentrancyGuard, Operator, Blacklistable, Pausable {

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
    uint256 public minHealthFactor;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    mapping(address => StakeInfo) public stakeRequest;
    mapping(address => WithdrawInfo) public withdrawRequest;

    uint256 public withdrawLockupEpochs;
    uint256 public userExitEpochs;

    uint256 public glpInFee;
    uint256 public glpOutFee;
    uint256 public capacity;

    // flags
    bool public initialized;

    address public usdcRiskonVault = 0x07Cf4384b5B5Bb90c796b7C23986A4f12898BcAC;
    address public aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address public usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event WithdrawRequest(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount);
    event StakedByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event StakedETHByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event WithdrawRequestedByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event WithdrawnByGov(uint256 indexed atEpoch, uint256 amount, uint256 time);
    event RewardPaid(address indexed user, int256 reward);
    event RewardAdded(uint256 time, uint256 indexed atEpoch, uint256 period, uint256 totalStakedAmount, int256 reward, uint256 sharePrice);
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
    event AaveV3Updated(uint256 indexed atEpoch, address _aaveV3);
    event TreasuryUpdated(uint256 indexed atEpoch, address _treasury);
    event GasthresholdUpdated(uint256 indexed atEpoch, uint256 _gasthreshold);
    event MinimumRequestUpdated(uint256 indexed atEpoch, uint256 _minimumRequest);
    event MinHealthFactorUpdated(uint256 indexed atEpoch, uint256 _minHealthFactor);
    event RepayWithdraw(uint256 repayAmount, uint256 withdrawAmount);
    event SupplyBorrow(uint256 supplyAmount, uint256 borrowAmount);


    /* ========== Modifiers =============== */

    modifier onlyTreasury() {
        require(treasury == msg.sender, "caller is not the treasury");
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
        address _token,
        uint256 _fee,
        address _feeTo,
        uint256 _glpInFee,
        uint256 _glpOutFee,
        uint256 _gasthreshold,
        uint256 _minimumRequset,
        address _treasury
    ) public notInitialized {
        require(_token != address(0), "token address can not be zero address");
        require(_feeTo != address(0), "feeTo address can not be zero address");
        require(_treasury != address(0), "treasury address can not be zero address");
        token = _token;
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
        capacity = 10e18;
        minHealthFactor = 110 * 1e18 / 1e2;
        IAavePoolV3(aaveV3).setUserEMode(2);
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
        require(_feeTo != address(0), "address can not be zero address");
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

    function setAaveV3(address _aaveV3) external onlyOperator {
        require(_aaveV3 != address(0), "address can not be zero address");
        aaveV3 = _aaveV3;
        emit AaveV3Updated(epoch(), _aaveV3);
    }

    function setTreasury(address _treasury) external onlyOperator {
        require(_treasury != address(0), "address can not be zero address");
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
    
    function setMinHealthFactor(uint256 _minHealthFactor) external onlyOperator {
        require(minHealthFactor >= 110 * 1e18 / 1e2, "minHealthFactor must be greater than 110%");
        minHealthFactor = _minHealthFactor;
        emit MinHealthFactorUpdated(epoch(), _minHealthFactor);
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

    function aaveUserEMode() public view returns (uint256) {
        return IAavePoolV3(aaveV3).getUserEMode(address(this));
    }

    function aaveData() public view returns (uint256 totalCollateralBase, uint256 totalDebtBase,
    uint256 availableBorrowsBase, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor) {
        return IAavePoolV3(aaveV3).getUserAccountData(address(this));
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
        ISharplabs(token).mint(msg.sender, _amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw_request(uint256 _amount) external payable memberExists notBlacklisted(msg.sender) whenNotPaused {
        require(_amount != 0, "withdraw request cannot be equal to 0");
        require(_amount + withdrawRequest[msg.sender].amount <= _balances[msg.sender].staked, "withdraw amount exceeds the staked balance");
        require(members[msg.sender].epochTimerStart + withdrawLockupEpochs <= epoch(), "still in withdraw lockup");
        require(msg.value >= gasthreshold, "need more gas to handle request");
        withdrawRequest[msg.sender].amount += _amount;
        withdrawRequest[msg.sender].requestTimestamp = block.timestamp;
        withdrawRequest[msg.sender].requestEpoch = epoch();
        totalWithdrawRequest += _amount;
        emit WithdrawRequest(msg.sender, _amount);
    }

    function withdraw(uint256 amount, bool convert_weth) public override onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        require(amount != 0, "cannot withdraw 0");
        super.withdraw(amount, convert_weth);
        try ISharplabs(token).burn(msg.sender, amount) {
        } catch {}
        emit Withdrawn(msg.sender, amount);
    }

    function redeem() external onlyOneBlock notBlacklisted(msg.sender) whenNotPaused {
        uint256 _epoch = epoch();
        require(_epoch == stakeRequest[msg.sender].requestEpoch, "can not redeem");
        uint amount = balance_wait(msg.sender);
        _balances[msg.sender].wait -= amount;
        _totalSupply.wait -= amount;
        IERC20(share).safeTransfer(msg.sender, amount);  
        try ISharplabs(token).burn(msg.sender, amount) {
        } catch {}
        delete stakeRequest[msg.sender];
        emit Redeemed(msg.sender, amount);   
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
                try ISharplabs(token).burn(user, _glpOutFee) {
                } catch {}
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

    function stakeByGov(uint256 _amount) external onlyTreasury {
        IERC20(usdc).safeApprove(usdcRiskonVault, 0);
        IERC20(usdc).safeApprove(usdcRiskonVault, _amount);
        IRiskVault(usdcRiskonVault).stake{value: IRiskVault(usdcRiskonVault).gasthreshold()}(_amount);
        emit StakedByGov(epoch(), _amount, block.timestamp);
    }

    function withdrawRequestByGov(uint256 _amount) external onlyTreasury{
        IRiskVault(usdcRiskonVault).withdraw_request{value: IRiskVault(usdcRiskonVault).gasthreshold()}(_amount);
        emit WithdrawRequestedByGov(epoch(), _amount, block.timestamp);
    }

    function withdrawByGov(uint256 _amount) external onlyTreasury{
        IRiskVault(usdcRiskonVault).withdraw(_amount);
        emit WithdrawnByGov(epoch(), _amount, block.timestamp);
    }

    function allocateReward(int256 amount) external onlyOneBlock onlyTreasury {
        require(total_supply_staked() > 0, "totalSupply is 0");

        // Create & add new snapshot
        int256 prevRPS = getLatestSnapshot().rewardPerShare;
        int256 nextRPS = prevRPS + amount * 1e18 / total_supply_staked().toInt256();

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        _totalSupply.reward += amount;
        emit RewardAdded(block.number, epoch(), ITreasury(treasury).period(), total_supply_staked(), amount, share_price());
    }

    // 0: Disable E-Mode, 1: stable coin, 2: eth correlated
    function setAaveUserEMode(uint8 categoryId) external onlyTreasury(){
        IAavePoolV3(aaveV3).setUserEMode(categoryId);
        (,,,,,uint256 healthFactor) = IAavePoolV3(aaveV3).getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
    }

    function supplyBorrow(uint256 _supplyAmount, uint256 _borrowAmount, uint16 _referralCode) external onlyTreasury{
        if (_supplyAmount > 0){
            IERC20(share).safeApprove(aaveV3, 0);
            IERC20(share).safeApprove(aaveV3, _supplyAmount);
            IAavePoolV3(aaveV3).supply(share, _supplyAmount, address(this), _referralCode);
        }
        if (_borrowAmount > 0){
            IAavePoolV3(aaveV3).borrow(weth, _borrowAmount, 2, _referralCode, address(this));
        }
        (,,,,,uint256 healthFactor) = IAavePoolV3(aaveV3).getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
        emit SupplyBorrow(_supplyAmount, _borrowAmount);
    }

    function repayWithdraw(uint256 _repayAmount, uint256 _withdrawAmount)external onlyTreasury{
        if (_repayAmount > 0){
            IERC20(weth).safeApprove(aaveV3, 0);
            IERC20(weth).safeApprove(aaveV3, _repayAmount);
            uint64 assetId = 4;
            uint8 interestRateMode = 2;
            bytes memory _args = abi.encodePacked(
                bytes14(uint112(interestRateMode)),
                bytes16(uint128(_repayAmount)),
                bytes2(uint16(assetId)));
            bytes32 args;
            assembly {
                args := mload(add(_args, 32))
            }
            IAavePoolV3(aaveV3).repay(args);
        }
        if (_withdrawAmount > 0){
            uint64 assetId = 8;
            bytes memory _args = abi.encodePacked(
                bytes30(uint240(_withdrawAmount)),
                bytes2(uint16(assetId)));
            bytes32 args;
            assembly {
                args := mload(add(_args, 32))
            }
            IAavePoolV3(aaveV3).withdraw(args);
        }
        (,,,,,uint256 healthFactor) = IAavePoolV3(aaveV3).getUserAccountData(address(this));
        require(healthFactor >= minHealthFactor, "health factor too low");
        emit RepayWithdraw(_repayAmount, _withdrawAmount);
    }

    function treasuryWithdrawFunds(address _token, uint256 amount, address to) external onlyTreasury {
        require(to != address(0), "to address can not be zero address");
        IERC20(_token).safeTransfer(to, amount);
    }

    function treasuryWithdrawFundsWETHToETH(uint256 amount, address to) external nonReentrant onlyTreasury {
        require(to != address(0), "to address can not be zero address");
        IWETH(weth).withdraw(amount);
        Address.sendValue(payable(to), amount);
    }

    function treasuryWithdrawFundsETH(uint256 amount, address to) external nonReentrant onlyTreasury {
        require(to != address(0), "to address can not be zero address");
        Address.sendValue(payable(to), amount);
    }
}
