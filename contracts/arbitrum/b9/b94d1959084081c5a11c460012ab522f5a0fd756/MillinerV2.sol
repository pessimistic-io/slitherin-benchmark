// SPDX-License-Identifier: GPL-3.0
/*                            ******@@@@@@@@@**@*                               
                        ***@@@@@@@@@@@@@@@@@@@@@@**                             
                     *@@@@@@**@@@@@@@@@@@@@@@@@*@@@*                            
                  *@@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@*@**                          
                 *@@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@*                         
                **@@@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@**                       
                **@@@@@@@@@@@@@@@*@@@@@@@@@@@@@@@@@@@@@@@*                      
                **@@@@@@@@@@@@@@@@*************************                    
                **@@@@@@@@***********************************                   
                 *@@@***********************&@@@@@@@@@@@@@@@****,    ******@@@@*
           *********************@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@************* 
      ***@@@@@@@@@@@@@@@*****@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@****@@*********      
   **@@@@@**********************@@@@*****************#@@@@**********            
  *@@******************************************************                     
 *@************************************                                         
 @*******************************                                               
 *@*************************                                                    
   ********************* 
   
    /$$$$$                                               /$$$$$$$   /$$$$$$   /$$$$$$ 
   |__  $$                                              | $$__  $$ /$$__  $$ /$$__  $$
      | $$  /$$$$$$  /$$$$$$$   /$$$$$$   /$$$$$$$      | $$  \ $$| $$  \ $$| $$  \ $$
      | $$ /$$__  $$| $$__  $$ /$$__  $$ /$$_____/      | $$  | $$| $$$$$$$$| $$  | $$
 /$$  | $$| $$  \ $$| $$  \ $$| $$$$$$$$|  $$$$$$       | $$  | $$| $$__  $$| $$  | $$
| $$  | $$| $$  | $$| $$  | $$| $$_____/ \____  $$      | $$  | $$| $$  | $$| $$  | $$
|  $$$$$$/|  $$$$$$/| $$  | $$|  $$$$$$$ /$$$$$$$/      | $$$$$$$/| $$  | $$|  $$$$$$/
 \______/  \______/ |__/  |__/ \_______/|_______/       |_______/ |__/  |__/ \______/                                      
*/

pragma solidity ^0.8.2;

// Libraries
import {SafeMath} from "./SafeMath.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";

// Interfaces
import "./IERC20.sol";
import "./HatDistributionCenter.sol";

// Milliner is the master of Hats.
contract MillinerV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        int256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of JONES
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accJonesPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accJonesPerShare` (and `lastRewardSecond`) gets updated.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated. (can be set to negative, that means the user is owed that amount)
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JONES to distribute per block.
        uint256 lastRewardSecond; // Last second number that JONES distribution occurs.
        uint256 accJonesPerShare; // Accumulated JONES per share, times 1e12. See below.
        uint256 currentDeposit; // Current deposited, fix from sushiswap to allow single staking of JONES
    }

    // The JONES TOKEN!
    IERC20 public jones;
    // JONES tokens created per second.
    uint256 public jonesPerSecond;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when JONES mining starts.
    uint256 public startTime;

    mapping(IERC20 => bool) public poolExistence;

    mapping(address => bool) public whitelistedContract;

    // Starts as the multisig but will pass to veJONES voter
    address public rewardManager;

    // Rewards contract
    HatDistributionCenter public hatDistributor;

    constructor(
        IERC20 _jones,
        uint256 _jonesPerSecond,
        uint256 _startTime,
        address _rewardManager,
        address _hatDistributor
    ) {
        if (_rewardManager == address(0)) {
            revert Zero_Address();
        }

        jones = _jones;
        jonesPerSecond = _jonesPerSecond;
        startTime = _startTime;
        rewardManager = _rewardManager;
        hatDistributor = HatDistributionCenter(_hatDistributor);
    }

    // ============================== View Functions ==============================

    /**
     * @return the current number of pools.
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * View function to see deposited LP on frontend.
     * @param _pid The pool Id,
     * @param _user User address
     */
    function deposited(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        return userInfo[_pid][_user].amount;
    }

    /**
     * View function to see pending JONES on frontend.
     * @param _pid The pool Id,
     * @param _user User address
     */
    function pendingJones(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accJonesPerShare = pool.accJonesPerShare;
        uint256 lpSupply = pool.currentDeposit;
        if (block.timestamp > pool.lastRewardSecond && lpSupply != 0) {
            uint256 multiplier = _getMultiplier(
                pool.lastRewardSecond,
                block.timestamp
            );
            uint256 jonesReward = multiplier
                .mul(jonesPerSecond)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accJonesPerShare = accJonesPerShare.add(
                jonesReward.mul(1e12).div(lpSupply)
            );
        }
        return
            _calculatePending(user.rewardDebt, accJonesPerShare, user.amount);
    }

    // ============================== User Functions ==============================

    /**
     * Deposit LP tokens to Milliner for JONES allocation.
     * @param _pid pool Id
     * @param _amount amount to deposit
     */
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        _senderIsEligible();
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (_amount == 0) revert Zero_Amount();
        updatePool(_pid);
        _deposit(user, pool, _amount, false);
        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * Withdraw LP tokens from Milliner.
     * @param _pid pool Id
     * @param _amount amount to withdraw
     */
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.amount < _amount) revert Not_Enough_Balance();
        if (_amount == 0) revert Zero_Amount();
        updatePool(_pid);

        // Send tokens
        pool.lpToken.safeTransfer(address(msg.sender), _amount);

        // Update variables
        user.rewardDebt =
            user.rewardDebt -
            int256(_amount.mul(pool.accJonesPerShare).div(1e12));

        user.amount = user.amount.sub(_amount);
        pool.currentDeposit -= _amount;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /**
     * @notice Harvest proceeds for transaction sender to `to`.
     * @param _pid The index of the pool. See `poolInfo`.
     */
    function harvest(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = _calculatePending(
            user.rewardDebt,
            pool.accJonesPerShare,
            user.amount
        );

        if (pending > 0) {
            _safeJonesTransfer(msg.sender, pending);
        }
        user.rewardDebt = (user.amount.mul(pool.accJonesPerShare).div(1e12))
            .toInt256();
        emit Harvest(msg.sender, _pid, pending);
    }

    /**
     * @notice Compounds rewards into the pool (only available for single staking).
     * @param _pid The index of the pool.
     */
    function compound(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (address(pool.lpToken) != address(jones))
            revert Single_Staking_Only();
        updatePool(_pid);
        uint256 pending = _calculatePending(
            user.rewardDebt,
            pool.accJonesPerShare,
            user.amount
        );
        if (pending != 0) {
            _deposit(user, pool, pending, true);
        }
        user.rewardDebt = (user.amount.mul(pool.accJonesPerShare).div(1e12))
            .toInt256();
    }

    /**
     * Withdraw without caring about rewards. EMERGENCY ONLY.
     * @param _pid pool Id
     */
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        pool.currentDeposit = 0;
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // ============================== Management Functions ==============================

    /**
     * Update reward variables of the given pool to be up-to-date.
     * @param _pid pool Id
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.timestamp > pool.lastRewardSecond) {
            uint256 lpSupply = pool.currentDeposit;
            if (lpSupply > 0 && pool.allocPoint > 0) {
                uint256 blocks = _getMultiplier(
                    pool.lastRewardSecond,
                    block.timestamp
                );
                uint256 jonesReward = blocks
                    .mul(jonesPerSecond)
                    .mul(pool.allocPoint)
                    .div(totalAllocPoint);

                pool.accJonesPerShare = pool.accJonesPerShare.add(
                    jonesReward.mul(1e12).div(lpSupply)
                );
            }
            pool.lastRewardSecond = block.timestamp;
        }
    }

    /**
     * Update reward variables for all pools.
     * @dev Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * Create a new pool, Can only be called by the owner.
     * @param _allocPoint Allocation points for the pool. rate = (_allocPoint * rewardRate) / totalAlloc
     * @param _lpToken The lp token for the farm
     * @param _withUpdate If it should update the pools (almost all cases this should be tue)
     */
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner nonDuplicated(_lpToken) {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardSecond = block.timestamp > startTime
            ? block.timestamp
            : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardSecond: lastRewardSecond,
                accJonesPerShare: 0,
                currentDeposit: 0
            })
        );
        emit NewPool(address(_lpToken), poolInfo.length - 1, _allocPoint);
    }

    /**
     * Update the given pool's JONES allocation point and deposit fee. Can only be called by the owner.
     * @param _pid The pool Id,
     * @param _allocPoint Allocation points for the pool. rate = (_allocPoint * rewardRate) / totalAlloc
     * @param _withUpdate If it should update the pools (almost all cases this should be tue)
     */
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyRewardsManager {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        emit PoolUpdate(_pid, _allocPoint);
    }

    /**
     * Updates the reward rate per second from now on.
     * @param _jonesPerSecond new rate
     */
    function updateEmissionRate(uint256 _jonesPerSecond) public onlyOwner {
        massUpdatePools();
        jonesPerSecond = _jonesPerSecond;
        massUpdatePools();
        emit UpdateEmissionRate(_jonesPerSecond);
    }

    /**
     * Migrates all rewards to another contract.
     * @dev to be used only in emergencies
     * @param _amount amount to be sent out
     * @param _to address to send the rewards to
     */
    function migrateRewards(uint256 _amount, address _to) public onlyOwner {
        jones.safeTransfer(_to, _amount);
    }

    /**
     * Adds contract to whitelist.
     * @param _contractAddress contract address
     */
    function addContractAddressToWhitelist(address _contractAddress)
        public
        virtual
        onlyOwner
    {
        whitelistedContract[_contractAddress] = true;
    }

    /**
     * Removes contract from whitelist.
     * @param _contractAddress contract address
     */
    function removeContractAddressFromWhitelist(address _contractAddress)
        public
        virtual
        onlyOwner
    {
        whitelistedContract[_contractAddress] = false;
    }

    function updateRewardsManager(address _newManager)
        public
        virtual
        onlyOwner
    {
        rewardManager = _newManager;
    }

    function updateHatDistributor(address _distributor)
        public
        virtual
        onlyOwner
    {
        if (_distributor == address(0)) {
            revert Zero_Address();
        }

        hatDistributor = HatDistributionCenter(_distributor);
    }

    // ============================== Internal Functions ==============================

    // Return reward multiplier over the given _from to _to timestamp.
    function _getMultiplier(uint256 _from, uint256 _to)
        private
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // Safe jones transfer function, just in case if rounding error causes pool to not have enough JONES.
    function _safeJonesTransfer(address _to, uint256 _amount) internal {
        hatDistributor.sendRewards(_amount, _to);
    }

    // Deposits and updates state variables
    function _deposit(
        UserInfo storage _user,
        PoolInfo storage _pool,
        uint256 _amount,
        bool _compound
    ) private {
        if (_amount > 0) {
            /// If its compounding then we there is no need to transfer
            if (!_compound) {
                _pool.lpToken.safeTransferFrom(
                    address(msg.sender),
                    address(this),
                    _amount
                );
            }
            _user.amount = _user.amount.add(_amount);
            _user.rewardDebt =
                _user.rewardDebt +
                int256(_amount.mul(_pool.accJonesPerShare).div(1e12));
            _pool.currentDeposit += _amount;
        }
    }

    function _senderIsEligible() internal view {
        if (msg.sender != tx.origin) {
            if (!whitelistedContract[msg.sender]) {
                revert Contract_Not_Whitelisted();
            }
        }
    }

    /**
     * Calculates the peding rewards with the given paramethers.
     * If the reward debt is negative it adds as pending, if its positive it counts as already payed.
     * @param _rewardDebt current user reward debt (or allowance)
     * @param _accJonesPerShare accomulated jones per share
     * @param _amount amount to which it is being calculated to
     */
    function _calculatePending(
        int256 _rewardDebt,
        uint256 _accJonesPerShare,
        uint256 _amount
    ) internal pure returns (uint256) {
        return
            _rewardDebt < 0
                ? _amount.mul(_accJonesPerShare).div(1e12).add(
                    (-_rewardDebt).toUint256()
                )
                : _amount.mul(_accJonesPerShare).div(1e12).sub(
                    (_rewardDebt).toUint256()
                );
    }

    // ============================== Modifiers ==============================

    modifier nonDuplicated(IERC20 _lpToken) {
        if (poolExistence[_lpToken]) revert Pool_For_Token_Exists();
        _;
    }

    modifier onlyRewardsManager() {
        if (msg.sender != rewardManager) {
            revert Not_Permited();
        }
        _;
    }

    // ============================== Events ==============================

    error Single_Staking_Only(); // Single staking only
    error E2(); // Reward transaction failed (add more JONES to Milliner)
    error Pool_For_Token_Exists(); // Cannot have 2 pools for same token
    error Not_Enough_Balance(); // Not enough balance
    error Zero_Amount(); // 0 amount
    error Contract_Not_Whitelisted(); // Contract not whitelisted
    error Not_Permited(); // Not authorized
    error Farm_Start_In_The_Past(); // Farm cannot start in the past
    error Zero_Address(); // Zero address

    // ============================== Events ==============================

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(uint256 jonesPerSecond);
    event PoolUpdate(uint256 pid, uint256 newAlloc);
    event NewPool(address lp, uint256 pid, uint256 newAlloc);
}

