// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./SafeERC20.sol";
import "./Ikigai.sol";
import "./IReferral.sol";

// .___ ____  __.___  ________    _____  .___
// |   |    |/ _|   |/  _____/   /  _  \ |   |
// |   |      < |   /   \  ___  /  /_\  \|   |
// |   |    |  \|   \    \_\  \/    |    \   |
// |___|____|__ \___|\______  /\____|__  /___|
//             \/           \/         \/

/**
 * @title Ikigai Masterchef contract
 * @notice Masterchef implementation inspired by Fullsail's fork without deposit fees nor extra emissions for the owner address.
 * Adds sensible reward limits to the referral rewards, and a pool duplication check.
 * Adds support for deflationary tokens (Thanks Rugdoc)
 * 10% of emissions are sent to the Reward Vault to provide additional rewards to the time locked vaults (IkiPool)
 * Total supply check in updatePool
 * Updated to Solidity 0.8 (see https://docs.soliditylang.org/en/v0.8.17/080-breaking-changes.html)
 * Switch from block based to time based accounting (https://developer.arbitrum.io/time)
 * ikigaidex.org
 * @author chef nomi && others && ikigai.
 * @dev im not gonna do natspec for the rest u probably know the drill. <3
 **/
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of IKIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accIkiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accIkiPerShare` (and `lastRewardBlockTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. IKIs to distribute per block.
        uint256 lastRewardBlockTime; // Last block timestamp that IKIs distribution occurs.
        uint256 accIkiPerShare; // Accumulated IKIs per share, times 1e12. See below.
    }

    // The IKI TOKEN!
    Ikigai public iki;
    // IKI tokens created per second.
    uint256 public ikiPerSecond;
    // Bonus muliplier for early iki makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Initial emission rate: 1 IKI per second.
    uint256 public constant INITIAL_EMISSION_RATE = 1 ether;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block timestamp when IKI mining starts.
    uint256 public startTime = type(uint256).max;

    // Iki referral contract address.
    IReferral public ikiReferral;
    // In BPS -- Referral commission rate in basis points. -- Default 2%
    uint16 public referralCommissionRate = 200;
    // In BPS -- Max referral commission rate: 3%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 300;
    // IkiPool Vault Reward Contract Address -- 10% of all the emissions is sent to the reward vault to be distributed in the time locked vault -- In BPS
    address public immutable rewardVault;
    uint256 public constant rewardVaultShare = 1000;

    mapping(IERC20 => bool) private poolExists;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );

    event EmissionRateUpdated(address indexed caller, uint256 newAmount);

    event ReferralCommissionPaid(
        address indexed user,
        address indexed referrer,
        uint256 commissionAmount
    );

    constructor(Ikigai _iki, address _rewardVault) {
        iki = _iki;
        ikiPerSecond = INITIAL_EMISSION_RATE;
        rewardVault = _rewardVault;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        require(multiplierNumber < 5, "invalid multiplier");
        BONUS_MULTIPLIER = multiplierNumber;
    }

    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExists[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner nonDuplicated(_lpToken) {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlockTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // Add Pool to mapping
        poolExists[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlockTime: lastRewardBlockTime,
                accIkiPerShare: 0
            })
        );
    }

    // Update the given pool's IKI allocation point. Can only be called by the owner.
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
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending IKIs on frontend.
    function pendingIki(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accIkiPerShare = pool.accIkiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardBlockTime && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlockTime,
                block.timestamp
            );
            uint256 cakeReward = multiplier
                .mul(ikiPerSecond)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accIkiPerShare = accIkiPerShare.add(
                cakeReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accIkiPerShare).div(1e12).sub(user.rewardDebt);
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
        if (block.timestamp <= pool.lastRewardBlockTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlockTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardBlockTime,
            block.timestamp
        );
        uint256 ikiReward = multiplier
            .mul(ikiPerSecond)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        // If function returns false, max supply is reached and we turn off the emissions.
        bool canMint = iki.mint(address(this), ikiReward);

        if (!canMint) {
            ikiPerSecond = 0;
            // we dont need to continue
            return;
        }

        pool.accIkiPerShare = pool.accIkiPerShare.add(
            ikiReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlockTime = block.timestamp;

        // mint 10% to Reward Vault
        iki.mint(rewardVault, ikiReward.mul(rewardVaultShare).div(10000));
    }

    // Deposit LP tokens to MasterChef for IKI allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (
            _amount > 0 &&
            address(ikiReferral) != address(0) &&
            _referrer != address(0) &&
            _referrer != msg.sender
        ) {
            ikiReferral.recordReferral(msg.sender, _referrer);
        }
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accIkiPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeIkiTransfer(msg.sender, pending);
                payReferralCommission(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            // Thanks for RugDoc advice
            uint256 before = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            uint256 _after = pool.lpToken.balanceOf(address(this));
            _amount = _after.sub(before);
            // Thanks for RugDoc advice

            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accIkiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accIkiPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeIkiTransfer(msg.sender, pending);
            payReferralCommission(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accIkiPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe iki transfer function, just in case if rounding error causes pool to not have enough IKIs.
    function safeIkiTransfer(address _to, uint256 _amount) internal {
        uint256 ikiBal = iki.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > ikiBal) {
            transferSuccess = iki.transfer(_to, ikiBal);
        } else {
            transferSuccess = iki.transfer(_to, _amount);
        }
        require(transferSuccess, "safeIkiTransfer: Transfer failed");
    }

    function reduceEmissions(uint256 _mintAmt) external onlyOwner {
        require(_mintAmt < ikiPerSecond, "Only lower amount allowed.");
        require(
            _mintAmt.mul(100).div(ikiPerSecond) >= 95,
            "Max 5% decrease per transaction."
        );
        ikiPerSecond = _mintAmt;
        emit EmissionRateUpdated(msg.sender, ikiPerSecond);
    }

    // Update the iki referral contract address by the owner
    function setIkiReferral(IReferral _ikiReferral) public onlyOwner {
        ikiReferral = _ikiReferral;
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(
        uint16 _referralCommissionRate
    ) public onlyOwner {
        require(
            _referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE,
            "invalid ref rate"
        );
        referralCommissionRate = _referralCommissionRate;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(ikiReferral) != address(0) && referralCommissionRate > 0) {
            address referrer = ikiReferral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(
                10000
            );

            if (referrer != address(0) && commissionAmount > 0) {
                iki.mint(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        // Ensure that we can only set it before launch
        require(block.timestamp < startTime && block.timestamp < _startTime);
        startTime = _startTime;

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[pid].lastRewardBlockTime = startTime;
        }
    }

    function timeToStart() external view returns (uint256) {
        uint256 _timeToStart;

        block.timestamp < startTime
            ? _timeToStart = startTime - block.timestamp
            : _timeToStart = 0;

        return _timeToStart;
    }

    // Thanks for actually reading all that shit
    // <3
}

