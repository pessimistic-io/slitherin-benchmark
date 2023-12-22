//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/**

⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⢀⣠⣤⣤⣤⣾⣿⣿⣿⣿⣷⣶⣶⣦⡄⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠙⠛⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⡿⠿⠿⠿⠿⠿⠿⢿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢠⣤⣴⣶⣶⣶⣶⣦⣤⡄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣿⣿⣿⣿⣿⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⢿⣿⣿⡿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⣀⣠⣤⣶⣶⣤⣤⣤⣤⣶⣶⣤⣄⣀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⣿⡉⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣶⣿⡇⢻⣿⣿⣿⣧⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣥⣽⡇⢸⣿⣿⣿⣿⡄⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠈⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠉⠁⠈⠉⠉⠉⠉⠁⠀⠀⠀⠀⠀
  _  _   __  ___  ____________ _____ _____   _____  _   _  ___________ 
 | || | / / / _ \ | ___ \ ___ \  _  |_   _| /  __ \| | | ||  ___|  ___|
/ __) |/ / / /_\ \| |_/ / |_/ / | | | | |   | /  \/| |_| || |__ | |_   
\__ \    \ |  _  ||    /|    /| | | | | |   | |    |  _  ||  __||  _|  
(   / |\  \| | | || |\ \| |\ \\ \_/ / | |   | \__/\| | | || |___| |    
 |_|\_| \_/\_| |_/\_| \_\_| \_|\___/  \_/    \____/\_| |_/\____/\_|    
                                                                       
                                                                       
    https://twitter.com/Karrot_gg 
 */
 
import "./ABDKMath64x64.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Math.sol";
import "./KarrotInterfaces.sol";
import "./IRandomizer.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";

/**
-Cooks karrots
-Based on EggChefV2
-Vaults reward karrot holders with more karrots, ofsetting debase
-Smol protec: karrots are locked for 1 day, 10% of total rewards to this vault
-Big protec: karrots are locked for 1 day, 90% of total rewards to this vault
-Withdraw != Claim
-Rabbits may steal some of the user's claims if:
    -they don't have the thresold karrot balance in full protec fault
    -they don't have >33% of their liquidity in the protocol in the full protec pool
-Users karrots equivalent in the contract is added based on karrots needed to mint X LP tokens at time of deposit
-Users karrots equivalent in the contract is subtracted based on karrots needed to mint X LP tokens at time of withdrawal
-Debase happens when users claim rewards (calls debase function on Karrots contract)
-,43 +t2q' o?*3 b;pj
 */

contract KarrotChef is Ownable, ReentrancyGuard {
    //=========================================================================
    // SETUP
    //=========================================================================
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 public constant taxFreeRequestId = uint256(keccak256(abi.encodePacked("KARROT TAX EXEMPT (FOR COMPOUNDING)"))); //kek
    uint256 public constant REWARD_SCALING_FACTOR = 1e12;
    uint256 public constant KARROTS_DECIMALS = 1e18;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint224 rewardDebt; // Reward debt. See explanation below.
        uint32 lockEndedTimestamp;
        //
        //   pending reward = (user.amount * pool.accRewardPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRewardPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint128 allocPoint; // How many allocation points assigned to this pool. Rewards to distribute per block.
        uint32 lastRewardBlock; // Last block number that Rewards distribution occurs.
        uint96 accRewardPerShare; // Accumulated Rewards per share.
    }

    IConfig public config;

    // Compound ratio which is 1e13=0.001% (will be used to decrease supply)
    //word1
    uint16 public karrotClaimTaxRate = 3300; // 33%
    uint16 public fullProtecProtocolLiqProportion = 3300; // 33%
    uint16 public claimTaxChance = 2500; // 25%
    uint24 public callbackGasLimit = 10000000;
    uint40 public startBlock;    
    uint48 public compoundRatio = 13 * 1e12; //scales debase linearly if assuming compounding period of 1 block
    uint64 public lastBlock;
    uint16 public constant PERCENTAGE_DENOMINATOR = 10000;

    //word2
    uint8 public constant blockOffset = 1; //just to keep math safer maybe, so that user cant deposit on "block 0"
    uint88 public karrotRewardPerBlock = uint88(13000000 * KARROTS_DECIMALS); //13M karrots/block
    uint128 public totalAllocPoint = 0;
    uint32 public constant claimRequestTimeout = 15 minutes;

    bool isInitialized;
    bool public vaultDepositsAreOpen = false; //all vaults closed. (big/smol)
    bool public depositsPaused = false; //for pausing without resetting startblock

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // user's withdrawable rewards
    mapping(uint256 => mapping(address => uint256)) private userRewards;
    // Lock duration in seconds
    mapping(uint256 => uint256) public lockDurations;

    struct Request {
        uint16 poolId;
        uint240 feePaid;
        uint256 randomNumber;
        address sender;
    }

    mapping(uint256 => Request) public requests;
    mapping(address => bool) public claimRequestIsPending;
    mapping(address => uint256) public karrotChefKarrotEquivalentTotal;
    mapping(address => uint256) public userLastRequestTimestamp;

    // Events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 indexed pid, uint256 amount);
    event SetRewardPerBlock(uint88 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, IERC20 indexed lpToken);
    event SetAllocationPoint(uint256 indexed pid, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 lastRewardBlock, uint256 lpSupply, uint256 accRewardPerShare);
    event SetLockDuration(uint256 indexed pid, uint256 lockDuration);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount, uint256 tax);
    event RewardQueued(address _account, uint256 _pid, uint256 pending);
    event RequestedForPool(uint256 requestId, uint256 poolId);
    event RequestFulfilled(uint256 requestId, uint256 poolId);
    event Compound(address indexed user, uint256 amountKarrot, uint256 poolId);

    error CallerIsNotRequestSender(address caller, address requestSender);
    error RevealNotReady();
    error InvalidActionType();
    error CallerIsNotRandomizer();
    error EOAsOnly();
    error RabbitsPerWalletLimitReached();
    error NoPendingRewards(address user);
    error InsuffientFundsForRngRequest();
    error ForwardFailed();
    error UnauthorizedCaller(address caller);
    error CallerIsNotConfig();
    error VaultsDepositsAreClosed();
    error ClaimRequestPending();
    error CallerIsNotAccountOrThisContract();
    error PoolExists();
    error InvalidAmount();
    error InvalidAddress();
    error StillLocked();
    error ClaimRequestNotTimedOut();

    constructor(address _configManager) Ownable() ReentrancyGuard() {
        config = IConfig(_configManager);

        IKarrotsToken(config.karrotsAddress()).approve(config.karrotStolenPoolAddress(), type(uint).max);

        //default lockDurations
        lockDurations[0] = 1 days;
        lockDurations[1] = 1 days;
    }

    modifier onlyConfig() {
        if (msg.sender != address(config)) {
            revert CallerIsNotConfig();
        }
        _;
    }

    //================================================================================================
    // RANDOMIZER / COMMIT - REVEAL LOGIC
    //================================================================================================

    function requestClaim(uint256 _pid) external payable nonReentrant returns (uint256) {
        //supply a msg.value 20% above what the request will cost based on
        // await
        uint256 requestFee;
        uint256 requestId; 

        if (claimRequestIsPending[msg.sender]) {
            revert ClaimRequestPending();
        }
        if (msg.sender != tx.origin) {
            revert EOAsOnly();
        }

        updatePool(_pid);
        queueRewards(_pid, msg.sender);

        if (userRewards[_pid][msg.sender] == 0) {
            revert NoPendingRewards(msg.sender);
        }   

        IRandomizer randomizer = IRandomizer(config.randomizerAddress());

        requestFee = randomizer.estimateFee(callbackGasLimit);

        if (msg.value < requestFee) {
            revert InsuffientFundsForRngRequest();
        }

        //transfer request fee funds to our 'subscription' on the randomizer contract
        randomizer.clientDeposit{value: msg.value}(address(this));

        requestId = randomizer.request(callbackGasLimit);
        
        claimRequestIsPending[msg.sender] = true;
        userLastRequestTimestamp[msg.sender] = block.timestamp;

        requests[requestId] = Request({
            poolId: uint16(_pid),
            feePaid: uint240(msg.value),
            randomNumber: 0,
            sender: msg.sender
        });

        emit RequestedForPool(requestId, _pid);

        return requestId;
    }

    //called by randomizer contract to fulfill the requests
    function randomizerCallback(uint256 _id, bytes32 _value) external {
        if (msg.sender != config.randomizerAddress()) {
            revert CallerIsNotRandomizer();
        }

        uint256 randomNumber = uint256(_value);
        IRandomizer randomizer = IRandomizer(config.randomizerAddress());
        requests[_id].randomNumber = randomNumber;
        Request storage request = requests[_id];

        //[!] call  _claim (within this, rng-based tax rate for claim is applied if user full protec balance is below threshold)
        (uint256 reward, uint256 claimTax) = _claim(request.poolId, request.sender, randomNumber, _id, false);

        claimRequestIsPending[request.sender] = false; //set false here because _claim is used in other scenarios that don't involve requests.

        emit Claim(request.sender, request.poolId, reward, claimTax);
        emit RequestFulfilled(_id, request.poolId);
    }

    function previewClaimTaxResult(address _user, bytes32 _value) public view returns (bool) {
        return _userIsExemptFromClaimTax(_user, uint256(_value));
    }

    //=========================================================================
    // POOL ACTIONS
    //=========================================================================

    // Add a new lp to the pool. Can only be called by the owner.
    function addPool(uint128 _allocPoint, address _lpToken, bool _withUpdatePools) external onlyOwner {
        if(!lpTokenIsNotAlreadyAdded(_lpToken)){
            revert PoolExists();
        }
        if (_withUpdatePools) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: IERC20(_lpToken),
                allocPoint: _allocPoint,
                lastRewardBlock: uint32(lastRewardBlock),
                accRewardPerShare: 0
            })
        );

        emit LogPoolAddition(poolInfo.length - 1, _allocPoint, IERC20(_lpToken));
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function lpTokenIsNotAlreadyAdded(address _lpToken) internal view returns (bool) {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            if (address(poolInfo[pid].lpToken) == _lpToken) {
                return false;
            }
        }
        return true;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if(address(pool.lpToken) == address(0)){
            return;
        }
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply;
        if (address(pool.lpToken) == config.karrotsAddress()) {
            lpSupply = IKarrotsToken(config.karrotsAddress()).balanceOfUnderlying(address(this));
        } else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }

        if (lpSupply == 0) {
            pool.lastRewardBlock = uint32(block.number);
            return;
        }
        uint256 karrotsReward = ((block.number - pool.lastRewardBlock) * karrotRewardPerBlock * pool.allocPoint) /
            totalAllocPoint;
        pool.accRewardPerShare += uint96((karrotsReward * REWARD_SCALING_FACTOR) / lpSupply);
        pool.lastRewardBlock = uint32(block.number);

        emit PoolUpdated(_pid, pool.lastRewardBlock, lpSupply, pool.accRewardPerShare);
    }

    //=========================================================================
    // USER ACTIONS
    //=========================================================================

    // Deposit tokens to KarrotsChef for Karrots allocation.
    function deposit(uint256 _pid, uint256 _amount, address _account) external nonReentrant {
        if (msg.sender != _account && msg.sender != address(this)) {
            revert CallerIsNotAccountOrThisContract();
        }

        if (!vaultDepositsAreOpen || depositsPaused) {
            revert VaultsDepositsAreClosed();
        }

        if(_amount == 0){
            revert InvalidAmount();
        }

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_account];
        user.lockEndedTimestamp = uint32(block.timestamp + lockDurations[_pid]);
        
        updatePool(_pid);
        queueRewards(_pid, _account);

        pool.lpToken.transferFrom(_account, address(this), _amount);
        
        //for calculating total protocol TVL with karrot equivalent of LP tokens at time of deposit for big protec
        if(_pid == 0){
            karrotChefKarrotEquivalentTotal[_account] += getKarrotEquivalent(_amount);
        } else if (_pid == 1){
            karrotChefKarrotEquivalentTotal[_account] += _amount; 
        }

        if (address(pool.lpToken) == config.karrotsAddress()) {
            _amount = IKarrotsToken(config.karrotsAddress()).fragmentToKarrots(_amount);
        }

        user.amount += _amount;
        user.rewardDebt = uint224((user.amount * pool.accRewardPerShare) / REWARD_SCALING_FACTOR);

        emit Deposit(_account, _pid, _amount);

    }

    // Withdraw tokens from KarrotChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        if(_amount == 0){
            revert InvalidAmount();
        }
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if(user.lockEndedTimestamp > block.timestamp){
            revert StillLocked();
        }

        if(_amount > user.amount){
            revert InvalidAmount();
        }

        updatePool(_pid);
        queueRewards(_pid, msg.sender);

        user.amount -= _amount;
        user.rewardDebt = uint224((user.amount * pool.accRewardPerShare) / REWARD_SCALING_FACTOR);
        
        if (address(pool.lpToken) == config.karrotsAddress()) {
            _amount = IKarrotsToken(config.karrotsAddress()).karrotsToFragment(_amount);
        }

        //for calculating total protocol TVL with karrot equivalent of LP tokens at time of withdraw for big protec
        if(_pid == 0){

            uint256 karrotEquivalent = getKarrotEquivalent(_amount);
            //if karrot equivalent at time of withdraw is greater than users karrot equivalent total in big/smol, set to 0
            if(karrotChefKarrotEquivalentTotal[msg.sender] < karrotEquivalent){
                karrotChefKarrotEquivalentTotal[msg.sender] = 0;
            } else {
                karrotChefKarrotEquivalentTotal[msg.sender] -= karrotEquivalent;
            }

        } else if (_pid == 1){

            if(karrotChefKarrotEquivalentTotal[msg.sender] < _amount){
                karrotChefKarrotEquivalentTotal[msg.sender] = 0;
            } else {
                karrotChefKarrotEquivalentTotal[msg.sender] -= _amount;
            }

        }
        
        // pool.lpToken.safeTransfer(address(msg.sender), _amount);
        pool.lpToken.transfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
 
    }

    // Claim Karrots from KarrotChef
    function _claim(
        uint256 _pid,
        address _account,
        uint256 _randomNumber,
        uint256 _requestId,
        bool callerIsCompounder
    )
        internal
        returns (
            uint256,
            uint256
        )
    {
        if (msg.sender != address(this) && msg.sender != config.randomizerAddress() && !callerIsCompounder) {
            revert UnauthorizedCaller(msg.sender);
        }

        //[!] potentially not needed here because it'll be in the request function??
        updatePool(_pid);
        queueRewards(_pid, _account);

        uint256 pendingRewards = userRewards[_pid][_account];
        if (pendingRewards == 0) {
            revert NoPendingRewards(_account);
        }

        IKarrotsToken karrots = IKarrotsToken(config.karrotsAddress());

        UserInfo storage user = userInfo[_pid][_account];
        user.lockEndedTimestamp = uint32(block.timestamp) + uint32(lockDurations[_pid]);

        userRewards[_pid][_account] = 0;
        userInfo[_pid][_account].rewardDebt = uint224(
            (userInfo[_pid][_account].amount * poolInfo[_pid].accRewardPerShare) /
            (REWARD_SCALING_FACTOR));

        if (lastBlock != block.number) {
            uint256 compoundedVal = compound(KARROTS_DECIMALS, compoundRatio, block.number - lastBlock) - KARROTS_DECIMALS;
            karrots.rebase(block.number, compoundedVal, false);
            lastBlock = uint64(block.number);

            IUniswapV2Pair(config.karrotsPoolAddress()).sync();
        }

        //[!] if user has enough deposited into the Full Protec Pool, no withdrawal tax
        //if they don't, there will be a 25% chance of a 33% tax on their claim
        //the taxed amount will be sent to the stolen pool
        uint256 tax;
        if (_userIsExemptFromClaimTax(_account, _randomNumber) || _requestId == taxFreeRequestId) {
            karrots.mint(_account, pendingRewards);
            emit RewardPaid(_account, _pid, pendingRewards);        
        } else {
            tax = Math.mulDiv(pendingRewards, karrotClaimTaxRate, PERCENTAGE_DENOMINATOR);
            karrots.mint(_account, pendingRewards - tax);
            karrots.mint(address(this), tax);

            if(IKarrotsToken(config.karrotsAddress()).allowance(address(this), config.karrotStolenPoolAddress()) < tax){
                IKarrotsToken(config.karrotsAddress()).approve(config.karrotStolenPoolAddress(), tax);
            }
            
            IStolenPool(config.karrotStolenPoolAddress()).deposit(tax);
            emit RewardPaid(config.karrotStolenPoolAddress(), _pid, tax);  
            emit RewardPaid(_account, _pid, pendingRewards - tax);
        }
        
        return (pendingRewards, tax);
    }

    /// @dev claims pending karrot rewards in smol protec vault tax-free, then immediately deposits back into smol protec vault
    function compoundSmol() external {
        uint256 _randomNumber = 0;
        (uint256 rewards, ) = _claim(1, msg.sender, _randomNumber, taxFreeRequestId, true);
        this.deposit(1, rewards, msg.sender);
        emit Compound(msg.sender, rewards, 1);
    }

    /// @dev claims pending karrot rewards in big protec vault tax-free, then immediately deposits these karrots + additional eth back into big protec vault
    function compoundBig(
        uint256 _amountTokenDesired,
        uint256 _amountTokenMin,
        uint256 _amountETHMin
    ) external payable returns (uint256) {
        address routerAddress = config.sushiswapRouterAddress();
        address karrotsAddress = config.karrotsAddress();
        uint256 _randomNumber = 0;
        _claim(0, msg.sender, _randomNumber, taxFreeRequestId, true);

        IERC20(karrotsAddress).transferFrom(msg.sender, address(this), _amountTokenDesired);
        IERC20(karrotsAddress).approve(routerAddress, _amountTokenDesired);

        (uint256 token, , uint256 liq) = IUniswapV2Router02(routerAddress).addLiquidityETH{value: msg.value}(
            karrotsAddress,
            _amountTokenDesired,
            _amountTokenMin,
            _amountETHMin,
            msg.sender,
            block.timestamp
        );

        this.deposit(0, liq, msg.sender);

        if(_amountTokenDesired - token > 0){
            IERC20(karrotsAddress).transfer(msg.sender, _amountTokenDesired - token);
        }

        emit Compound(msg.sender, _amountTokenDesired, 0);
        return liq;
    }

    function queueRewards(uint256 _pid, address _account) internal {
        UserInfo storage user = userInfo[_pid][_account];
        uint256 pendingRewards = Math.mulDiv(user.amount, poolInfo[_pid].accRewardPerShare, REWARD_SCALING_FACTOR) - user.rewardDebt;
        if (pendingRewards > 0) {
            userRewards[_pid][_account] += pendingRewards;
        }
        emit RewardQueued(_account, _pid, pendingRewards);
    }

    function randomizerWithdrawKarrotChef(address _to, uint256 _amount) external {
        if(msg.sender != address(config) && msg.sender != owner()){
            revert UnauthorizedCaller(msg.sender);
        }
        if(_to == address(0)){
            revert InvalidAddress();
        }
        IRandomizer randomizer = IRandomizer(config.randomizerAddress());
        (uint256 depositedBalance, ) = randomizer.clientBalanceOf(address(this));
        if(_amount > depositedBalance){
            revert InvalidAmount();
        }
        randomizer.clientWithdrawTo(_to, _amount);
    }

    //=========================================================================
    // GETTERS
    //=========================================================================

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see pending Karrots on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (address(pool.lpToken) == config.karrotsAddress()) {
            lpSupply = IKarrotsToken(config.karrotsAddress()).balanceOfUnderlying(address(this));
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 karrotsReward = (block.number - pool.lastRewardBlock) * Math.mulDiv(karrotRewardPerBlock, pool.allocPoint, totalAllocPoint);
            accRewardPerShare += (karrotsReward * REWARD_SCALING_FACTOR) / lpSupply;
        }
        return userRewards[_pid][_user] + (user.amount * accRewardPerShare / REWARD_SCALING_FACTOR) - user.rewardDebt;
    }

    function _userIsExemptFromClaimTax(address _user, uint256 _randomNumber) internal view returns (bool) {
        //check both threshold karrot amount in full protec, and % of total karrots in all vaults in full protec to be above 33% (or n%)
        IFullProtec fullProtec = IFullProtec(config.karrotFullProtecAddress());
        bool thresholdCheck = fullProtec.getIsUserAboveThresholdToAvoidClaimTax(_user);
        
        uint256 karrotsInFullProtec = fullProtec.getUserStakedAmount(_user);
        uint256 karrotsInSmol = userInfo[1][_user].amount;
        uint256 karrotEquivalentInBig = karrotChefKarrotEquivalentTotal[_user];
        
        if(karrotsInFullProtec + karrotsInSmol == 0) {
            return false;
        }

        uint256 karrotsInFullProtecRatio = Math.mulDiv(karrotsInFullProtec, PERCENTAGE_DENOMINATOR, karrotsInFullProtec + karrotsInSmol + karrotEquivalentInBig);
        bool ratioCheck = karrotsInFullProtecRatio > fullProtecProtocolLiqProportion;

        if(thresholdCheck && ratioCheck) {
            return true;
        }

        // else 25% chance of 33% claim tax applying (or new values)
        uint256 randomNumber = _randomNumber % PERCENTAGE_DENOMINATOR;
        if(randomNumber > claimTaxChance) {
            return true;
        }

        //if none of these conditions apply, claim tax is applied.
        return false;
    }

    // gets karrots that would have been deposited to get N lp tokens at time of deposit
    function getKarrotEquivalent(uint256 _amount) public view returns (uint256) {
            uint256 tokenReserve;
            IUniswapV2Pair karrotsEthPool = IUniswapV2Pair(config.karrotsPoolAddress());
            uint256 totalLpTokenSupply = karrotsEthPool.totalSupply();
            (uint112 _reserve0, uint112 _reserve1, ) = karrotsEthPool.getReserves();
            address token0 = karrotsEthPool.token0();
            address token1 = karrotsEthPool.token1();

            if(token0 == config.karrotsAddress()){
                tokenReserve = uint256(_reserve0);
            } else if(token1 == config.karrotsAddress()){
                tokenReserve = uint256(_reserve1);
            }
            //get % of LP token supply to be deposited
            uint256 lpTokenRatioAtTimeOfDeposit = Math.mulDiv(totalLpTokenSupply, 1, IKarrotsToken(config.karrotsAddress()).karrotsToFragment(_amount)); // gets "inverse proportion" of LP tokens to be deposited -- total/user

            //get equivalent amount of karrots at time of deposit based on % of LP tokens to be deposited and reserve of karrots in pool. 
            // ideally s.t. this always returns non-zero even if user has 1 wei worth of LP token, though maybe instituting a minimum deposit amount is better
            uint256 karrotEquivalent = Math.mulDiv(tokenReserve, KARROTS_DECIMALS, lpTokenRatioAtTimeOfDeposit * KARROTS_DECIMALS);
            return karrotEquivalent;
    }

    function getTotalAmountStakedInPoolByUser(uint256 _pid, address _user) external view returns (uint256) {
        return IKarrotsToken(config.karrotsAddress()).karrotsToFragment(userInfo[_pid][_user].amount);
    }

    function getRandomNumber(uint256 _requestId) external view returns (uint256) {
        return requests[_requestId].randomNumber;
    }

    function poolIdToToken(uint256 _pid) external view returns (address) {
        return address(poolInfo[_pid].lpToken);
    }



    //=========================================================================
    // SETTERS (CONFIG MANAGER CONTROLLED)
    //=========================================================================

    /// @dev unstuck failed claim request after presumed timeout
    function setPendingRequestToFalse() external {
        if(block.timestamp < userLastRequestTimestamp[msg.sender] + claimRequestTimeout){
            revert ClaimRequestNotTimedOut();
        }
        claimRequestIsPending[msg.sender] = false;
    }

    // Update the given pool's Karrots allocation point. Can only be called by the config manager.
    function setAllocationPoint(uint256 _pid, uint128 _allocPoint, bool _withUpdatePools) external onlyConfig {
        if (_withUpdatePools) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - uint128(poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        emit SetAllocationPoint(_pid, _allocPoint);
    }

    function setLockDuration(uint256 _pid, uint256 _lockDuration) external onlyConfig {
        lockDurations[_pid] = _lockDuration;
        emit SetLockDuration(_pid, _lockDuration);
    }

    function updateRewardPerBlock(uint88 _rewardPerBlock) external onlyConfig {

        massUpdatePools();
        karrotRewardPerBlock = _rewardPerBlock;
        emit SetRewardPerBlock(_rewardPerBlock);
    }

    function setCompoundRatio(uint48 _compoundRatio) external onlyConfig {
        compoundRatio = _compoundRatio;
    }

    function openKarrotChefDeposits() external onlyConfig {
        startBlock = uint40(block.number - blockOffset);
        lastBlock = startBlock;
        vaultDepositsAreOpen = true;
    }

    function setDepositIsPaused(bool _isPaused) external onlyConfig {
        depositsPaused = _isPaused;
    }

    function setClaimTaxRate(uint16 _maxTaxRate) external onlyConfig {
        karrotClaimTaxRate = _maxTaxRate;
    }

    function withdrawRequestFeeFunds(address _to, uint256 _amount) external onlyConfig {
        IRandomizer(config.randomizerAddress()).clientWithdrawTo(_to, _amount);
    }

    function setRandomizerClaimCallbackGasLimit(uint24 _callbackGasLimit) external onlyConfig{
        callbackGasLimit = _callbackGasLimit;
    }

    function setFullProtecLiquidityProportion(uint16 _fullProtecLiquidityProportion) external onlyConfig {
        fullProtecProtocolLiqProportion = _fullProtecLiquidityProportion;
    }

    function setClaimTaxChance(uint16 _claimTaxChance) external onlyConfig{
        claimTaxChance = _claimTaxChance;
    }

    function setConfigManagerAddress(address _configManagerAddress) external onlyOwner {
        config = IConfig(_configManagerAddress);
    }

    //=========================================================================
    // MATH
    //=========================================================================

    function pow(int128 x, uint256 n) public pure returns (int128 r) {
        r = ABDKMath64x64.fromUInt(1);
        while (n > 0) {
            if (n % 2 == 1) {
                r = ABDKMath64x64.mul(r, x);
                n -= 1;
            } else {
                x = ABDKMath64x64.mul(x, x);
                n /= 2;
            }
        }
    }

    function compound(uint256 principal, uint256 ratio, uint256 n) public pure returns (uint256) {
        return
            ABDKMath64x64.mulu(
                pow(ABDKMath64x64.add(ABDKMath64x64.fromUInt(1), ABDKMath64x64.divu(ratio, 10 ** 18)), n),
                principal
            );
    }
}

