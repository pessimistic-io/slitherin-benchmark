// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IERC20BurnableMinter.sol";
import "./IStakePool.sol";
import "./IBank.sol";
import "./Initializer.sol";
import "./DelegateGuard.sol";

// The stakepool will mint prChaos according to the total supply of Chaos and
// then distribute it to all users according to the amount of Chaos deposited by each user.
contract StakePool is Ownable, Initializer, DelegateGuard, IStakePool {
    using SafeERC20 for IERC20;

    // The Chaos token
    IERC20 public override Chaos;
    // The prChaos token
    IERC20BurnableMinter public override prChaos;
    // The bank contract
    IBank public override bank;
    // Info of each pool.
    PoolInfo[] public override poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public override userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public override totalAllocPoint = 0;

    // Withdraw duration.
    uint256 public override duration;
    // Daily minted Chaos as a percentage of Chaos total supply.
    uint32 public override mintPercentPerDay = 0;
    // How many blocks are there in a day.
    uint256 public override blocksPerDay = 0;

    // Developer address.
    address public override dev;
    // Withdraw fee(Chaos).
    uint32 public override withdrawFee = 0;
    // Mint fee(prChaos).
    uint32 public override mintFee = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 fee
    );

    event OptionsChanged(
        uint32 mintPercentPerDay,
        uint256 blocksPerDay,
        address dev,
        uint32 withdrawFee,
        uint32 mintFee
    );

    // Constructor.
    function constructor1(
        IERC20 _Chaos,
        IERC20BurnableMinter _prChaos,
        IBank _bank,
        address _owner
    ) external override isDelegateCall isUninitialized {
        Chaos = _Chaos;
        prChaos = _prChaos;
        bank = _bank;
        _transferOwnership(_owner);
    }

    function poolLength() external view override returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) external override isInitialized onlyOwner {
        // when _pid is 0, it is Chaos pool
        if (poolInfo.length == 0) {
            require(
                address(_lpToken) == address(Chaos),
                "StakePool: invalid lp token"
            );
        }

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: block.number,
                accPerShare: 0
            })
        );
    }

    // Update the given pool's prChaos allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external override isInitialized onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint =
            totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set options. Can only be called by the owner.
    function setOptions(
        uint256 _duration,
        uint32 _mintPercentPerDay,
        uint256 _blocksPerDay,
        address _dev,
        uint32 _withdrawFee,
        uint32 _mintFee,
        bool _withUpdate
    ) public override onlyOwner {
        require(
            _mintPercentPerDay <= 10000,
            "StakePool: mintPercentPerDay is too large"
        );
        require(_blocksPerDay > 0, "StakePool: blocksPerDay is zero");
        require(_dev != address(0), "StakePool: zero dev address");
        require(_withdrawFee <= 10000, "StakePool: invalid withdrawFee");
        require(_mintFee <= 10000, "StakePool: invalid mintFee");
        if (_withUpdate) {
            massUpdatePools();
        }
        duration = _duration;
        mintPercentPerDay = _mintPercentPerDay;
        blocksPerDay = _blocksPerDay;
        dev = _dev;
        withdrawFee = _withdrawFee;
        mintFee = _mintFee;
        emit OptionsChanged(
            _mintPercentPerDay,
            _blocksPerDay,
            _dev,
            _withdrawFee,
            _mintFee
        );
    }

    // View function to see pending prChaoss on frontend.
    function pendingRewards(uint256 _pid, address _user)
        external
        view
        override
        isInitialized
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPerShare = pool.accPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 pendingReward = (Chaos.totalSupply() *
                1e12 *
                mintPercentPerDay *
                (block.number - pool.lastRewardBlock) *
                pool.allocPoint) / (10000 * blocksPerDay * totalAllocPoint);
            accPerShare += pendingReward / lpSupply;
        }
        return (user.amount * accPerShare) / 1e12 - user.rewardDebt;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public override isInitialized {
        uint256 totalSupply = Chaos.totalSupply();
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid, totalSupply);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid, uint256 _totalSupply) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || totalAllocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 pendingReward = (_totalSupply *
            1e12 *
            mintPercentPerDay *
            (block.number - pool.lastRewardBlock) *
            pool.allocPoint) / (10000 * blocksPerDay * totalAllocPoint);
        uint256 mint = pendingReward / 1e12;
        prChaos.mint(dev, (mint * mintFee) / 10000);
        prChaos.mint(address(this), mint);
        pool.accPerShare += pendingReward / lpSupply;
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to StakePool for prChaos allocation.
    function deposit(uint256 _pid, uint256 _amount)
        external
        override
        isInitialized
    {
        depositFor(_pid, _amount, msg.sender);
    }

    // Deposit LP tokens to StakePool for user for prChaos allocation.
    function depositFor(
        uint256 _pid,
        uint256 _amount,
        address _user
    ) public override isInitialized {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        updatePool(_pid, Chaos.totalSupply());
        if (user.amount > 0) {
            uint256 pending = (user.amount * pool.accPerShare) /
                1e12 -
                user.rewardDebt;
            if (pending > 0) {
                safeTransfer(_user, pending);
            }
        }
        pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        user.amount = user.amount + _amount;
        user.timestamp = block.timestamp;
        user.rewardDebt = (user.amount * pool.accPerShare) / 1e12;
        emit Deposit(_user, _pid, _amount);
    }

    // Withdraw LP tokens from StakePool.
    function withdraw(uint256 _pid, uint256 _amount)
        external
        override
        isInitialized
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            user.amount >= _amount &&
                block.timestamp >= user.timestamp + duration,
            "StakePool: withdraw not good"
        );
        updatePool(_pid, Chaos.totalSupply());
        uint256 pending = (user.amount * pool.accPerShare) /
            1e12 -
            user.rewardDebt;
        if (pending > 0) {
            safeTransfer(msg.sender, pending);
        }

        // when _pid is 0, it is Chaos pool,
        // so we have to check the amount that can be withdrawn,
        // and calculate dev fee
        uint256 fee = 0;
        if (_pid == 0) {
            uint256 withdrawable = bank.withdrawable(msg.sender, user.amount);
            require(
                withdrawable >= _amount,
                "StakePool: amount exceeds withdrawable"
            );
            fee = (_amount * withdrawFee) / 10000;
        }

        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * pool.accPerShare) / 1e12;
        pool.lpToken.safeTransfer(msg.sender, _amount - fee);
        pool.lpToken.safeTransfer(dev, fee);
        emit Withdraw(msg.sender, _pid, _amount - fee, fee);
    }

    // Claim reward.
    function claim(uint256 _pid) external override isInitialized {
        claimFor(_pid, msg.sender);
    }

    // Claim reward for user.
    function claimFor(uint256 _pid, address _user)
        public
        override
        isInitialized
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount > 0, "StakePool: claim not good");
        updatePool(_pid, Chaos.totalSupply());
        uint256 pending = (user.amount * pool.accPerShare) /
            1e12 -
            user.rewardDebt;
        if (pending > 0) {
            safeTransfer(_user, pending);
            user.rewardDebt = (user.amount * pool.accPerShare) / 1e12;
        }
    }

    // Safe prChaos transfer function, just in case if rounding error causes pool to not have enough prChaoss.
    function safeTransfer(address _to, uint256 _amount) internal {
        uint256 prChaosBal = prChaos.balanceOf(address(this));
        if (_amount > prChaosBal) {
            prChaos.transfer(_to, prChaosBal);
        } else {
            prChaos.transfer(_to, _amount);
        }
    }
}

