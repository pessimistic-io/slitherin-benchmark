// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./IMainPool.sol";
import "./IAccountManager.sol";
import "./IFarmingManager.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Initializable.sol";

/*
 * The Main Pool holds the LP collateral and UND debt (but not UND tokens) for all active accounts.
 *
 * When a account is liquidated, it's LP Collateral and UND debt are transferred from the Main Pool, to liquidator. 
 * Also this pool will be responsible for all the farming operations and it's rewards
 *
 */

 contract MainPool is IMainPool, Ownable, ReentrancyGuard, Initializable {
    using SafeERC20 for IERC20;

    address public borrowerOperations;
    address public accountManager;

    uint256 internal _collateral;  // deposited collateral tracker
    uint256 internal _UNDDebt;

    uint256 public override undMintLimit;

    uint256 public farmingContractAddTime;
    address public pendingFarmingContract;

    /* ========== FARMING REWARD STATE VARIABLES ========== */

    struct Reward {
        uint256 lastDistributedReward;
        uint256 rewardPerTokenStored;
    }

    mapping(address => Reward) public rewardData;
    address[] public rewardTokens;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    IERC20 public depositToken;

    IFarmingManager public farmingManager;

    event NewFarmingManagerPurposed(address _newFarmingManager);
    event NewFarmingManagerEnabled(address _newFarmingManager);

     // user -> reward token -> amount
    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(address => mapping(address => uint256)) public rewards;

    function initialize(address _accountManager, address _borrowerOperations, address _depositToken, address _owner) public initializer {
        accountManager = _accountManager;
        borrowerOperations = _borrowerOperations;
        depositToken = IERC20(_depositToken);

        _transferOwnership(_owner);
    }

    // --- Pool functionality ---
    
    function increaseCollateral(uint _amount) external override {
        _requireCallerIsBO();
        uint256 newCollateral = _collateral + _amount;
        _collateral  = newCollateral;
        emit MainPoolCollateralBalanceUpdated(newCollateral);
    }

    function sendCollateral(IERC20 _depositToken, address _account, uint _amount) external override {
        _requireCallerIsAccountManagerOrBO();
        uint256 newCollateral = _collateral - _amount;
        _collateral  = newCollateral;
        emit MainPoolCollateralBalanceUpdated(newCollateral);
        emit CollateralSent(_account, _amount);

        _depositToken.safeTransfer(_account, _amount);
    }

    function increaseUNDDebt(uint _amount) external override {
        _requireCallerIsBO();
        uint256 newDebt = _UNDDebt + _amount;
        _UNDDebt  = newDebt;
        emit MainPoolUNDDebtUpdated(newDebt);
    }

    function decreaseUNDDebt(uint _amount) external override {
        _requireCallerIsAccountManagerOrBO();
        uint256 newDebt = _UNDDebt - _amount;
        _UNDDebt  = newDebt;
        emit MainPoolUNDDebtUpdated(newDebt);
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the state variable.
    *
    *Not necessarily equal to the the contract's raw Collateral balance - LP can be forcibly sent to contracts.
    */
    function getCollateral() external view override returns (uint) {
        return _collateral;
    }

    function getUNDDebt() external view override returns (uint) {
        return _UNDDebt;
    }

    // change UND mint limit for this specific vault
    function changeUNDMintLimit(uint256 _newMintLimit) external onlyOwner{
        undMintLimit = _newMintLimit;
        emit UNDMintLimitChanged(_newMintLimit);
    }

    // --- 'require' functions ---

    function _requireCallerIsBO() internal view {
        require(
            msg.sender == borrowerOperations,
            "MainPool: Caller is not BorrowerOperations");
    }
    
    function _requireCallerIsAccountManagerOrBO() internal view {
        require(
            msg.sender == borrowerOperations || msg.sender == accountManager,
            "MainPool: Caller is not BorrowerOperations or AccountManager");
    }

    // ----- FARMING section -----

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }
        return
            rewardData[_rewardsToken].rewardPerTokenStored + ((rewardData[_rewardsToken].lastDistributedReward * 1e18) / _totalSupply);
    }

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        return ((_balances[account] * (rewardData[_rewardsToken].rewardPerTokenStored - userRewardPerTokenPaid[account][_rewardsToken])) / 1e18) + rewards[account][_rewardsToken];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */ 

    function addReward(
        address _rewardsToken
    )
        public
        onlyOwner
    {
        rewardTokens.push(_rewardsToken);
    }

    function removeReward(
        uint256 _rewardsTokenIndex
    )
        public
        updateReward(address(0))
        onlyOwner
    {
        address _rewardsToken = rewardTokens[_rewardsTokenIndex];

        if(rewardTokens.length > 1){
            address lastElement = rewardTokens[rewardTokens.length - 1];
            rewardTokens[_rewardsTokenIndex] = lastElement;
        }

        rewardTokens.pop();

        rewardData[_rewardsToken].lastDistributedReward = 0;

        IERC20(_rewardsToken).safeTransfer(owner(), IERC20(_rewardsToken).balanceOf(address(this)));
    }

    function addFarmingManagerContract(address _farmingManager) external onlyOwner {
        farmingContractAddTime = block.timestamp;
        pendingFarmingContract = _farmingManager;

        emit NewFarmingManagerPurposed(_farmingManager);
    }

    // Withdraw all existing staked tokens, change farmingManager address and deposit al tokens to new farming contract
    function enableFarmingManagerContract() external onlyOwner updateReward(address(0)){
        require(farmingContractAddTime > 0, "MainPool: Nothing to enable");
        require(block.timestamp - farmingContractAddTime >= 1 days, "MainPool: too early");

        // revoke approve permission from old farming manager if have any & withdraw all staked tokens
        if(address(farmingManager) != address(0)){
            depositToken.safeApprove(address(farmingManager), 0);
            farmingManager.withdrawAll();
        }

        require(depositToken.balanceOf(address(this)) >= _collateral, "MainPool: Insufficient collateral");

        farmingManager = IFarmingManager(pendingFarmingContract);

        pendingFarmingContract = address(0);
        farmingContractAddTime = 0;
        
        // approve farming manager contract & stake all tokens to new farming contract
        if(address(farmingManager) != address(0)){
            depositToken.safeApprove(address(farmingManager), type(uint256).max); 
            farmingManager.depositAll();
        }

        emit NewFarmingManagerEnabled(address(farmingManager));
    }

    function stake(address user, uint256 amount) external override nonReentrant updateReward(user) {
        _requireCallerIsBO();

        _totalSupply = _totalSupply + amount;
        _balances[user] = _balances[user] + amount;
        
        if(address(farmingManager) != address(0)){

            farmingManager.deposit(amount);
            emit Staked(user, amount);
        }
    }

    function unstake(address user, uint256 amount) external override nonReentrant updateReward(user) {
        _requireCallerIsAccountManagerOrBO();
        
        _totalSupply = _totalSupply - amount;
        _balances[user] = _balances[user] - amount;
        
        if(address(farmingManager) != address(0)){

            farmingManager.withdraw(amount);
            emit Unstaked(user, amount);
        }
    }

    function getReward() public nonReentrant updateReward(msg.sender) returns(uint256[] memory){
        uint256[] memory _rewards = new uint256[](rewardTokens.length);
        
        for (uint i; i < rewardTokens.length; i++) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[msg.sender][_rewardsToken];
            if (reward > 0) {
                rewards[msg.sender][_rewardsToken] = 0;
                IERC20(_rewardsToken).safeTransfer(msg.sender, reward);
                emit RewardPaid(msg.sender, _rewardsToken, reward);
            }
            _rewards[i] = reward;
        }
        return _rewards;
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {

        if(address(farmingManager) != address(0)){

            for (uint i; i < rewardTokens.length; i++) {

                address token = rewardTokens[i];

                uint256 _reward = farmingManager.distributeRewards(IERC20(token));

                rewardData[token].lastDistributedReward = _reward;
                rewardData[token].rewardPerTokenStored = rewardPerToken(token);

                if (account != address(0)) {
                    rewards[account][token] = earned(account, token);
                    userRewardPerTokenPaid[account][token] = rewardData[token].rewardPerTokenStored;
                }
            }
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);
    event RewardsDurationUpdated(address token, uint256 newDuration);
 }
