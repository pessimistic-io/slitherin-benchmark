// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { SafeTransferLib } from "./SafeTransferLib.sol";
import { ERC20 } from "./ERC20.sol";
import { EnumerableSet } from "./EnumerableSet.sol";
import { GlobalACL, Auth } from "./Auth.sol";
import { MasterChefLib } from "./MasterChefLib.sol";
import { OARB } from "./oARB.sol";

interface IRewarder {
    function onOArbReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user) external view returns (uint256 pending);

    function rewardToken() external view returns (address);
}

// MasterChefUmami is a waifu. She says "onii chan, I'm gonna use timestamp instead".
// And to top it off, it takes no risks. Because the biggest risk is operator error.
// So we make it virtually impossible for the operator of this contract to cause a bug with people's harvests.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once OArb is sufficiently
// distributed and the community can show to govern itself.
contract MasterChefUmami is GlobalACL {
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
            //
            // We do some fancy math here. Basically, any point in time, the amount of OArb's
            // entitled to a user but is pending to be distributed is:
            //
            //   pending reward = (user.amount * pool.accOArbPerShare) - user.rewardDebt
            //
            // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
            //   1. The pool's `accOArbPerShare` (and `lastRewardTimestamp`) gets updated.
            //   2. User receives the pending reward sent to his/her address.
            //   3. User's `amount` gets updated.
            //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        ERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. OArb to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that OArb distribution occurs.
        uint256 accOArbPerShare; // Accumulated OArb per share, times 1e12. See below.
        IRewarder rewarder;
    }

    // The oARB TOKEN!
    OARB public oARB;
    // OArb tokens created per second.
    uint256 public oArbPerSec;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Set of all LP tokens that have been added as pools
    EnumerableSet.AddressSet private lpTokens;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when OArb mining starts.
    uint256 public startTimestamp;

    event Add(uint256 indexed pid, uint256 allocPoint, ERC20 indexed lpToken, IRewarder indexed rewarder);
    event Set(uint256 indexed pid, uint256 allocPoint, IRewarder indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accOArbPerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateEmissionRate(address indexed user, uint256 _oArbPerSec);

    constructor(OARB _oArb, Auth _auth, uint256 _oArbPerSec, uint256 _startTimestamp) GlobalACL(_auth) {
        oARB = _oArb;
        oArbPerSec = _oArbPerSec;
        startTimestamp = _startTimestamp;
        totalAllocPoint = 0;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function getPIdFromLP(address lp) external view returns (uint256) {
        for (uint256 index = 0; index < poolInfo.length; index++) {
            if (address(poolInfo[index].lpToken) == lp) {
                return index;
            }
        }
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, ERC20 _lpToken, IRewarder _rewarder) public onlyConfigurator {
        require(MasterChefLib.isContract(address(_lpToken)), "add: LP token must be a valid contract");
        require(
            MasterChefLib.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "add: rewarder must be contract or zero"
        );
        require(!lpTokens.contains(address(_lpToken)), "add: LP already added");
        massUpdatePools();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accOArbPerShare: 0,
                rewarder: _rewarder
            })
        );
        lpTokens.add(address(_lpToken));
        emit Add(poolInfo.length - 1, _allocPoint, _lpToken, _rewarder);
    }

    // Update the given pool's OArb allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, IRewarder _rewarder, bool overwrite) public onlyConfigurator {
        require(
            MasterChefLib.isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "set: rewarder must be contract or zero"
        );
        massUpdatePools();
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (overwrite) {
            poolInfo[_pid].rewarder = _rewarder;
        }
        emit Set(_pid, _allocPoint, overwrite ? _rewarder : poolInfo[_pid].rewarder, overwrite);
    }

    // View function to see pending OArb on frontend.
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingOArb,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        )
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accOArbPerShare = pool.accOArbPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
            uint256 oArbReward = (multiplier * oArbPerSec * pool.allocPoint) / totalAllocPoint;
            accOArbPerShare = accOArbPerShare + ((oArbReward * 1e12) / lpSupply);
        }
        pendingOArb = ((user.amount * accOArbPerShare) / 1e12) - user.rewardDebt;

        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            (bonusTokenAddress, bonusTokenSymbol) = rewarderBonusTokenInfo(_pid);
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    // Get bonus token info from the rewarder contract for a given pool, if it is a double reward farm
    function rewarderBonusTokenInfo(uint256 _pid)
        public
        view
        returns (address bonusTokenAddress, string memory bonusTokenSymbol)
    {
        PoolInfo storage pool = poolInfo[_pid];
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
            bonusTokenSymbol = ERC20(pool.rewarder.rewardToken()).symbol();
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
        uint256 oArbReward = (multiplier * oArbPerSec * pool.allocPoint) / totalAllocPoint;
        oARB.mint(address(this), oArbReward);
        pool.accOArbPerShare = pool.accOArbPerShare + ((oArbReward * 1e12) / lpSupply);
        pool.lastRewardTimestamp = block.timestamp;
        emit UpdatePool(_pid, pool.lastRewardTimestamp, lpSupply, pool.accOArbPerShare);
    }

    // Deposit LP tokens to MasterChef for OArb allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            // Harvest OArb
            uint256 pending = ((user.amount * pool.accOArbPerShare) / 1e12) - user.rewardDebt;
            safeOArbTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        user.amount = user.amount + _amount;
        user.rewardDebt = (user.amount * pool.accOArbPerShare) / 1e12;

        IRewarder rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onOArbReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: !_amount not available");

        updatePool(_pid);

        // Harvest OArb
        uint256 pending = ((user.amount * pool.accOArbPerShare) / 1e12) - user.rewardDebt;
        safeOArbTransfer(msg.sender, pending);
        emit Harvest(msg.sender, _pid, pending);

        user.amount = user.amount - _amount;
        user.rewardDebt = (user.amount * pool.accOArbPerShare) / 1e12;

        IRewarder rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onOArbReward(msg.sender, user.amount);
        }

        pool.lpToken.safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onOArbReward(msg.sender, 0);
        }

        // Note: transfer can fail or succeed if `amount` is zero.
        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe OArb transfer function, just in case if rounding error causes pool to not have enough OArb.
    function safeOArbTransfer(address _to, uint256 _amount) internal {
        uint256 oArbBal = oARB.balanceOf(address(this));
        if (_amount > oArbBal) {
            oARB.transfer(_to, oArbBal);
        } else {
            oARB.transfer(_to, _amount);
        }
    }

    // Pancake has to add hidden dummy pools inorder to alter the emission,
    // here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _oArbPerSec) public onlyConfigurator {
        massUpdatePools();
        oArbPerSec = _oArbPerSec;
        emit UpdateEmissionRate(msg.sender, _oArbPerSec);
    }

    // collects all pending rewards
    function collectAllPoolRewards() public {
        for (uint256 _pid = 0; _pid < poolInfo.length; _pid++) {
            updatePool(_pid);
            PoolInfo memory pool = poolInfo[_pid];
            UserInfo storage user = userInfo[_pid][msg.sender];

            if (user.amount > 0) {
                // Harvest OArb
                uint256 pending = ((user.amount * pool.accOArbPerShare) / 1e12) - user.rewardDebt;
                safeOArbTransfer(msg.sender, pending);
                emit Harvest(msg.sender, _pid, pending);
            }
            user.rewardDebt = (user.amount * pool.accOArbPerShare) / 1e12;
            IRewarder rewarder = poolInfo[_pid].rewarder;
            if (address(rewarder) != address(0)) {
                rewarder.onOArbReward(msg.sender, user.amount);
            }
        }
    }
}

