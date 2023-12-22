// SPDX-License-Identifier: MIT

// THIS IS A COPY OF SUSHISWAP MINICHEF REPURPOSED FOR MILK

pragma solidity 0.6.12;

pragma experimental ABIEncoderV2;

import "./BoringMath.sol";
import "./BoringBatchable.sol";
import "./BoringOwnable.sol";
import "./SignedSafeMath.sol";

interface IMigratorChef {
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    function migrate(IERC20 token) external returns (IERC20);
}

interface IToken {
    function mint(address _to, uint256 amount) external;
}

contract MiniChefV2 is BoringOwnable, BoringBatchable {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using BoringERC20 for IERC20;
    using SignedSafeMath for int256;

    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of milk entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of milk to distribute per block.
    struct PoolInfo {
        uint128 accMilkPerShare;
        uint64 lastRewardTime;
        uint64 allocPoint;
    }

    /// @notice Address of milk contract.
    IToken public MILK;
    // @notice The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    /// @notice Info of each MCV2 pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each MCV2 pool.
    IERC20[] public lpToken;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @dev Tokens added
    mapping(address => bool) public addedTokens;

    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public milkPerSecond;
    uint256 private constant ACC_MILK_PRECISION = 1e12;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20 indexed lpToken
    );
    event LogSetPool(uint256 indexed pid, uint256 allocPoint, bool overwrite);
    event LogUpdatePool(
        uint256 indexed pid,
        uint64 lastRewardTime,
        uint256 lpSupply,
        uint256 accMilkPerShare
    );
    event LogMilkPerSecond(uint256 milkPerSecond);

    /// @param _milk The MILK token contract address.
    constructor(IToken _milk) public {
        MILK = IToken(_milk);
    }

    /// @notice Returns the number of MCV2 pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    function add(uint256 allocPoint, IERC20 _lpToken) public onlyOwner {
        require(addedTokens[address(_lpToken)] == false, "Token already added");
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        lpToken.push(_lpToken);

        poolInfo.push(
            PoolInfo({
                allocPoint: allocPoint.to64(),
                lastRewardTime: block.timestamp.to64(),
                accMilkPerShare: 0
            })
        );
        addedTokens[address(_lpToken)] = true;
        emit LogPoolAddition(lpToken.length.sub(1), allocPoint, _lpToken);
    }

    /// @notice Update the given pool's milk allocation point and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool overwrite
    ) public onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint.to64();

        emit LogSetPool(_pid, _allocPoint, overwrite);
    }

    /// @notice Sets the milk per second to be distributed. Can only be called by the owner.
    /// @param _milkPerSecond The amount of milk to be distributed per second.
    function setMilkPerSEcond(uint256 _milkPerSecond) public onlyOwner {
        milkPerSecond = _milkPerSecond;
        emit LogMilkPerSecond(_milkPerSecond);
    }

    /// @notice Set the `migrator` contract. Can only be called by the owner.
    /// @param _migrator The contract address to set.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    /// @notice Migrate LP token to another LP contract through the `migrator` contract.
    /// @param _pid The index of the pool. See `poolInfo`.
    function migrate(uint256 _pid) public {
        require(
            address(migrator) != address(0),
            "MasterChefV2: no migrator set"
        );
        IERC20 _lpToken = lpToken[_pid];
        uint256 bal = _lpToken.balanceOf(address(this));
        _lpToken.approve(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(_lpToken);
        require(
            bal == newLpToken.balanceOf(address(this)),
            "MasterChefV2: migrated balance must match"
        );
        lpToken[_pid] = newLpToken;
    }

    /// @notice View function to see pending milk on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending milk reward for a given user.
    function pendingMilk(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending)
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMilkPerShare = pool.accMilkPerShare;
        uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 time = block.timestamp.sub(pool.lastRewardTime);
            uint256 milkReward = time.mul(milkPerSecond).mul(pool.allocPoint) /
                totalAllocPoint;
            accMilkPerShare = accMilkPerShare.add(
                milkReward.mul(ACC_MILK_PRECISION) / lpSupply
            );
        }
        pending = int256(user.amount.mul(accMilkPerShare) / ACC_MILK_PRECISION)
            .sub(user.rewardDebt)
            .toUInt256();
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 time = block.timestamp.sub(pool.lastRewardTime);
                uint256 milkReward = time.mul(milkPerSecond).mul(
                    pool.allocPoint
                ) / totalAllocPoint;
                pool.accMilkPerShare = pool.accMilkPerShare.add(
                    (milkReward.mul(ACC_MILK_PRECISION) / lpSupply).to128()
                );
            }
            pool.lastRewardTime = block.timestamp.to64();
            poolInfo[pid] = pool;
            emit LogUpdatePool(
                pid,
                pool.lastRewardTime,
                lpSupply,
                pool.accMilkPerShare
            );
        }
    }

    /// @notice Deposit LP tokens to MCV2 for milk allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][to];

        // Effects
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(
            int256(amount.mul(pool.accMilkPerShare) / ACC_MILK_PRECISION)
        );

        lpToken[pid].safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, pid, amount, to);
    }

    /// @notice Withdraw LP tokens from MCV2.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        // Effects
        user.rewardDebt = user.rewardDebt.sub(
            int256(amount.mul(pool.accMilkPerShare) / ACC_MILK_PRECISION)
        );
        user.amount = user.amount.sub(amount);

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of milk rewards.
    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedMilk = int256(
            user.amount.mul(pool.accMilkPerShare) / ACC_MILK_PRECISION
        );
        uint256 _pendingMilk = accumulatedMilk.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedMilk;

        // Interactions
        if (_pendingMilk != 0) {
            MILK.mint(to, _pendingMilk);
        }

        emit Harvest(msg.sender, pid, _pendingMilk);
    }

    /// @notice Withdraw LP tokens from MCV2 and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and milk rewards.
    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        int256 accumulatedMilk = int256(
            user.amount.mul(pool.accMilkPerShare) / ACC_MILK_PRECISION
        );
        uint256 _pendingMilk = accumulatedMilk.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedMilk.sub(
            int256(amount.mul(pool.accMilkPerShare) / ACC_MILK_PRECISION)
        );
        user.amount = user.amount.sub(amount);

        // Interactions
        MILK.mint(to, _pendingMilk);

        lpToken[pid].safeTransfer(to, amount);

        emit Withdraw(msg.sender, pid, amount, to);
        emit Harvest(msg.sender, pid, _pendingMilk);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        lpToken[pid].safeTransfer(to, amount);
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }
}

