// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.7;

/*

Website https://dibyield.com

__/\\\\\\\\\\\\_____/\\\\\\\\\\\__/\\\\\\\\\\\\\______________/\\\________/\\\_______________________/\\\\\\____________/\\\__        
 _\/\\\////////\\\__\/////\\\///__\/\\\/////////\\\___________\///\\\____/\\\/_______________________\////\\\___________\/\\\__       
  _\/\\\______\//\\\_____\/\\\_____\/\\\_______\/\\\_____________\///\\\/\\\/_____/\\\___________________\/\\\___________\/\\\__      
   _\/\\\_______\/\\\_____\/\\\_____\/\\\\\\\\\\\\\\________________\///\\\/______\///______/\\\\\\\\_____\/\\\___________\/\\\__     
    _\/\\\_______\/\\\_____\/\\\_____\/\\\/////////\\\_________________\/\\\________/\\\___/\\\/////\\\____\/\\\______/\\\\\\\\\__    
     _\/\\\_______\/\\\_____\/\\\_____\/\\\_______\/\\\_________________\/\\\_______\/\\\__/\\\\\\\\\\\_____\/\\\_____/\\\////\\\__   
      _\/\\\_______/\\\______\/\\\_____\/\\\_______\/\\\_________________\/\\\_______\/\\\_\//\\///////______\/\\\____\/\\\__\/\\\__  
       _\/\\\\\\\\\\\\/____/\\\\\\\\\\\_\/\\\\\\\\\\\\\/__________________\/\\\_______\/\\\__\//\\\\\\\\\\__/\\\\\\\\\_\//\\\\\\\/\\_ 
        _\////////////_____\///////////__\/////////////____________________\///________\///____\//////////__\/////////___\///////\//__
*/

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./MerkleProof.sol";
import "./DibYieldToken.sol";

// MasterChef is the master of DIB token. He can make DIB and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once DIB is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract DibYieldMasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bytes32 public whitelistMerkleRoot;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint64 unlockTime; // The withdraw unlock time
        //
        // We do some fancy math here. Basically, any point in time, the amount of DIBs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accDibPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
        //   1. The pool's `accDibPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 stakeToken; // Address of stake token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. DIBs to distribute per block.
        uint256 totalStaked; // Amount of tokens staked in given pool
        uint256 lastRewardTime; // Last timestamp DIBs distribution occurs.
        uint256 accDibPerShare; // Accumulated DIBs per share, times 1e18. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
        bool withDepositLockDiscount; //Allows to lock funds for deposit discound
    }

    // The DIB TOKEN
    DibYieldToken public immutable dib;
    // Dev address.
    address public devaddr;
    // Dev fee percentage.
    uint256 public devFee = 100;
    // DIB tokens created per second.
    uint256 public dibPerSecond;
    // Deposit Fee address
    address public feeAddress;

    // Max emission rate
    uint256 public constant MAX_EMISSION_RATE = 10 ether;
    // Max dev fee
    uint256 public constant MAX_DEV_FEE = 100;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when DIB mining starts.
    uint256 public startTime;

    mapping(uint256 => uint256) lockPeriodDiscounts;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 dibPerSecond);
    event UpdateDevFee(address indexed user, uint256 newFee);
    event LockPeriodDiscountSet(uint256 periodInSeconds, uint256 discount);

    event PoolAdded(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20 indexed stakeToken,
        uint16 depositFee,
        bool withDepositLockDiscount
    );
    event PoolSet(uint256 indexed pid, uint256 allocPoint, uint16 depositFee, bool withDepositLockDiscount);
    event PoolUpdated(
        uint256 indexed pid,
        uint256 lastRewardBlock,
        uint256 stakeSupply,
        uint256 accDibPerShare
    );
    event WhitelistMerkleRootSet(bytes32 newMerkleRoot);

    constructor(
        DibYieldToken _dib,
        address _devaddr,
        address _feeAddress,
        uint256 _dibPerSecond,
        uint256 _startTime
    ) {
        require(_devaddr != address(0), "zero address");
        require(_feeAddress != address(0), "zero address");
        require(_dibPerSecond <= MAX_EMISSION_RATE, "max emission rate exceeded");
        _dib.balanceOf(address(this)); //safety check

        dib = _dib;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        dibPerSecond = _dibPerSecond;
        startTime = _startTime;
        lockPeriodDiscounts[30 days] = 150;
        lockPeriodDiscounts[60 days] = 300;
        lockPeriodDiscounts[90 days] = 450;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _stakeToken,
        uint16 _depositFeeBP,
        bool _withUpdate,
        bool withDepositLockDiscount
    ) external onlyOwner {
        require(_depositFeeBP <= 1000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }

        _stakeToken.balanceOf(address(this)); //safety check

        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                stakeToken: _stakeToken,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accDibPerShare: 0,
                totalStaked: 0,
                depositFeeBP: _depositFeeBP,
                withDepositLockDiscount: withDepositLockDiscount
            })
        );

        emit PoolAdded(poolInfo.length.sub(1), _allocPoint, _stakeToken, _depositFeeBP, withDepositLockDiscount);
    }

    // Update the given pool's DIB allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool _withUpdate,
        bool withDepositLockDiscount
    ) external onlyOwner {
        require(_depositFeeBP <= 1000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        } else {
            updatePool(_pid);
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].withDepositLockDiscount = withDepositLockDiscount;

        emit PoolSet(_pid, _allocPoint, _depositFeeBP, withDepositLockDiscount);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending DIBs on frontend.
    function pendingTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDibPerShare = pool.accDibPerShare;
        uint256 stakeSupply = pool.totalStaked;
        if (block.timestamp > pool.lastRewardTime && stakeSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 totalDib = multiplier.mul(dibPerSecond).mul(pool.allocPoint).div(
                totalAllocPoint
            );
            uint256 forDevs = totalDib.mul(devFee).div(1000);
            uint256 dibReward = totalDib.sub(forDevs);
            accDibPerShare = accDibPerShare.add(dibReward.mul(1e18).div(stakeSupply));
        }
        return user.amount.mul(accDibPerShare).div(1e18).sub(user.rewardDebt);
    }

    function calculateNewUnlockTimeForUser(
        address _user,
        uint256 _pid,
        uint256 _lockTime,
        uint256 _amount
    ) public view returns (uint64) {
        uint256 userBalance = userInfo[_pid][_user].amount;
        uint256 unlockTime = userInfo[_pid][_user].unlockTime;
        uint256 timeToUnlock = 0;
        if (unlockTime > block.timestamp) {
            timeToUnlock = unlockTime - block.timestamp;
        }
        return calculateUnlockTime(userBalance, timeToUnlock, _amount, _lockTime);
    }

    function calculateUnlockTime(
        uint256 _oldAmount,
        uint256 _lockTimeLeft,
        uint256 _amount,
        uint256 _lockTime
    ) public pure returns (uint64) {
        if(_oldAmount + _amount == 0) return 0;
        return uint64((_oldAmount * _lockTimeLeft + _lockTime * _amount) / (_oldAmount + _amount));
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
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 stakeSupply = pool.totalStaked;
        if (stakeSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 totalDib = multiplier.mul(dibPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        if (totalDib == 0) return;

        uint256 forDevs = totalDib.mul(devFee).div(1000);
        uint256 dibReward = totalDib.sub(forDevs);
        dib.mint(devaddr, forDevs);
        dib.mint(address(this), dibReward);
        pool.accDibPerShare = pool.accDibPerShare.add(dibReward.mul(1e18).div(stakeSupply));
        pool.lastRewardTime = block.timestamp;
        emit PoolUpdated(_pid, pool.lastRewardTime, stakeSupply, pool.accDibPerShare);
    }

    // Deposit tokens to MasterChef for DIB allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        uint64 _lockPeriod,
        bytes32[] calldata _whitelistProof
    ) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 finalDepositAmount;
        uint256 pending;
        updatePool(_pid);
        if (user.amount > 0) {
            pending = user.amount.mul(pool.accDibPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                safeDibTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            // Prefetch balance to account for transfer fees
            uint256 preStakeBalance = pool.stakeToken.balanceOf(address(this));
            pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            finalDepositAmount = pool.stakeToken.balanceOf(address(this)) - preStakeBalance;

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = finalDepositAmount.mul(pool.depositFeeBP).div(10000);
                if (
                    _whitelistProof.length != 0 &&
                    whitelistMerkleRoot != bytes32(0)) {
                    require(
                        MerkleProof.verify(
                            _whitelistProof,
                            whitelistMerkleRoot,
                            keccak256(bytes.concat(keccak256(abi.encode(msg.sender))))
                        ),
                        "wrong proof"
                    );
                    depositFee = depositFee.div(2);
                }
                if (pool.withDepositLockDiscount && _lockPeriod > 0) {
                    uint256 lockDiscount = lockPeriodDiscounts[_lockPeriod];
                    require(lockDiscount > 0, "wrong lock period");
                    depositFee = (depositFee * (1000 - lockDiscount)) / 1000;
                    userInfo[_pid][msg.sender].unlockTime = uint64(
                        block.timestamp +
                            calculateNewUnlockTimeForUser(msg.sender, _pid, _lockPeriod, _amount)
                    );
                } else if(userInfo[_pid][msg.sender].unlockTime > block.timestamp) {
                    userInfo[_pid][msg.sender].unlockTime = uint64(
                        block.timestamp +
                            calculateNewUnlockTimeForUser(msg.sender, _pid, 0, _amount)
                    );
                }
                pool.stakeToken.safeTransfer(feeAddress, depositFee);
                finalDepositAmount = finalDepositAmount.sub(depositFee);
            }
            user.amount = user.amount.add(finalDepositAmount);
            pool.totalStaked = pool.totalStaked.add(finalDepositAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accDibPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, finalDepositAmount);
    }

    // Withdraw tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "too much");
        require(user.unlockTime <= block.timestamp, "not yet");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accDibPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            safeDibTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalStaked = pool.totalStaked.sub(_amount);
            pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDibPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.unlockTime <= block.timestamp, "not yet");
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked = pool.totalStaked.sub(amount);
        pool.stakeToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe DIB transfer function, just in case if rounding error causes pool to not have enough DIBs.
    function safeDibTransfer(address _to, uint256 _amount) internal {
        uint256 dibBal = dib.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > dibBal) {
            transferSuccess = dib.transfer(_to, dibBal);
        } else {
            transferSuccess = dib.transfer(_to, _amount);
        }
        require(transferSuccess, "safeDibTransfer: transfer failed");
    }

    /// @param _startTime The block to start mining
    /// @notice can only be changed if farming has not started already
    function setStartTime(uint256 _startTime) external onlyOwner {
        require(startTime > block.timestamp, "Farming started");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardTime = _startTime;
        }
        startTime = _startTime;
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devaddr) external onlyOwner {
        require(_devaddr != address(0), "zero address");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "zero address");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _dibPerSecond) external onlyOwner {
        massUpdatePools();
        _updateEmissionRate(_dibPerSecond);
    }

    function _updateEmissionRate(uint256 _dibPerSecond) internal {
        require(_dibPerSecond <= MAX_EMISSION_RATE, "Updated emissions are more than maximum rate");
        dibPerSecond = _dibPerSecond;
        emit UpdateEmissionRate(msg.sender, _dibPerSecond);
    }

    function updateDevFee(uint256 _newDevFee) external onlyOwner {
        require(_newDevFee <= MAX_DEV_FEE, "Updated fee is more than maximum rate");
        devFee = _newDevFee;
        emit UpdateDevFee(msg.sender, _newDevFee);
    }

    function setWhitelistMerkleRoot(bytes32 _root) external onlyOwner {
        whitelistMerkleRoot = _root;
        emit WhitelistMerkleRootSet(_root);
    }

    function setLockDiscount(uint256 _periodInSeconds, uint256 _discount) external onlyOwner {
        require(_discount <= 1000, "invalid discount value");
        require(_periodInSeconds > 0, "invalid discount value");
        lockPeriodDiscounts[_periodInSeconds] = _discount;
        emit LockPeriodDiscountSet(_periodInSeconds, _discount);
    }
}

