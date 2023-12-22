// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./SafeMath.sol";
import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "./Ownable.sol";
import "./Gauge.sol";
import "./ShieldToken.sol";

// MasterChef is the master of Shield. He can make Shield and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SHIELD is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Shields
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accShieldPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accShieldPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. HIGHs to distribute per block.
        uint256 lastRewardBlock; // Last block number that HIGHs distribution occurs.
        uint256 accShieldPerShare; // Accumulated HIGHs per share, times 1e12. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
        Gauge gauge;
    }

    // The SHIELD TOKEN!
    ShieldToken public shield;
    // Dev address.
    address public devaddr;
    // SHIELD tokens created per block.
    uint256 public shieldPerBlock;
    // Bonus muliplier for early shield makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;
    // XCAL rewards token address
    address public constant XCALaddress = 0xd2568acCD10A4C98e87c44E9920360031ad89fCB;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SHIELD mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    constructor(
        ShieldToken _shield,
        address _devaddr,
        address _feeAddress,
        uint256 _shieldPerBlock,
        uint256 _startBlock
    ) public {
        shield = _shield;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        shieldPerBlock = _shieldPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IBEP20 _lpToken,
        Gauge _gauge,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) public onlyOwner {
        require(
            _depositFeeBP <= 10000,
            "add: invalid deposit fee basis points"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accShieldPerShare: 0,
                depositFeeBP: _depositFeeBP,
                gauge: _gauge
            })
        );
    }

    // Update the given pool's SHIELD allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool _withUpdate
    ) public onlyOwner {
        require(
            _depositFeeBP <= 10000,
            "set: invalid deposit fee basis points"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    function claimLPTradingFees(uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.gauge.claimFees();
    }

    function getReward(
        uint256 _pid,
        address account,
        address[] memory tokens
    ) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.gauge.getReward(account, tokens);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending HIGHs on frontend.
    function pendingShield(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accShieldPerShare = pool.accShieldPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(pool.gauge));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 shieldReward = multiplier
                .mul(shieldPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accShieldPerShare = accShieldPerShare.add(
                shieldReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accShieldPerShare).div(1e12).sub(user.rewardDebt);
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
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(pool.gauge));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 shieldReward = multiplier
            .mul(shieldPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        shield.mint(devaddr, shieldReward.div(10));
        shield.mint(address(this), shieldReward);
        pool.accShieldPerShare = pool.accShieldPerShare.add(
            shieldReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for SHIELD allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accShieldPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeShieldTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accShieldPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function depositGauge(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (_amount > 0) {
            if (_pid > 0) {
                if (pool.depositFeeBP > 0) {
                    uint256 depositFee = _amount.mul(pool.depositFeeBP).div(
                        10000
                    );
                    pool.lpToken.approve(
                        address(pool.gauge),
                        _amount.sub(depositFee)
                    );
                    pool.gauge.deposit(_amount.sub(depositFee), 0);
                } else {
                    pool.lpToken.approve(address(pool.gauge), _amount);
                    pool.gauge.deposit(_amount, 0);
                }
            }
        }
    }

    function depositGaugeOld(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (_amount > 0) {
            if (_pid > 0) {
                pool.lpToken.approve(address(pool.gauge), _amount);
                pool.gauge.deposit(_amount, 0);
            }
        }
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accShieldPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeShieldTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accShieldPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function withdrawGauge(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        if (_pid > 0) {
            pool.gauge.withdrawToken(_amount, 0);
        }
    }

    // Withdraw rewards
    function rewardsWithdraw() public onlyOwner {
        IBEP20 tokenContract = IBEP20(address(XCALaddress));
        uint256 withdrawAmountTokens = tokenContract.balanceOf(address(this));
        tokenContract.transfer(address(msg.sender), withdrawAmountTokens);
    }

    function emergencyGaugeWithdraw(uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.gauge.withdrawAll();
    }

    // Safe shield transfer function, just in case if rounding error causes pool to not have enough HIGHs.
    function safeShieldTransfer(address _to, uint256 _amount) internal {
        uint256 shieldBal = shield.balanceOf(address(this));
        if (_amount > shieldBal) {
            shield.transfer(_to, shieldBal);
        } else {
            shield.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _shieldPerBlock) public onlyOwner {
        massUpdatePools();
        shieldPerBlock = _shieldPerBlock;
    }
}

