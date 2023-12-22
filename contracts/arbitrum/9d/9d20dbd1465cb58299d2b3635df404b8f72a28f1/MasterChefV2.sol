// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./Token.sol";

interface ArbSys {
    function arbBlockNumber() external view returns (uint);
}

// MasterChef is the master of Chibi. He can make Chibi and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once CHIBI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefV2 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of CHIBIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accChibiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accChibiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. CHIBIs to distribute per block.
        uint256 lastRewardBlock; // Last block number that CHIBIs distribution occurs.
        uint256 accChibiPerShare; // Accumulated CHIBIs per share, times 1e12. See below.
    }
    // The CHIBI TOKEN!
    Chibi public chibi;
    // Dev address.
    address public devaddr;
    // Rewarder contract address.
    address public rewarder;
    // CHIBI tokens created per block.
    uint256 public chibiPerBlock = 1 ether;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when CHIBI mining starts.
    uint256 public startBlock;
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        Chibi _chibi,
        address _devaddr,
        address _rewarder
    ) public {
        chibi = _chibi;
        devaddr = _devaddr;
        startBlock = uint256(-1);
        rewarder = _rewarder;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            ArbSys(address(100)).arbBlockNumber() > startBlock ? ArbSys(address(100)).arbBlockNumber() : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accChibiPerShare: 0
            })
        );
    }

    // Update the given pool's CHIBI allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // View function to see pending CHIBIs on frontend.
    function pendingChibi(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accChibiPerShare = pool.accChibiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (ArbSys(address(100)).arbBlockNumber() > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, ArbSys(address(100)).arbBlockNumber());
            uint256 chibiReward =
                multiplier.mul(chibiPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accChibiPerShare = accChibiPerShare.add(
                chibiReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accChibiPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (ArbSys(address(100)).arbBlockNumber() <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = ArbSys(address(100)).arbBlockNumber();
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, ArbSys(address(100)).arbBlockNumber());
        uint256 chibiReward =
            multiplier.mul(chibiPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
        pool.accChibiPerShare = pool.accChibiPerShare.add(
            chibiReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = ArbSys(address(100)).arbBlockNumber();
    }

    // Deposit LP tokens to MasterChef for CHIBI allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accChibiPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            safeChibiTransfer(msg.sender, pending);
        }
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(pool.accChibiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending =
            user.amount.mul(pool.accChibiPerShare).div(1e12).sub(
                user.rewardDebt
            );
        safeChibiTransfer(msg.sender, pending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accChibiPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe chibi transfer function, just in case if rounding error causes pool to not have enough CHIBIs.
    function safeChibiTransfer(address _to, uint256 _amount) internal {
        uint256 chibiBal = chibi.balanceOf(address(rewarder));
        if (_amount > chibiBal) {
            chibi.transferFrom(rewarder, _to, chibiBal);
        } else {
            chibi.transferFrom(rewarder, _to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function updateEmissionRate(uint256 _chibiPerBlock) external onlyOwner {
        massUpdatePools();
        chibiPerBlock = _chibiPerBlock;
    }

    function updateStartBlock(uint256 _startBlock) external onlyOwner {
        require(ArbSys(address(100)).arbBlockNumber() < startBlock, "Farm already started");
        require(ArbSys(address(100)).arbBlockNumber() < _startBlock, "Cannot set startBlock in the past");

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = _startBlock;
        }

        startBlock = _startBlock;
    }
}
