// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { EnumerableSetUpgradeable } from "./EnumerableMapUpgradeable.sol";

import { IRewardPerSec } from "./IRewardPerSec.sol";
import { ILeverageVault } from "./ILeverageVault.sol";
import { IBoosting } from "./IBoosting.sol";

interface ISingleStaking {
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 boostMultiplier; //current multiplier after boosting
    }

    struct PoolInfo {
        IERC20Upgradeable lpToken;
        uint256 allocPoint; // How many allocation points assigned to this pool. esVKAs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that esVKAs distribution occurs.
        uint256 accesVKAPerShare; // Accumulated esVKAs per share, times 1e18. See below.
        uint256 totalBoostedShare; // total boosted share amount in this pool
        IRewardPerSec rewarder;
    }
}

/**
 * @title Vaultka Tokenomics - SingleStaking Contract
 * @notice  accept Proof of Deposit token (POD) as staking token, and earn esVKA as reward, and VKA reward when liquidity mining incentive program is on.
 * @author Vaultka
 **/

contract SingleStakingV2 is ISingleStaking, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    // Main Reward Token
    IERC20Upgradeable public esVKAToken;

    uint256 public BOOST_PRECISION;

    uint256 public ACC_ESVKA_PRECISION;
    IBoosting public boostContract;
    // esVKA tokens created per second.
    uint256 public esVKAPerSec;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when esVKA mining starts.
    uint256 public startTimestamp;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Set of all LP tokens that have been added as pools
    EnumerableSetUpgradeable.AddressSet private lpTokens;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    mapping(address => uint256) public pendingAmount; //pending amount if there is not enough balance in the pool
    mapping(address => bool) public isLeverageVault;

    event Add(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC20Upgradeable indexed lpToken,
        IRewardPerSec indexed rewarder
    );
    event Set(uint256 indexed pid, uint256 allocPoint, IRewardPerSec indexed rewarder, bool overwrite);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdatePool(uint256 indexed pid, uint256 lastRewardTimestamp, uint256 lpSupply, uint256 accesVKAPerShare);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event UpdateEmissionRate(address indexed user, uint256 _esVKAPerSec);
    event UpdateBoostMultiplier(
        address indexed user,
        uint256 indexed pid,
        uint256 oldMultiplier,
        uint256 newMultiplier
    );
    event MissingTokenRecovered(address indexed user, uint256 amount);
    event SetTreasuryAddress(address indexed newAddress);

    ///@notice modifier to check if the caller is a leverage vault
    modifier onlyLeverageVault() {
        require(isLeverageVault[msg.sender], "Leverage Vault only");
        _;
    }

    ///@custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize function
    function initialize(
        IERC20Upgradeable _esVKAToken,
        IBoosting _boosting,
        uint256 _esVKAPerSec,
        uint256 _startTimestamp
    ) external initializer {
        //Implement zero address checks
        require(address(_esVKAToken) != address(0) && address(_boosting) != address(0), "constructor: address is zero");

        esVKAToken = _esVKAToken;
        boostContract = _boosting;
        esVKAPerSec = _esVKAPerSec;
        startTimestamp = _startTimestamp;
        totalAllocPoint = 0;

        BOOST_PRECISION = 100 * 1e10;

        ACC_ESVKA_PRECISION = 1e18;

        __Ownable_init();
    }

    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /// set an address as one of the leverage Vaults within the Vaultka ecosystem
    /// @param _vault address of the leverage vault
    /// @param _isLeverageVault boolean to indicate if the address is a leverage vault
    function setLeverageVault(address _vault, bool _isLeverageVault) external onlyOwner {
        require(_vault != address(0), "No zero addresses");
        isLeverageVault[_vault] = _isLeverageVault;
    }

    function recoverMissingToken() external {
        //if the pending amount is greater than 0, then transfer the amount to the owner
        uint256 amount = pendingAmount[msg.sender];
        require(amount > 0, "No pending amount");
        //make sure there is enough balance to avoid infinite loop of func call
        require(amount <= esVKAToken.balanceOf(address(this)), "Not enough balance");
        pendingAmount[msg.sender] = 0;
        _safeEsVKATransfer(msg.sender, amount);

        //add event for this function

        emit MissingTokenRecovered(msg.sender, amount);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    /// @notice function to add a new pool
    /// @param _allocPoint allocation point of the pool
    /// @param _lpToken address of the token
    /// @param _rewarder address of the rewarder contract
    /// @dev DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IERC20Upgradeable _lpToken, IRewardPerSec _rewarder) external onlyOwner {
        require(poolInfo.length < 25, "add: Too many pools");
        require(isContract(address(_lpToken)), "add: LP token must be a valid contract");
        require(
            isContract(address(_rewarder)) || address(_rewarder) == address(0),
            "add: rewarder must be contract or zero"
        );
        require(!lpTokens.contains(address(_lpToken)), "add: LP already added");
        // require(address(_lpToken) != address(0), "add: LP cannot be address 0");

        massUpdatePools();
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint += _allocPoint;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimestamp: lastRewardTimestamp,
                accesVKAPerShare: 0,
                totalBoostedShare: 0,
                rewarder: _rewarder
            })
        );
        lpTokens.add(address(_lpToken));
        emit Add(poolInfo.length - 1, _allocPoint, _lpToken, _rewarder);
    }

    /// @notice Update the given pool's esVKA allocation point. Can only be called by the owner.
    /// @param _pid pool id
    /// @param _allocPoint allocation point of the pool
    /// @param _rewarder address of the rewarder contract
    /// @param overwrite boolean to indicate if the rewarder contract should be overwritten
    function set(uint256 _pid, uint256 _allocPoint, IRewardPerSec _rewarder, bool overwrite) external onlyOwner {
        require(
            isContract(address(_rewarder)) || address(_rewarder) == address(0),
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

    function resetAccEs(uint256 _pid1, uint256 _pid2) public onlyOwner {
        PoolInfo storage pool1 = poolInfo[_pid1];
        PoolInfo storage pool2 = poolInfo[_pid2];
        pool1.accesVKAPerShare = 0;
        pool2.accesVKAPerShare = 0;
        updatePool(_pid1);
        updatePool(_pid2);
    }

    function resetUserDebt(uint256 _pid, address[] memory _users, uint256[] memory _pendings) external onlyOwner {
       require(_users.length == _pendings.length, "resetUserDebt: length not match");
       for (uint256 i = 0; i < _users.length; i++) {
           UserInfo storage user = userInfo[_pid][_users[i]];
           PoolInfo storage pool = poolInfo[_pid];
           user.rewardDebt = 0;
           _safeEsVKATransfer(_users[i], _pendings[i]);
       }
    }

    function resetSingleUserDebt(uint256 _pid, address _user) external onlyOwner {
        UserInfo storage user = userInfo[_pid][_user];
        user.rewardDebt = 0;
    }

    // Deposit LP tokens to MasterChef for esVKA allocation.
    /// @notice function to deposit staking token
    /// @param _pid pool id
    /// @param _amount amount of staking token
    function deposit(uint256 _pid, uint256 _amount) external {
        poolInfo[_pid] = updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];


        uint256 multiplier = getBoostMultiplier(msg.sender, _pid);
        if (user.amount > 0) {
            _settlePendingESVKA(msg.sender, _pid, multiplier);
        }

        multiplier = boostContract.getBoostMultiplierWithDeposit(msg.sender, _pid, _amount);

        if (_amount > 0) {
            uint256 before = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)) - before;
            user.amount = user.amount + _amount;
            pool.totalBoostedShare += (_amount * multiplier) / BOOST_PRECISION;
        }

        user.rewardDebt =
            (((user.amount * multiplier) / BOOST_PRECISION) * pool.accesVKAPerShare) /
            ACC_ESVKA_PRECISION;

        IRewardPerSec rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onesVKAReward(msg.sender, user.amount);
        }

        user.boostMultiplier = multiplier;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice function to withdraw staking token from Master Chef
    /// @param _pid pool id
    /// @param _amount amount of staking token
    function withdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not enough balance");

        uint256 multiplier = getBoostMultiplier(msg.sender, _pid);
        _settlePendingESVKA(msg.sender, _pid, multiplier);

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        uint256 userBoostedAmount = (_amount * multiplier) / BOOST_PRECISION;

        if (poolInfo[_pid].totalBoostedShare > userBoostedAmount) {
            poolInfo[_pid].totalBoostedShare -= userBoostedAmount;
        } else {
            pool.totalBoostedShare = 0;
        }

        user.boostMultiplier = boostContract.getBoostMultiplier(msg.sender, _pid);
        user.rewardDebt =
            (user.amount * user.boostMultiplier * pool.accesVKAPerShare) /
            ACC_ESVKA_PRECISION /
            BOOST_PRECISION;

        IRewardPerSec rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onesVKAReward(msg.sender, user.amount);
        }

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param _pid pool id
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        uint256 boostedAmount = (amount * getBoostMultiplier(msg.sender, _pid)) / BOOST_PRECISION;
        pool.totalBoostedShare = pool.totalBoostedShare > boostedAmount ? pool.totalBoostedShare - boostedAmount : 0;

        // Note: transfer can fail or succeed if `amount` is zero.
        pool.lpToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /// @notice function to update the emission rate, by the owner
    /// @param _esVKAPerSec amount of esVKA emitted per second
    function updateEmissionRate(uint256 _esVKAPerSec) external onlyOwner {
        massUpdatePools();
        esVKAPerSec = _esVKAPerSec;
        emit UpdateEmissionRate(msg.sender, _esVKAPerSec);
    }

    /// @notice function to update the boost multiplier of a user in a pool
    /// @param _user user address
    /// @param _pid pool id
    /// @return _newMultiplier new multiplier
    function updateBoostMultiplier(address _user, uint256 _pid) public returns (uint256 _newMultiplier) {
        require(_user != address(0), "MasterChefV2: The user address must be valid");

        if (msg.sender != address(this)) {
            poolInfo[_pid] = updatePool(_pid);
        }

        PoolInfo storage pool = poolInfo[_pid];

        UserInfo storage user = userInfo[_pid][_user];

        uint256 prevMultiplier = getBoostMultiplier(_user, _pid);

        _settlePendingESVKA(_user, _pid, prevMultiplier);

        _newMultiplier = boostContract.getBoostMultiplier(_user, _pid);
        user.boostMultiplier = _newMultiplier;

        user.rewardDebt =
            (user.amount * _newMultiplier * pool.accesVKAPerShare) /
            ACC_ESVKA_PRECISION /
            BOOST_PRECISION;

        pool.totalBoostedShare =
            pool.totalBoostedShare +
            (user.amount * _newMultiplier) /
            BOOST_PRECISION -
            (user.amount * prevMultiplier) /
            BOOST_PRECISION;

        emit UpdateBoostMultiplier(_user, _pid, prevMultiplier, _newMultiplier);
    }

    //get how much POD token singleStaking is currently holding, by pool id
    function getPoolTokenBalance(uint256 _pid) external view returns (uint256) {
        return poolInfo[_pid].lpToken.balanceOf(address(this));
    }

    /// notice function to check how many pools are there
    /// return amount of pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// notice get the token address by pool id
    /// @param _pid pool id
    /// @return address of the token

    function getPoolTokenAddress(uint256 _pid) external view returns (address) {
        if (_pid >= poolInfo.length) {
            return address(0);
        }
        return address(poolInfo[_pid].lpToken);
    }

    /// @notice View function to see pending esVKAs on frontend.
    /// @param _pid pool id
    /// @param _user user address
    /// @return pendingesVKA pending esVKA reward for a given user
    /// @return bonusTokenAddress address of the bonus token
    /// @return pendingBonusToken pending bonus token reward for a given user
    function pendingTokens(
        uint256 _pid,
        address _user
    ) external view returns (uint256 pendingesVKA, address bonusTokenAddress, uint256 pendingBonusToken) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accesVKAPerShare = pool.accesVKAPerShare;

        if (block.timestamp > pool.lastRewardTimestamp && pool.totalBoostedShare != 0) {
            uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
            uint256 lpPercent = 1000;
            uint256 esVKAReward = (multiplier * esVKAPerSec * pool.allocPoint * lpPercent) / totalAllocPoint / 1000;
            accesVKAPerShare = accesVKAPerShare + ((esVKAReward * 1e18) / pool.totalBoostedShare);
        }

        uint256 boostedAmount = (user.amount * getBoostMultiplier(_user, _pid)) / BOOST_PRECISION;

        pendingesVKA = (boostedAmount * accesVKAPerShare) / 1e18 - user.rewardDebt;
        // If it's a double reward farm, we return info about the bonus token
        if (address(pool.rewarder) != address(0)) {
            (bonusTokenAddress) = rewarderBonusTokenInfo(_pid);
            pendingBonusToken = pool.rewarder.pendingTokens(_user);
        }
    }

    // Update reward variables for all pools.
    /// @notice function to update all pools
    /// @dev be aware of the gas limit
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    /// @notice function to update a pool
    /// @param _pid pool id
    /// @return pool info
    function updatePool(uint256 _pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[_pid];

        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 lpSupply = pool.totalBoostedShare;
            if (lpSupply > 0 && pool.allocPoint > 0) {
                uint256 multiplier = block.timestamp - pool.lastRewardTimestamp;
                uint256 esVKAReward = (multiplier * esVKAPerSec * pool.allocPoint) / totalAllocPoint;

                uint256 lpPercent = 1000;
                pool.accesVKAPerShare += (esVKAReward * 1e18 * lpPercent) / (lpSupply * 1000);

                pool.lastRewardTimestamp = block.timestamp;
                poolInfo[_pid] = pool;

                // esVKAToken.transfer(address(this), esVKAReward * lpPercent / 1000);
            }

            emit UpdatePool(_pid, pool.lastRewardTimestamp, lpSupply, pool.accesVKAPerShare);
        }
    }

    /// @notice burn the staking token for a user and send the pending rewards
    /// @notice when rewarder address is 0, it means it is a single reward farm and there is no bonus token
    ///@dev custom function for the tokenomics, to allow the leverage pool to call this function, burn the staking token for a user and send the pending rewards
    /// @param _pid pool id
    /// @param _user user address
    /// @param _amount amount of staking token
    function unstakeAndLiquidate(uint256 _pid, address _user, uint256 _amount) public onlyLeverageVault {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        require(user.amount > 0, "User has no stake in the pool");

        updatePool(_pid);

        uint256 multiplier = getBoostMultiplier(_user, _pid);
        _settlePendingESVKA(_user, _pid, multiplier);

        user.amount -= _amount;
        // update the user's reward debt

        uint256 boostedAmount = (user.amount * multiplier) / BOOST_PRECISION;
        if (pool.totalBoostedShare > boostedAmount) {
            pool.totalBoostedShare -= boostedAmount;
        } else {
            pool.totalBoostedShare = 0;
        }
        user.boostMultiplier = boostContract.getBoostMultiplier(msg.sender, _pid);
        user.rewardDebt =
            (user.amount * user.boostMultiplier * pool.accesVKAPerShare) /
            ACC_ESVKA_PRECISION /
            BOOST_PRECISION;

        IRewardPerSec rewarder = poolInfo[_pid].rewarder;
        if (address(rewarder) != address(0)) {
            rewarder.onesVKAReward(_user, user.amount);
        }

        ILeverageVault(msg.sender).burn(_amount);
    }

    /// @notice function to get the amount of staked token for a user
    /// @param _pid pool id
    /// @param _user user address
    /// @return amount of staked token
    function getUserAmount(uint256 _pid, address _user) public view returns (uint256) {
        return userInfo[_pid][_user].amount;
    }

    /// @notice get bonus token info from the rewarder contract for a given pool, if it is a bonus reward farm
    /// @param _pid pool id
    /// @return bonusTokenAddress

    function rewarderBonusTokenInfo(uint256 _pid) public view returns (address bonusTokenAddress) {
        PoolInfo storage pool = poolInfo[_pid];
        if (address(pool.rewarder) != address(0)) {
            bonusTokenAddress = address(pool.rewarder.rewardToken());
        }
    }

    /// @notice function to get the boost multiplier of a user in a pool
    /// @param _user user address
    /// @param _pid pool id
    function getBoostMultiplier(address _user, uint256 _pid) public view returns (uint256) {
        return userInfo[_pid][_user].boostMultiplier > 0 ? userInfo[_pid][_user].boostMultiplier : BOOST_PRECISION;
    }

    /// @notice  Safe esVKA transfer function, just in case if rounding error causes pool to not have enough esVKAs.
    /// @param _to address of the receiver
    /// @param _amount amount of esVKA token
    /// @notice  Safe esVKA transfer function, just in case if rounding error causes pool to not have enough esVKAs.
    /// @param _to address of the receiver
    /// @param _amount amount of esVKA token

    function _safeEsVKATransfer(address _to, uint256 _amount) internal {
        uint256 esVKABal = esVKAToken.balanceOf(address(this));
        if (_amount > esVKABal) {
            pendingAmount[_to] += _amount - esVKABal;
            esVKAToken.safeTransfer(_to, esVKABal);
        } else {
            esVKAToken.safeTransfer(_to, _amount);
        }
    }

    /// @notice function to settle the pending esVKA for a user in a pool
    /// @param _user user address
    /// @param _pid pool id
    /// @param _boostMultiplier multiplier of the user
    /// @return pending amount of esVKA token
    function _settlePendingESVKA(
        address _user,
        uint256 _pid,
        uint256 _boostMultiplier
    ) internal returns (uint256 pending) {
        UserInfo memory user = userInfo[_pid][_user];
        uint256 boostedAmount = (user.amount * _boostMultiplier) / BOOST_PRECISION;
        uint256 accESVKA = (boostedAmount * poolInfo[_pid].accesVKAPerShare) / ACC_ESVKA_PRECISION;
        pending = accESVKA - user.rewardDebt;

        // SafeTransfer ESVKA
        _safeEsVKATransfer(_user, pending);

        emit Harvest(msg.sender, _pid, pending);

        return pending;
    }

    //owner withdraw all esVKA balance
    function withdrawAllESVKA() external onlyOwner {
        esVKAToken.safeTransfer(msg.sender, esVKAToken.balanceOf(address(this)));
    }
}

