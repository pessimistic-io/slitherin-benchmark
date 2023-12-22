// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";
import "./IMultipleRewards.sol";
import "./BoringERC20.sol";
import "./IZyberPair.sol";
import "./IEscrowMaster.sol";

contract YieldGeniusDistributor is Ownable, ReentrancyGuard {
    using BoringERC20 for IBoringERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
        uint256 lastRewardTimestamp;
    }

    // Info of each pool.
    struct PoolInfo {
        /**
         *@notice Address of LP token contract.
         */
        IBoringERC20 lpToken;
        /**
         *@notice How many allocation points assigned to this pool. Yieldgenius to distribute per block.
         */
        uint256 allocPoint;
        /**
         *@notice Last block number that Yieldgenius distribution occurs.
         */
        uint256 lastRewardTimestamp;
        /**
         *@notice Accumulated Yieldgenius per share, times 1e18. See below.
         */
        uint256 accYieldgeniusPerShare;
        /**
         *@notice Deposit fee in basis points
         */
        uint16 depositFeeBP;
        /**
         *@notice Harvest interval in seconds
         */
        uint256 harvestInterval;
        /**
         *@notice Total token in Pool
         */
        uint256 totalLp;
        /**
         *@notice Array of rewarder contract for pools with incentives
         */
        IMultipleRewards[] rewarders;
    }

    IBoringERC20 public yieldgenius;
    /**
     * @notice Yieldgenius tokens created per second
     */
    uint256 public yieldgeniusPerSec;

    /**
     * @notice Max harvest interval: 60 days
     */
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 70 days;

    /**
     * @notice Maximum deposit fee rate: 10%
     */
    uint16 public constant MAXIMUM_DEPOSIT_FEE_RATE = 1000;

    /**
     * @notice Maximum emission rate
     */
    uint256 public constant MAXIMUM_EMISSION_RATE = 10 ether;

    /**
     *@notice Info of each pool
     */
    PoolInfo[] public poolInfo;

    /**
     *@notice Info of each user that stakes LP tokens.
     */
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /**
     *@notice Total allocation points. Must be the sum of all allocation points in all pools.
     */
    uint256 public totalAllocPoint;

    /**
     *@notice The timestamp when Yieldgenius mining starts.
     */
    uint256 public startTimestamp;

    /**
     *@notice Total locked up rewards
     */
    uint256 public totalLockedUpRewards;

    /**
     *@notice Total Yieldgenius in Yieldgenius Pools (can be multiple pools)
     */
    uint256 public totalYieldgeniusInPools;

    /**
     *@notice marketing address.
     */
    address public marketingAddress;

    /**
     *@notice Fee address if needed
     */
    address public feeAddress;

    /**
     *@notice Percentage of pool rewards that goto the team.
     */
    uint256 public marketingPercent;

    /**
     *@notice vested rewards contract
     */
    IEscrowMaster public rewardMinter;

    /**
     *@notice The precision factor
     */
    uint256 internal constant ACC_TOKEN_PRECISION = 1e12;

    /**
     *@notice Pool validation by pid
     */
    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "Pool does not exist");
        _;
    }

    event Add(
        uint256 indexed pid,
        uint256 allocPoint,
        IBoringERC20 indexed lpToken,
        uint16 depositFeeBP,
        uint256 harvestInterval,
        IMultipleRewards[] indexed rewarders
    );

    event Set(
        uint256 indexed pid,
        uint256 allocPoint,
        uint16 depositFeeBP,
        uint256 harvestInterval,
        IMultipleRewards[] indexed rewarders
    );

    event UpdatePool(
        uint256 indexed pid,
        uint256 lastRewardTimestamp,
        uint256 lpSupply,
        uint256 accYieldgeniusPerShare
    );

    event RewardSent(uint256 indexed pid, uint256 amount, address indexed user);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    event EmissionRateUpdated(
        address indexed caller,
        uint256 previousValue,
        uint256 newValue
    );

    event RewardLockedUp(
        address indexed user,
        uint256 indexed pid,
        uint256 amountLockedUp
    );

    event AllocPointsUpdated(
        address indexed caller,
        uint256 previousAmount,
        uint256 newAmount
    );

    event SetMarketingAddress(
        address indexed oldAddress,
        address indexed newAddress
    );

    event SetFeeAddress(address indexed oldAddress, address indexed newAddress);

    event SetInvestorAddress(
        address indexed oldAddress,
        address indexed newAddress
    );

    event SetMarketingPercent(uint256 oldPercent, uint256 newPercent);

    event SetTreasuryPercent(uint256 oldPercent, uint256 newPercent);

    event SetInvestorPercent(uint256 oldPercent, uint256 newPercent);

    constructor(
        IBoringERC20 _yieldgenius,
        uint256 _yieldgeniusPerSec,
        address _marketingAddress,
        uint256 _marketingPercent,
        address _feeAddress,
        IEscrowMaster _rewardMinter
    ) {
        require(
            _marketingPercent <= 100,
            "constructor: invalid marketing percent value"
        );

        startTimestamp = block.timestamp + (60 * 60 * 24 * 365);

        yieldgenius = _yieldgenius;
        yieldgeniusPerSec = _yieldgeniusPerSec;
        marketingAddress = _marketingAddress;
        marketingPercent = _marketingPercent;
        feeAddress = _feeAddress;
        rewardMinter = _rewardMinter;
    }

    /**
     *@notice Set farming start, can call only once
     */
    function startFarming() public onlyOwner {
        require(block.timestamp < startTimestamp, "farm already started");

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardTimestamp = block.timestamp;
        }

        startTimestamp = block.timestamp;
    }

    /**
     *@return uint256 Pool length
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     *@notice Add a new lp to the pool. Can only be called by the owner.
     *@notice Can add multiple pool with same lp token without messing up rewards, because each pool's balance is tracked using its own totalLp
     *@param _allocPoint allocation point
     *@param _lpToken LP token
     *@param _depositFeeBP deposit fee
     *@param _harvestInterval harvest interval
     */
    function add(
        uint256 _allocPoint,
        IBoringERC20 _lpToken,
        uint16 _depositFeeBP,
        uint256 _harvestInterval,
        IMultipleRewards[] calldata _rewarders
    ) public onlyOwner {
        require(_rewarders.length <= 10, "add: too many rewarders");
        require(
            _depositFeeBP <= MAXIMUM_DEPOSIT_FEE_RATE,
            "add: deposit fee too high"
        );
        require(
            _harvestInterval <= MAXIMUM_HARVEST_INTERVAL,
            "add: invalid harvest interval"
        );
        for (
            uint256 rewarderId = 0;
            rewarderId < _rewarders.length;
            ++rewarderId
        ) {
            require(
                Address.isContract(address(_rewarders[rewarderId])),
                "add: rewarder must be contract"
            );
        }

        _massUpdatePools();

        uint256 lastRewardTimestamp = block.timestamp > startTimestamp
            ? block.timestamp
            : startTimestamp;

        totalAllocPoint += _allocPoint;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accYieldgeniusPerShare: 0,
                depositFeeBP: _depositFeeBP,
                harvestInterval: _harvestInterval,
                totalLp: 0,
                rewarders: _rewarders
            })
        );

        emit Add(
            poolInfo.length - 1,
            _allocPoint,
            _lpToken,
            _depositFeeBP,
            _harvestInterval,
            _rewarders
        );
    }

    /**
     *@notice Update the given pool's Yieldgenius allocation point and deposit fee. Can only be called by the owner.
     *@param _pid pool id number
     *@param _allocPoint allocation point
     *@param _depositFeeBP deposit fee
     *@param _harvestInterval harvest interval
     */
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint256 _harvestInterval,
        IMultipleRewards[] calldata _rewarders
    ) public onlyOwner validatePoolByPid(_pid) {
        require(_rewarders.length <= 10, "set: too many rewarders");

        require(
            _depositFeeBP <= MAXIMUM_DEPOSIT_FEE_RATE,
            "set: deposit fee too high"
        );
        require(
            _harvestInterval <= MAXIMUM_HARVEST_INTERVAL,
            "set: invalid harvest interval"
        );

        for (
            uint256 rewarderId = 0;
            rewarderId < _rewarders.length;
            ++rewarderId
        ) {
            require(
                Address.isContract(address(_rewarders[rewarderId])),
                "set: rewarder must be contract"
            );
        }

        _massUpdatePools();

        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;

        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
        poolInfo[_pid].rewarders = _rewarders;

        emit Set(
            _pid,
            _allocPoint,
            _depositFeeBP,
            _harvestInterval,
            _rewarders
        );
    }

    /**
     *@notice View function to see pending rewards on frontend.
     *@param _pid pool id number
     *@param _user user address
     *@return addresses pool reward adddress
     *@return symbols symbols
     *@return decimals number of decimals
     *@return amounts reward amounts
     */
    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        validatePoolByPid(_pid)
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory amounts
        )
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accYieldgeniusPerShare = pool.accYieldgeniusPerShare;
        uint256 lpSupply = pool.totalLp;

        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
            uint256 total = 1000;
            uint256 lpPercent = total - marketingPercent;

            uint256 yieldgeniusReward = (multiplier *
                yieldgeniusPerSec *
                pool.allocPoint *
                lpPercent) /
                totalAllocPoint /
                total;

            accYieldgeniusPerShare += (
                ((yieldgeniusReward * ACC_TOKEN_PRECISION) / lpSupply)
            );
        }

        uint256 pendingYieldgenius = (((user.amount * accYieldgeniusPerShare) /
            ACC_TOKEN_PRECISION) - user.rewardDebt) + user.rewardLockedUp;

        addresses = new address[](pool.rewarders.length + 1);
        symbols = new string[](pool.rewarders.length + 1);
        amounts = new uint256[](pool.rewarders.length + 1);
        decimals = new uint256[](pool.rewarders.length + 1);

        addresses[0] = address(yieldgenius);
        symbols[0] = IBoringERC20(yieldgenius).safeSymbol();
        decimals[0] = IBoringERC20(yieldgenius).safeDecimals();
        amounts[0] = pendingYieldgenius;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            addresses[rewarderId + 1] = address(
                pool.rewarders[rewarderId].rewardToken()
            );

            symbols[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeSymbol();

            decimals[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeDecimals();

            amounts[rewarderId + 1] = pool.rewarders[rewarderId].pendingTokens(
                _pid,
                _user
            );
        }
    }

    /**
     *@notice View function to see pool rewards per sec
     *@param _pid pool id number
     *@return addresses pool reward adddress
     *@return symbols symbols
     *@return decimals number of decimals
     *@return rewardsPerSec rewards per second
     */
    function poolRewardsPerSec(
        uint256 _pid
    )
        external
        view
        validatePoolByPid(_pid)
        returns (
            address[] memory addresses,
            string[] memory symbols,
            uint256[] memory decimals,
            uint256[] memory rewardsPerSec
        )
    {
        PoolInfo storage pool = poolInfo[_pid];

        addresses = new address[](pool.rewarders.length + 1);
        symbols = new string[](pool.rewarders.length + 1);
        decimals = new uint256[](pool.rewarders.length + 1);
        rewardsPerSec = new uint256[](pool.rewarders.length + 1);

        addresses[0] = address(yieldgenius);
        symbols[0] = IBoringERC20(yieldgenius).safeSymbol();
        decimals[0] = IBoringERC20(yieldgenius).safeDecimals();

        uint256 total = 1000;
        uint256 lpPercent = total - marketingPercent;

        rewardsPerSec[0] =
            (pool.allocPoint * yieldgeniusPerSec * lpPercent) /
            totalAllocPoint /
            total;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            addresses[rewarderId + 1] = address(
                pool.rewarders[rewarderId].rewardToken()
            );

            symbols[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeSymbol();

            decimals[rewarderId + 1] = IBoringERC20(
                pool.rewarders[rewarderId].rewardToken()
            ).safeDecimals();

            rewardsPerSec[rewarderId + 1] = pool
                .rewarders[rewarderId]
                .poolRewardsPerSec(_pid);
        }
    }

    /**
     *@notice View function to see rewarders for a pool
     *@param _pid pool id number
     *@return rewarders rewarders addresses
     */
    function poolRewarders(
        uint256 _pid
    )
        external
        view
        validatePoolByPid(_pid)
        returns (address[] memory rewarders)
    {
        PoolInfo storage pool = poolInfo[_pid];
        rewarders = new address[](pool.rewarders.length);
        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            rewarders[rewarderId] = address(pool.rewarders[rewarderId]);
        }
    }

    /**
     *@notice View function to see if user can harvest Yieldgenius.
     *@param _pid pool id number
     *@param _pid user address
     *@return bool can harvest true/false
     */
    function canHarvest(
        uint256 _pid,
        address _user
    ) public view validatePoolByPid(_pid) returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return
            block.timestamp >= startTimestamp &&
            block.timestamp >= user.nextHarvestUntil;
    }

    /**
     *@notice Update reward vairables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() external nonReentrant {
        _massUpdatePools();
    }

    /**
     *@notice Internal method for massUpdatePools
     */
    function _massUpdatePools() internal {
        for (uint256 pid = 0; pid < poolInfo.length; ++pid) {
            _updatePool(pid);
        }
    }

    /**
     *@notice Update reward variables of the given pool to be up-to-date.
     *@param _pid pool id number
     */
    function updatePool(uint256 _pid) external nonReentrant {
        _updatePool(_pid);
    }

    /**
     *@notice Internal method for _updatePool
     *@param _pid pool id number
     */
    function _updatePool(uint256 _pid) internal validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];

        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }

        uint256 lpSupply = pool.totalLp;

        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;

        uint256 yieldgeniusReward = ((multiplier * yieldgeniusPerSec) *
            pool.allocPoint) / totalAllocPoint;

        uint256 total = 1000;
        uint256 lpPercent = total - marketingPercent;

        if (marketingPercent > 0) {
            yieldgenius.mint(
                marketingAddress,
                (yieldgeniusReward * marketingPercent) / total
            );
        }

        // yieldgenius.mint(address(this), (yieldgeniusReward * lpPercent) / total);

        pool.accYieldgeniusPerShare +=
            (yieldgeniusReward * ACC_TOKEN_PRECISION * lpPercent) /
            pool.totalLp /
            total;

        pool.lastRewardTimestamp = block.timestamp;

        emit UpdatePool(
            _pid,
            pool.lastRewardTimestamp,
            lpSupply,
            pool.accYieldgeniusPerShare
        );
    }

    /**
     *@notice Internal method for depositing with permit
     *@param pid pool id number
     *@param amount deposit amount
     *@param deadline deposit deadline
     *@param v v
     *@param r r
     *@param s s
     */
    function depositWithPermit(
        uint256 pid,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public nonReentrant validatePoolByPid(pid) {
        PoolInfo storage pool = poolInfo[pid];
        IZyberPair pair = IZyberPair(address(pool.lpToken));
        pair.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(pid, amount);
    }

    /**
     *@notice Deposit tokens for Yieldgenius allocation.
     *@param _pid pool id number
     *@param _amount deposit amount
     */
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        _deposit(_pid, _amount);
    }

    /**
     *@notice Deposit tokens for Yieldgenius allocation.
     *@param _pid pool id number
     *@param _amount deposit amount
     */
    function _deposit(
        uint256 _pid,
        uint256 _amount
    ) internal validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        _updatePool(_pid);

        payOrLockupPendingYieldgenius(_pid);

        if (_amount > 0) {
            uint256 beforeDeposit = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 afterDeposit = pool.lpToken.balanceOf(address(this));

            _amount = afterDeposit - beforeDeposit;

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (_amount * pool.depositFeeBP) / 10000;
                pool.lpToken.safeTransfer(feeAddress, depositFee);

                _amount = _amount - depositFee;
            }

            user.amount += _amount;

            if (address(pool.lpToken) == address(yieldgenius)) {
                totalYieldgeniusInPools += _amount;
            }
        }
        user.rewardDebt =
            (user.amount * pool.accYieldgeniusPerShare) /
            ACC_TOKEN_PRECISION;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            pool.rewarders[rewarderId].onYGReward(
                _pid,
                msg.sender,
                user.amount
            );
        }

        if (_amount > 0) {
            pool.totalLp += _amount;
        }

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     *@notice withdraw tokens
     *@param _pid pool id number
     *@param _amount deposit amount
     */
    function withdraw(
        uint256 _pid,
        uint256 _amount
    ) public nonReentrant validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        //this will make sure that user can only withdraw from his pool
        require(user.amount >= _amount, "withdraw: user amount not enough");

        //cannot withdraw more than pool's balance
        require(pool.totalLp >= _amount, "withdraw: pool total not enough");

        _updatePool(_pid);

        payOrLockupPendingYieldgenius(_pid);

        if (_amount > 0) {
            user.amount -= _amount;
            if (address(pool.lpToken) == address(yieldgenius)) {
                totalYieldgeniusInPools -= _amount;
            }
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }

        user.rewardDebt =
            (user.amount * pool.accYieldgeniusPerShare) /
            ACC_TOKEN_PRECISION;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            pool.rewarders[rewarderId].onYGReward(
                _pid,
                msg.sender,
                user.amount
            );
        }

        if (_amount > 0) {
            pool.totalLp -= _amount;
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /**
     *@notice Withdraw without caring about rewards. EMERGENCY ONLY.
     *@param _pid pool id number
     */
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;

        //Cannot withdraw more than pool's balance
        require(
            pool.totalLp >= amount,
            "emergency withdraw: pool total not enough"
        );

        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
        pool.totalLp -= amount;

        for (
            uint256 rewarderId = 0;
            rewarderId < pool.rewarders.length;
            ++rewarderId
        ) {
            pool.rewarders[rewarderId].onYGReward(_pid, msg.sender, 0);
        }

        if (address(pool.lpToken) == address(yieldgenius)) {
            totalYieldgeniusInPools -= amount;
        }

        pool.lpToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /**
     *@notice Pay or lockup pending Yieldgenius.
     *@param _pid pool id number
     */
    function payOrLockupPendingYieldgenius(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.nextHarvestUntil == 0 && block.timestamp >= startTimestamp) {
            user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
        }

        if (user.nextHarvestUntil != 0 && pool.harvestInterval == 0) {
            user.nextHarvestUntil = 0;
        }

        uint256 pending = ((user.amount * pool.accYieldgeniusPerShare) /
            ACC_TOKEN_PRECISION) - user.rewardDebt;

        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                pending = pending + user.rewardLockedUp;
                uint256 locked;
                // reset lockup
                totalLockedUpRewards -= user.rewardLockedUp;
                user.rewardLockedUp = 0;
                user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
                if (pending > 0) {
                    locked =
                        (pending / (rewardMinter.LOCKEDPERIODAMOUNT() + 1)) *
                        rewardMinter.LOCKEDPERIODAMOUNT();

                    yieldgenius.mint(msg.sender, pending - locked);
                    emit RewardSent(_pid, pending - locked, msg.sender);
                    if (locked > 0) {
                        yieldgenius.mint(address(rewardMinter), locked);
                        rewardMinter.lock(msg.sender, locked);
                    }

                    user.lastRewardTimestamp = block.timestamp;
                }
            }
        } else if (pending > 0) {
            totalLockedUpRewards += pending;
            user.rewardLockedUp += pending;
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    /**
     *@notice Safe Yieldgenius transfer function, just in case if rounding error causes pool do not have enough Yieldgenius.
     *@param _to address to
     *@param _amount transfer amount
     */
    function safeYieldgeniusTransfer(address _to, uint256 _amount) internal {
        if (yieldgenius.balanceOf(address(this)) > totalYieldgeniusInPools) {
            /**
             *@notice YieldgeniusBal = total Yieldgenius in YieldgeniusChef - total Yieldgenius in Yieldgenius pools,
             *@notice this will make sure that YieldgeniusDistributor never transfer rewards from deposited Yieldgenius pools
             */
            uint256 yieldgeniusBal = yieldgenius.balanceOf(address(this)) -
                totalYieldgeniusInPools;
            if (_amount >= yieldgeniusBal) {
                yieldgenius.safeTransfer(_to, yieldgeniusBal);
            } else if (_amount > 0) {
                yieldgenius.safeTransfer(_to, _amount);
            }
        }
    }

    /**
     *@notice Update emission rate.
     *@param _yieldgeniusPerSec new emission rate per sec
     */
    function updateEmissionRate(uint256 _yieldgeniusPerSec) public onlyOwner {
        require(_yieldgeniusPerSec <= MAXIMUM_EMISSION_RATE, "too high");
        _massUpdatePools();

        emit EmissionRateUpdated(
            msg.sender,
            yieldgeniusPerSec,
            _yieldgeniusPerSec
        );

        yieldgeniusPerSec = _yieldgeniusPerSec;
    }

    /**
     *@notice Update allocation point.
     *@param _pid pool id number
     *@param _allocPoint allocation point
     */
    function updateAllocPoint(
        uint256 _pid,
        uint256 _allocPoint
    ) public onlyOwner {
        _massUpdatePools();

        emit AllocPointsUpdated(
            msg.sender,
            poolInfo[_pid].allocPoint,
            _allocPoint
        );

        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /**
     * @notice Returns pools total amount of LP tokens
     * @param pid pool id number
     * @return uint256 The amount of pools total LP tokens
     */
    function poolTotalLp(uint256 pid) external view returns (uint256) {
        return poolInfo[pid].totalLp;
    }

    /**
     *@notice Function to harvest many pools in a single transaction
     *@param _pids pool id numbers
     */
    function harvestMany(uint256[] calldata _pids) public nonReentrant {
        require(_pids.length <= 30, "harvest many: too many pool ids");
        for (uint256 index = 0; index < _pids.length; ++index) {
            _deposit(_pids[index], 0);
        }
    }

    /**
     * @notice Sets Marketing address
     * @param _marketingAddress The address for marketing
     */
    function setMarketingAddress(address _marketingAddress) public onlyOwner {
        require(
            _marketingAddress != address(0),
            "invalid new marketing address"
        );
        marketingAddress = _marketingAddress;
        emit SetMarketingAddress(msg.sender, _marketingAddress);
    }

    /**
     *@notice Sets marketing percents
     *@param _newMarketingPercent Marketing percent
     */
    function setMarketingPercent(
        uint256 _newMarketingPercent
    ) public onlyOwner {
        require(_newMarketingPercent <= 100, "invalid percent value");
        emit SetMarketingPercent(marketingPercent, _newMarketingPercent);
        marketingPercent = _newMarketingPercent;
    }

    /**
     *@notice Update fee address.
     *@param _feeAddress Fee address
     */
    function setFeeAddress(address _feeAddress) public onlyOwner {
        require(_feeAddress != address(0), "invalid new fee address");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    /**
     *@notice Get Yiel Genius tokens created per second
     *@return uint256 Yiel Genius tokens per second
     */
    function getYieldgeniusPerSec() public view returns (uint256) {
        return yieldgeniusPerSec;
    }

    /**
     *@notice changes the reward locker
     *@param _locker new locker address
     */
    function changeRewardLocker(IEscrowMaster _locker) external onlyOwner {
        rewardMinter = _locker;
    }
}

