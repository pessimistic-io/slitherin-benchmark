// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//openzepplin
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./SafeCast.sol";
import "./Ownable.sol";
import "./Pausable.sol";

import "./IRewarder.sol";
import "./IXSteakTokenUsage.sol";

/// @title Enigma vault contracts
/// @notice Next generation liquidity management protocol ontop of Uniswap v3
/// @notice Allows for liquidity mining of Enigma Pools
/// @author by SteakHut Labs © 2023
contract EnigmaBoostedMasterchef is Ownable, IXSteakTokenUsage, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    /// @notice Info of each Boosted Enigma user
    /// `amount` LP token amount the user has provided
    /// `rewardDebt` The amount of xSTEAK entitled to the user
    /// `factor` the users factor, use _getUserFactor
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 factor;
    }

    /// @notice Info of each Boosted Enigma pool
    /// `allocPoint` The amount of allocation points assigned to the pool
    /// Also known as the amount of xSTEAK to distribute per block
    struct PoolInfo {
        // Address are stored in 160 bits, so we store allocPoint in 96 bits to
        // optimize storage (160 + 96 = 256)
        IERC20 lpToken;
        uint96 allocPoint;
        uint256 accJoePerShare;
        uint256 accJoePerFactorPerShare;
        // Address are stored in 160 bits, so we store lastRewardTimestamp in 64 bits and
        // veJoeShareBp in 32 bits to optimize storage (160 + 64 + 32 = 256)
        uint64 lastRewardTimestamp;
        IRewarder rewarder;
        /// @dev should be rewarder contract
        // Share of the reward to distribute to veJoe holders
        uint32 veJoeShareBp;
        // The sum of all veJoe held by users participating in this farm
        // This value is updated when
        // - A user enter/leaves a farm
        // - A user claims veJOE
        // - A user unstakes JOE
        uint256 totalFactor;
        // The total LP supply of the farm
        // This is the sum of all users boosted amounts in the farm. Updated when
        // someone deposits or withdraws.
        // This is used instead of the usual `lpToken.balanceOf(address(this))` for security reasons
        uint256 totalLpSupply;
    }

    /// @notice the amount of xSteak to emit per second
    uint256 public xSteakPerSec;

    /// @notice Address of STEAK contract
    IERC20 public STEAK;
    /// @notice Address of xSTEAK contract
    IERC20 public xSTEAK;
    /// @notice The index of BMCJ master pool in MCJV2
    uint256 public MASTER_PID;

    /// @notice Info of each BMCJ pool
    PoolInfo[] public poolInfo;
    /// @dev Maps an address to a bool to assert that a token isn't added twice
    mapping(IERC20 => bool) private checkPoolDuplicate;

    /// @notice Info of each user that stakes LP tokens
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools
    uint256 public totalAllocPoint;
    uint256 private ACC_TOKEN_PRECISION;

    /// @dev Amount of claimable Joe the user has, this is required as we
    /// need to update rewardDebt after a token operation but we don't
    /// want to send a reward at this point. This amount gets added onto
    /// the pending amount when a user claims
    mapping(uint256 => mapping(address => uint256)) public claimableJoe;

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------
    event Add(
        uint256 indexed pid, uint256 allocPoint, uint256 veJoeShareBp, IERC20 indexed lpToken, address indexed rewarder
    );
    event Set(uint256 indexed pid, uint256 allocPoint, uint256 veJoeShareBp, address indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTimestamp,
        uint256 lpSupply,
        uint256 accJoePerShare,
        uint256 accJoePerFactorPerShare
    );
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Init(uint256 amount);
    event UpdateJoePerSec(uint256 _emissionRate);
    event Allocate(address indexed userAddress, uint256 amount);
    event Deallocate(address indexed userAddress, uint256 amount);

    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    /// @dev Constructor for the Enigma Pool contract that sets the Enigma Factory
    constructor(address steakToken, address xSteakToken) {
        STEAK = IERC20(steakToken);
        xSTEAK = IERC20(xSteakToken);

        ACC_TOKEN_PRECISION = 1e18;
    }

    /// -----------------------------------------------------------
    /// Ownable External Functions
    /// -----------------------------------------------------------

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param _allocPoint AP of the new pool.
    /// @param _veJoeShareBp Share of rewards allocated in proportion to user's liquidity
    /// and veJoe balance
    /// @param _lpToken Address of the LP ERC-20 token.
    /// @param _rewarder Address of the rewarder delegate.
    function add(uint96 _allocPoint, uint32 _veJoeShareBp, IERC20 _lpToken, IRewarder _rewarder) external onlyOwner {
        require(!checkPoolDuplicate[_lpToken], "BoostedMasterChefJoe: LP already added");
        require(_veJoeShareBp <= 10_000, "BoostedMasterChefJoe: veJoeShareBp needs to be lower than 10000");
        require(poolInfo.length <= 50, "BoostedMasterChefJoe: Too many pools");
        checkPoolDuplicate[_lpToken] = true;
        // Sanity check to ensure _lpToken is an ERC20 token
        _lpToken.balanceOf(address(this));
        // Sanity check if we add a rewarder
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(address(0), 0);
        }

        massUpdatePools();

        totalAllocPoint = totalAllocPoint + _allocPoint;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                accJoePerShare: 0,
                accJoePerFactorPerShare: 0,
                lastRewardTimestamp: uint64(block.timestamp),
                rewarder: _rewarder,
                veJoeShareBp: _veJoeShareBp,
                totalFactor: 0,
                totalLpSupply: 0
            })
        );
        emit Add(poolInfo.length - 1, _allocPoint, _veJoeShareBp, _lpToken, address(_rewarder));
    }

    /// @notice Update the given pool's JOE allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _allocPoint New AP of the pool
    /// @param _veJoeShareBp Share of rewards allocated in proportion to user's liquidity
    /// and veJoe balance
    /// @param _rewarder Address of the rewarder delegate
    /// @param _overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored
    function set(uint256 _pid, uint96 _allocPoint, uint32 _veJoeShareBp, IRewarder _rewarder, bool _overwrite)
        external
        onlyOwner
    {
        require(_veJoeShareBp <= 10_000, "BoostedMasterChefJoe: veJoeShareBp needs to be lower than 10000");
        massUpdatePools();

        PoolInfo storage pool = poolInfo[_pid];
        totalAllocPoint = totalAllocPoint + _allocPoint - pool.allocPoint;
        pool.allocPoint = _allocPoint;
        pool.veJoeShareBp = _veJoeShareBp;
        if (_overwrite) {
            if (address(_rewarder) != address(0)) {
                // Sanity check
                _rewarder.onJoeReward(address(0), 0);
            }
            pool.rewarder = _rewarder;
        }

        emit Set(_pid, _allocPoint, _veJoeShareBp, _overwrite ? address(_rewarder) : address(pool.rewarder), _overwrite);
    }

    /// -----------------------------------------------------------
    /// External Functions
    /// -----------------------------------------------------------

    /// @notice Deposit LP tokens to BMCJ for JOE allocation
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _amount LP token amount to deposit
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        // Pay a user any pending rewards
        if (user.amount != 0) {
            _harvestXSteak(user, pool, _pid);
        }

        uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
        pool.lpToken.safeTransferFrom(_msgSender(), address(this), _amount);
        uint256 receivedAmount = pool.lpToken.balanceOf(address(this)) - (balanceBefore);

        _updateUserAndPool(_msgSender(), user, pool, receivedAmount, true);

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(_msgSender(), user.amount);
        }
        emit Deposit(_msgSender(), _pid, receivedAmount);
    }

    /// @notice Withdraw LP tokens from BMCJ
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _amount LP token amount to withdraw
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];
        require(user.amount >= _amount, "BoostedMasterChefJoe: withdraw not good");

        if (user.amount != 0) {
            _harvestXSteak(user, pool, _pid);
        }

        _updateUserAndPool(_msgSender(), user, pool, _amount, false);

        pool.lpToken.safeTransfer(_msgSender(), _amount);

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(_msgSender(), user.amount);
        }
        emit Withdraw(_msgSender(), _pid, _amount);
    }

    /// @notice Withdraw without caring about rewards (EMERGENCY ONLY)
    /// @param _pid The index of the pool. See `poolInfo`
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_msgSender()];

        pool.totalFactor = pool.totalFactor - (user.factor);
        pool.totalLpSupply = pool.totalLpSupply - (user.amount);
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.factor = 0;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onJoeReward(_msgSender(), 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero
        pool.lpToken.safeTransfer(_msgSender(), amount);
        emit EmergencyWithdraw(_msgSender(), _pid, amount);
    }

    /// @notice sets the amount of xSteak to pay per seconds
    /// @param _newXSteakPerSec new emissions rate
    function setXSteakPerSec(uint256 _newXSteakPerSec) external onlyOwner {
        xSteakPerSec = _newXSteakPerSec;

        emit UpdateJoePerSec(_newXSteakPerSec);
    }

    /// @notice View function to see pending JOE on frontend
    /// @param _pid The index of the pool. See `poolInfo`
    /// @param _user Address of user
    /// @return pendingJoe JOE reward for a given user.
    /// @return bonusTokenAddress The address of the bonus reward.
    /// @return pendingBonusToken The amount of bonus rewards pending.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256 pendingJoe, address bonusTokenAddress, uint256 pendingBonusToken)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accJoePerShare = pool.accJoePerShare;
        uint256 accJoePerFactorPerShare = pool.accJoePerFactorPerShare;

        if (block.timestamp > pool.lastRewardTimestamp && pool.totalLpSupply != 0 && pool.allocPoint != 0) {
            uint256 secondsElapsed = block.timestamp - pool.lastRewardTimestamp;

            uint256 joeReward = secondsElapsed * xSteakPerSec * pool.allocPoint / totalAllocPoint;

            accJoePerShare = accJoePerShare
                + (joeReward * ACC_TOKEN_PRECISION * (10_000 - pool.veJoeShareBp) / (pool.totalLpSupply * 10_000));

            if (pool.veJoeShareBp != 0 && pool.totalFactor != 0) {
                accJoePerFactorPerShare = accJoePerFactorPerShare
                    + (joeReward * (ACC_TOKEN_PRECISION) * (pool.veJoeShareBp) / (pool.totalFactor * (10_000)));
            }
        }

        pendingJoe = ((user.amount * accJoePerShare) + (user.factor * accJoePerFactorPerShare)) / (ACC_TOKEN_PRECISION)
            + claimableJoe[_pid][_user] - (user.rewardDebt);

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    /// @notice Returns the number of BMCJ pools.
    /// @return pools The amount of pools in this farm
    function poolLength() external view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(i);
        }
    }

    /// @notice Update reward variables of the given pool
    /// @param _pid The index of the pool. See `poolInfo`
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastRewardTimestamp = pool.lastRewardTimestamp;
        if (block.timestamp > lastRewardTimestamp) {
            uint256 lpSupply = pool.totalLpSupply;
            uint256 allocPoint = pool.allocPoint;
            // gas opt and prevent div by 0
            if (lpSupply != 0 && allocPoint != 0) {
                uint256 secondsElapsed = block.timestamp - lastRewardTimestamp;
                uint256 veJoeShareBp = pool.veJoeShareBp;
                uint256 totalFactor = pool.totalFactor;

                uint256 joeReward = secondsElapsed * (xSteakPerSec) * (allocPoint) / (totalAllocPoint);
                pool.accJoePerShare = pool.accJoePerShare
                    + (joeReward * (ACC_TOKEN_PRECISION) * (10_000 - veJoeShareBp) / (lpSupply * (10_000)));
                // If veJoeShareBp is 0, then we don't need to update it
                if (veJoeShareBp != 0 && totalFactor != 0) {
                    pool.accJoePerFactorPerShare = pool.accJoePerFactorPerShare
                        + (joeReward * (ACC_TOKEN_PRECISION) * (veJoeShareBp) / (totalFactor * (10_000)));
                }
            }
            pool.lastRewardTimestamp = uint64(block.timestamp);
            emit UpdatePool(_pid, pool.lastRewardTimestamp, lpSupply, pool.accJoePerShare, pool.accJoePerFactorPerShare);
        }
    }

    /// @notice Return an user's factor
    /// @param amount The user's amount of liquidity
    /// @param xSteakBalance The user's xSteak balance
    /// @return uint256 The user's factor
    function _getUserFactor(uint256 amount, uint256 xSteakBalance) private pure returns (uint256) {
        return Math.sqrt(amount * xSteakBalance);
    }

    /// @notice Updates user and pool infos
    /// @param _user The user that needs to be updated
    /// @param _pool The pool that needs to be updated
    /// @param _amount The amount that was deposited or withdrawn
    /// @param _isDeposit If the action of the user is a deposit
    function _updateUserAndPool(
        address _userAddress,
        UserInfo storage _user,
        PoolInfo storage _pool,
        uint256 _amount,
        bool _isDeposit
    ) private {
        uint256 oldAmount = _user.amount;
        uint256 newAmount = _isDeposit ? oldAmount + (_amount) : oldAmount - (_amount);

        if (_amount != 0) {
            _user.amount = newAmount;
            _pool.totalLpSupply = _isDeposit ? _pool.totalLpSupply + (_amount) : _pool.totalLpSupply - (_amount);
        }

        uint256 oldFactor = _user.factor;
        uint256 newFactor = _getUserFactor(newAmount, usersAllocation[_userAddress]);

        if (oldFactor != newFactor) {
            _user.factor = newFactor;
            _pool.totalFactor = _pool.totalFactor + (newFactor) - (oldFactor);
        }

        _user.rewardDebt =
            newAmount * (_pool.accJoePerShare) + (newFactor * (_pool.accJoePerFactorPerShare)) / (ACC_TOKEN_PRECISION);
    }

    /// @notice Harvests user's pending xSteak
    /// @dev WARNING this function doesn't update user's rewardDebt,
    /// it still needs to be updated in order for this contract to work properlly
    /// @param _user The user that will harvest its rewards
    /// @param _pool The pool where the user staked and want to harvest its JOE
    /// @param _pid The pid of that pool
    function _harvestXSteak(UserInfo storage _user, PoolInfo storage _pool, uint256 _pid) private {
        uint256 pending = ((_user.amount * _pool.accJoePerShare) + (_user.factor * _pool.accJoePerFactorPerShare))
            / (ACC_TOKEN_PRECISION) + (claimableJoe[_pid][_msgSender()]) - (_user.rewardDebt);

        claimableJoe[_pid][_msgSender()] = 0;

        //if rewards transfer them
        if (pending != 0) {
            xSTEAK.safeTransfer(_msgSender(), pending);
            emit Harvest(_msgSender(), _pid, pending);
        }
    }

    /// -----------------------------------------------------------
    /// External Functions
    /// -----------------------------------------------------------

    /// @notice Updates factor after after a xSteak token operation.
    /// This function needs to be called by this contract
    /// every allocation / deallocation
    /// @param _user The users address we are updating
    /// @param _newXSteakBalance The new balance of the users allocated xSTEAK
    function _updateFactor(address _user, uint256 _newXSteakBalance) internal {
        uint256 len = poolInfo.length;
        uint256 _ACC_TOKEN_PRECISION = ACC_TOKEN_PRECISION;

        for (uint256 pid; pid < len; ++pid) {
            UserInfo storage user = userInfo[pid][_user];

            // Skip if user doesn't have any deposit in the pool
            uint256 amount = user.amount;
            if (amount == 0) {
                continue;
            }

            PoolInfo storage pool = poolInfo[pid];

            updatePool(pid);
            uint256 oldFactor = user.factor;
            (uint256 accJoePerShare, uint256 accJoePerFactorPerShare) =
                (pool.accJoePerShare, pool.accJoePerFactorPerShare);
            uint256 pending = amount * (accJoePerShare)
                + (oldFactor * (accJoePerFactorPerShare)) / (_ACC_TOKEN_PRECISION) - (user.rewardDebt);

            // Increase claimableJoe
            claimableJoe[pid][_user] = claimableJoe[pid][_user] + (pending);

            // Update users veJoeBalance
            uint256 newFactor = _getUserFactor(amount, _newXSteakBalance);
            user.factor = newFactor;
            pool.totalFactor = pool.totalFactor + (newFactor) - (oldFactor);

            user.rewardDebt = (amount * accJoePerShare + (newFactor * accJoePerFactorPerShare)) / (_ACC_TOKEN_PRECISION);

            // Update the pool total veJoe
        }
    }

    /// -----------------------------------------------------------
    /// -----------------------------------------------------------
    /// -----------------------------------------------------------
    /// XSTEAK INTERFACING FUNCTIONS
    /// -----------------------------------------------------------
    /// -----------------------------------------------------------
    /// -----------------------------------------------------------

    mapping(address => uint256) public usersAllocation; // User's xSteak allocation
    uint256 public totalAllocation; // Contract's total xSteak allocation

    /**
     * @dev Checks if caller is the xSteakToken contract
     */
    modifier xSteakTokenOnly() {
        require(msg.sender == address(xSTEAK), "xSteakTokenOnly: caller should be xSteakToken");
        _;
    }

    /**
     * Allocates "userAddress" user's "amount" of xSteak to this dividends contract
     *
     * Can only be called by xSteakToken contract, which is trusted to verify amounts
     * "data" is only here for compatibility reasons (IxSteakTokenUsage)
     */
    function allocate(address userAddress, uint256 amount, bytes calldata /*data*/ )
        external
        override
        nonReentrant
        xSteakTokenOnly
    {
        uint256 _newAllocation = usersAllocation[userAddress] + (amount);
        usersAllocation[userAddress] = _newAllocation;
        totalAllocation = totalAllocation + (amount);

        _updateFactor(userAddress, _newAllocation);

        emit Allocate(userAddress, amount);
    }

    /**
     * Deallocates "userAddress" user's "amount" of xSteak allocation from this dividends contract
     *
     * Can only be called by xSteakToken contract, which is trusted to verify amounts
     * "data" is only here for compatibility reasons (IxSteakTokenUsage)
     */
    function deallocate(address userAddress, uint256 amount, bytes calldata /*data*/ )
        external
        override
        nonReentrant
        xSteakTokenOnly
    {
        uint256 _newAllocation = usersAllocation[userAddress] - (amount);
        usersAllocation[userAddress] = _newAllocation;
        totalAllocation = totalAllocation - (amount);

        _updateFactor(userAddress, _newAllocation);

        emit Deallocate(userAddress, amount);
    }

    /// -----------------------------------------------------------
    /// -----------------------------------------------------------
    /// -----------------------------------------------------------
    /// END
    /// -----------------------------------------------------------
    /// -----------------------------------------------------------
    /// -----------------------------------------------------------
}

