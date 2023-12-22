// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IStrategy} from "./IStrategy.sol";
import {MonopolyToken} from "./MonopolyToken.sol";
import {IEarningsReferral} from "./IEarningsReferral.sol";

import "./console.sol";

contract MonoMaster is Ownable {
    using SafeERC20 for IERC20;

    address public deployer;

    bool public isInitialized;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many shares the user currently has
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastDepositTimestamp; // Timestamp of the last deposit.

        //
        // We do some fancy math here. Basically, any point in time, the amount of Rewards
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accEarningPerShare) / ACC_EARNING_PRECISION - user.rewardDebt
        //
        // Whenever a user harvest from a pool, here's what happens:
        //   1. The pool's `accEarningPerShare` gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 want; // Address of LP token contract.
        IStrategy strategy; // Address of strategy for pool
        uint256 allocPoint; // How many allocation points assigned to this pool. earnings to distribute per block.
        uint256 lastRewardTime; // Last block number that earnings distribution occurs.
        uint256 accEarningPerShare; // Accumulated earnings per share, times ACC_EARNING_PRECISION. See below.
        uint256 totalShares; //total number of shares in the pool
        uint256 lpPerShare; //number of LP tokens per share, times ACC_EARNING_PRECISION
        uint16 depositFeeBP; // Deposit fee in basis points
        uint16 withdrawFeeBP; // Withdraw fee in basis points
        bool isWithdrawFee; // if the pool has withdraw fee
    }

    // The main reward token!
    MonopolyToken public earningToken;
    // The block when mining starts.
    uint256 public startTime;
    //development endowment
    address public dev;
    //performance fee address -- receives performance fees from strategies
    address public performanceFeeAddress;
    //actionFee fee address -- receives actionFee fees, deposit,withdraw
    address public actionFeeAddress;
    // amount of reward emitted per second
    uint256 public earningsPerSecond;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    //allocations to dev and nest addresses, expressed in BIPS
    uint256 public devMintBips = 1000;
    //whether the onlyApprovedContractOrEOA is turned on or off
    bool public onlyApprovedContractOrEOAStatus;

    uint256 internal constant ACC_EARNING_PRECISION = 1e18;
    uint256 internal constant MAX_BIPS = 10000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    //mappping for tracking contracts approved to build on top of this one
    mapping(address => bool) public approvedContracts;
    //tracks historic deposits of each address. deposits[pid][user] is the total deposits for that user to that mono
    mapping(uint256 => mapping(address => uint256)) public deposits;
    //tracks historic withdrawals of each address. withdrawals[pid][user] is the total withdrawals for that user from that mono
    mapping(uint256 => mapping(address => uint256)) public withdrawals;

    uint16 public constant MAX_DEPOSIT_FEE_BP = 400;
    uint16 public constant MAX_WITHDRAW_FEE_BP = 400;
    uint256 public MAX_LINEAR_DURATION = 3 days;
    uint256 public REWARD_DURATION = 21 days;

    // Earnings referral contract address.
    IEarningsReferral public earningReferral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 300;
    // Max referral commission rate: 20%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 2000;

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
    event DevSet(address indexed oldAddress, address indexed newAddress);
    event PerformanceFeeAddressSet(
        address indexed oldAddress,
        address indexed newAddress
    );
    event ReferralCommissionPaid(
        address indexed user,
        address indexed referrer,
        uint256 commissionAmount
    );

    /**
     * @notice Throws if called by smart contract
     */
    modifier onlyApprovedContractOrEOA() {
        if (onlyApprovedContractOrEOAStatus) {
            require(
                tx.origin == msg.sender || approvedContracts[msg.sender],
                "MonoMaster::onlyApprovedContractOrEOA"
            );
        }
        _;
    }

    constructor() {
        deployer = msg.sender;
    }

    function initialize(
        MonopolyToken _earningToken,
        uint256 _startTime,
        address _dev,
        address _performanceFeeAddress,
        address _actionFeeAddress,
        uint256 _earningsPerSecond
    ) external {
        require(!isInitialized, "already initialized");
        require(_startTime > block.timestamp, "must start in future");
        require(_dev != address(0), "dev address cannot be 0");
        require(
            _performanceFeeAddress != address(0),
            "performanceFee address cannot be 0"
        );
        require(
            _actionFeeAddress != address(0),
            "actionFee address cannot be 0"
        );

        isInitialized = true;
        earningToken = _earningToken;
        startTime = _startTime;
        dev = _dev;
        performanceFeeAddress = _performanceFeeAddress;
        actionFeeAddress = _actionFeeAddress;
        earningsPerSecond = _earningsPerSecond;
        emit DevSet(address(0), _dev);
        emit PerformanceFeeAddressSet(address(0), _performanceFeeAddress);
    }

    //VIEW FUNCTIONS
    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see total pending reward in = on frontend.
    function pendingEarnings(
        uint256 pid,
        address userAddr
    ) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][userAddr];
        uint256 accEarningPerShare = pool.accEarningPerShare;
        uint256 poolShares = pool.totalShares;
        if (block.timestamp > pool.lastRewardTime && poolShares != 0) {
            uint256 earningsReward = (reward(
                pool.lastRewardTime,
                block.timestamp
            ) * pool.allocPoint) / totalAllocPoint;
            accEarningPerShare =
                accEarningPerShare +
                ((earningsReward * ACC_EARNING_PRECISION) / poolShares);
        }
        return
            ((user.amount * accEarningPerShare) / ACC_EARNING_PRECISION) -
            user.rewardDebt;
    }

    // view function to get all pending rewards, from MonoMaster, Strategy, and Rewarder
    function pendingTokens(
        uint256 pid,
        address user
    ) external view returns (address[] memory, uint256[] memory) {
        uint256 earningAmount = pendingEarnings(pid, user);
        (
            address[] memory strategyTokens,
            uint256[] memory strategyRewards
        ) = poolInfo[pid].strategy.pendingTokens(pid, user, earningAmount);

        uint256 rewardsLength = 1;
        for (uint256 j = 0; j < strategyTokens.length; j++) {
            if (strategyTokens[j] != address(0)) {
                rewardsLength += 1;
            }
        }
        address[] memory _rewardTokens = new address[](rewardsLength);
        uint256[] memory _pendingAmounts = new uint256[](rewardsLength);
        _rewardTokens[0] = address(earningToken);
        _pendingAmounts[0] = earningAmount;
        for (uint256 m = 0; m < strategyTokens.length; m++) {
            if (strategyTokens[m] != address(0)) {
                _rewardTokens[m + 1] = strategyTokens[m];
                _pendingAmounts[m + 1] = strategyRewards[m];
            }
        }
        return (_rewardTokens, _pendingAmounts);
    }

    // Return reward over the period _from to _to.
    function reward(
        uint256 _lastRewardTime,
        uint256 _currentTime
    ) public view returns (uint256) {
        if (_lastRewardTime > startTime + REWARD_DURATION) {
            return 0;
        }
        if (_currentTime > startTime + REWARD_DURATION) {
            _currentTime = startTime + REWARD_DURATION;
        }

        return ((_currentTime - _lastRewardTime) * earningsPerSecond);
    }

    //convenience function to get the yearly emission of reward at the current emission rate
    function earningPerYear() public view returns (uint256) {
        //31536000 = seconds per year = 365 * 24 * 60 * 60
        return (earningsPerSecond * 31536000);
    }

    //convenience function to get the yearly emission of reward at the current emission rate, to a given monopoly
    function earningPerYearToMonopoly(
        uint256 pid
    ) public view returns (uint256) {
        return ((earningPerYear() * poolInfo[pid].allocPoint) /
            totalAllocPoint);
    }

    //convenience function to get the total number of shares in an monopoly
    function totalShares(uint256 pid) public view returns (uint256) {
        return poolInfo[pid].totalShares;
    }

    //convenience function to get the total amount of LP tokens in an monopoly
    function totalLP(uint256 pid) public view returns (uint256) {
        return ((poolInfo[pid].lpPerShare * totalShares(pid)) /
            ACC_EARNING_PRECISION);
    }

    //convenience function to get the shares of a single user in an monopoly
    function userShares(
        uint256 pid,
        address user
    ) public view returns (uint256) {
        return userInfo[pid][user].amount;
    }

    //WRITE FUNCTIONS
    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint256 poolShares = pool.totalShares;
            if (poolShares == 0 || pool.allocPoint == 0) {
                pool.lastRewardTime = block.timestamp;
                return;
            }
            uint256 earningReward = (reward(
                pool.lastRewardTime,
                block.timestamp
            ) * pool.allocPoint) / totalAllocPoint;
            pool.lastRewardTime = block.timestamp;
            if (earningReward > 0) {
                uint256 toDev = (earningReward * devMintBips) / MAX_BIPS;
                pool.accEarningPerShare =
                    pool.accEarningPerShare +
                    ((earningReward * ACC_EARNING_PRECISION) / poolShares);
                earningToken.mint(dev, toDev);
                earningToken.mint(address(this), earningReward);
            }
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Deposit LP tokens to MonoMaster for reward allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(
        uint256 pid,
        uint256 amount,
        address to,
        address _referrer
    ) external onlyApprovedContractOrEOA {
        uint256 totalAmount = amount;
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        if (amount > 0) {
            UserInfo storage user = userInfo[pid][to];

            if (
                address(earningReferral) != address(0) &&
                _referrer != address(0) &&
                _referrer != msg.sender
            ) {
                earningReferral.recordReferral(msg.sender, _referrer);
            }

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = (amount * pool.depositFeeBP) / 10000;
                pool.want.safeTransferFrom(
                    address(msg.sender),
                    actionFeeAddress,
                    depositFee
                );
                amount = amount - depositFee;
            }

            //find number of new shares from amount
            uint256 newShares = (amount * ACC_EARNING_PRECISION) /
                pool.lpPerShare;

            //transfer tokens directly to strategy
            pool.want.safeTransferFrom(
                address(msg.sender),
                address(pool.strategy),
                amount
            );
            //tell strategy to deposit newly transferred tokens and process update
            pool.strategy.deposit(msg.sender, to, amount, newShares);

            //track new shares
            pool.totalShares = pool.totalShares + newShares;
            user.amount = user.amount + newShares;
            user.rewardDebt =
                user.rewardDebt +
                ((newShares * pool.accEarningPerShare) / ACC_EARNING_PRECISION);
            user.lastDepositTimestamp = block.timestamp;
            //track deposit for profit tracking
            deposits[pid][to] += totalAmount;

            emit Deposit(msg.sender, pid, totalAmount, to);
        }
    }

    /// @notice Withdraw LP tokens from MonoMaster.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(
        uint256 pid,
        uint256 amountShares,
        address to
    ) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amountShares, "withdraw: not good");

        if (amountShares > 0) {
            //find amount of LP tokens from shares
            uint256 lpFromShares = (amountShares * pool.lpPerShare) /
                ACC_EARNING_PRECISION;

            uint256 withdrawFeeBP;
            if (pool.isWithdrawFee) {
                withdrawFeeBP = getWithdrawFee(pid, msg.sender);
            }

            //track withdrawal for profit tracking
            withdrawals[pid][to] += lpFromShares;
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            pool.strategy.withdraw(
                msg.sender,
                to,
                lpFromShares,
                amountShares,
                withdrawFeeBP
            );

            //track removed shares
            user.amount = user.amount - amountShares;
            uint256 rewardDebtOfShares = ((amountShares *
                pool.accEarningPerShare) / ACC_EARNING_PRECISION);
            uint256 userRewardDebt = user.rewardDebt;
            user.rewardDebt = (userRewardDebt >= rewardDebtOfShares)
                ? (userRewardDebt - rewardDebtOfShares)
                : 0;
            pool.totalShares = pool.totalShares - amountShares;

            emit Withdraw(msg.sender, pid, amountShares, to);
        }
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of rewards.
    function harvest(
        uint256 pid,
        address to
    ) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        //find all time rewards for all of user's shares
        uint256 accumulatedEarnings = (user.amount * pool.accEarningPerShare) /
            ACC_EARNING_PRECISION;
        //subtract out the rewards they have already been entitled to
        uint256 pendings = accumulatedEarnings - user.rewardDebt;
        //update user reward debt
        user.rewardDebt = accumulatedEarnings;

        //send remainder as reward
        if (pendings > 0) {
            safeEarningsTransfer(to, pendings);
            payReferralCommission(msg.sender, pendings);
        }

        //call strategy to update
        pool.strategy.withdraw(msg.sender, to, 0, 0, 0);

        emit Harvest(msg.sender, pid, pendings);
    }

    /// @notice Withdraw LP tokens from MonoMaster.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdrawAndHarvest(
        uint256 pid,
        uint256 amountShares,
        address to
    ) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amountShares, "withdraw: not good");

        //find all time rewards for all of user's shares
        uint256 accumulatedEarnings = (user.amount * pool.accEarningPerShare) /
            ACC_EARNING_PRECISION;
        //subtract out the rewards they have already been entitled to
        uint256 pendings = accumulatedEarnings - user.rewardDebt;
        //find amount of LP tokens from shares
        uint256 lpToSend = (amountShares * pool.lpPerShare) /
            ACC_EARNING_PRECISION;

        uint256 withdrawFeeBP;
        if (pool.isWithdrawFee) {
            withdrawFeeBP = getWithdrawFee(pid, msg.sender);
        }

        //track withdrawal for profit tracking
        withdrawals[pid][to] += lpToSend;
        //tell strategy to withdraw lpTokens, send to 'to', and process update
        pool.strategy.withdraw(
            msg.sender,
            to,
            lpToSend,
            amountShares,
            withdrawFeeBP
        );

        //track removed shares
        user.amount = user.amount - amountShares;
        uint256 rewardDebtOfShares = ((amountShares * pool.accEarningPerShare) /
            ACC_EARNING_PRECISION);
        user.rewardDebt = accumulatedEarnings - rewardDebtOfShares;
        pool.totalShares = pool.totalShares - amountShares;

        //handle rewards
        if (pendings > 0) {
            safeEarningsTransfer(to, pendings);
            payReferralCommission(msg.sender, pendings);
        }

        emit Withdraw(msg.sender, pid, amountShares, to);
        emit Harvest(msg.sender, pid, pendings);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(
        uint256 pid,
        address to
    ) external onlyApprovedContractOrEOA {
        //skip pool update
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amountShares = user.amount;
        //find amount of LP tokens from shares
        uint256 lpFromShares = (amountShares * pool.lpPerShare) /
            ACC_EARNING_PRECISION;

        uint256 withdrawFeeBP;
        if (pool.isWithdrawFee) {
            withdrawFeeBP = getWithdrawFee(pid, msg.sender);
        }

        //track withdrawal for profit tracking
        withdrawals[pid][to] += lpFromShares;
        //tell strategy to withdraw lpTokens, send to 'to', and process update
        pool.strategy.emergencyWithdraw(
            msg.sender,
            to,
            lpFromShares,
            amountShares,
            withdrawFeeBP
        );

        //track removed shares
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalShares = pool.totalShares - amountShares;

        emit EmergencyWithdraw(msg.sender, pid, amountShares, to);
    }

    //OWNER-ONLY FUNCTIONS
    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param _allocPoint AP of the new pool.
    /// @param _want Address of the LP ERC-20 token.
    /// @param _withUpdate True if massUpdatePools should be called prior to pool updates.
    function add(
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP,
        IERC20 _want,
        bool _withUpdate,
        bool _isWithdrawFee,
        IStrategy _strategy
    ) external onlyOwner {
        require(
            _depositFeeBP <= MAX_DEPOSIT_FEE_BP,
            "add: invalid deposit fee basis points"
        );
        require(
            _withdrawFeeBP <= MAX_WITHDRAW_FEE_BP,
            "add: invalid withdraw fee basis points"
        );

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                want: _want,
                strategy: _strategy,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accEarningPerShare: 0,
                depositFeeBP: _depositFeeBP,
                withdrawFeeBP: _withdrawFeeBP,
                isWithdrawFee: _isWithdrawFee,
                totalShares: 0,
                lpPerShare: ACC_EARNING_PRECISION
            })
        );
    }

    /// @notice Update the given pool's reward allocation point, withdrawal fee, and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _withUpdate True if massUpdatePools should be called prior to pool updates.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP,
        bool _withUpdate,
        bool _isWithdrawFee
    ) external onlyOwner {
        require(
            _depositFeeBP <= MAX_DEPOSIT_FEE_BP,
            "add: invalid deposit fee basis points"
        );
        require(
            _withdrawFeeBP <= MAX_WITHDRAW_FEE_BP,
            "add: invalid withdraw fee basis points"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint =
            (totalAllocPoint - poolInfo[_pid].allocPoint) +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].withdrawFeeBP = _withdrawFeeBP;
        poolInfo[_pid].isWithdrawFee = _isWithdrawFee;
    }

    //used to migrate an monopoly from using one strategy to another
    function migrateStrategy(
        uint256 pid,
        IStrategy newStrategy
    ) external onlyOwner {
        PoolInfo storage pool = poolInfo[pid];
        //migrate funds from old strategy to new one
        pool.strategy.migrate(address(newStrategy));
        //update strategy in storage
        pool.strategy = newStrategy;
        newStrategy.onMigration();
    }

    //used in emergencies, or if setup of an monopoly fails
    function setStrategy(
        uint256 pid,
        IStrategy newStrategy,
        bool transferOwnership,
        address newOwner
    ) external onlyOwner {
        PoolInfo storage pool = poolInfo[pid];
        if (transferOwnership) {
            pool.strategy.transferOwnership(newOwner);
        }
        pool.strategy = newStrategy;
    }

    function manualMint(address dest, uint256 amount) external onlyOwner {
        earningToken.mint(dest, amount);
    }

    // function transferMinter(address newMinter) external onlyOwner {
    //     require(newMinter != address(0));
    //     earningToken.transferOwnership(newMinter);
    // }

    function setDev(address _dev) external onlyOwner {
        require(_dev != address(0));
        emit DevSet(dev, _dev);
        dev = _dev;
    }

    function setPerfomanceFeeAddress(
        address _performanceFeeAddress
    ) external onlyOwner {
        require(_performanceFeeAddress != address(0));
        emit PerformanceFeeAddressSet(
            performanceFeeAddress,
            _performanceFeeAddress
        );
        performanceFeeAddress = _performanceFeeAddress;
    }

    function setActionFeeAddress(address _actionFeeAddress) external onlyOwner {
        require(_actionFeeAddress != address(0));

        actionFeeAddress = _actionFeeAddress;
    }

    function setDevMintBips(uint256 _devMintBips) external onlyOwner {
        require(
            _devMintBips <= MAX_BIPS,
            "combined dev & nest splits too high"
        );
        devMintBips = _devMintBips;
    }

    function setEarningsEmission(
        uint256 newEarningsPerSecond,
        bool withUpdate
    ) external onlyOwner {
        if (withUpdate) {
            massUpdatePools();
        }
        earningsPerSecond = newEarningsPerSecond;
    }

    //ACCESS CONTROL FUNCTIONS
    function modifyApprovedContracts(
        address[] calldata contracts,
        bool[] calldata statuses
    ) external onlyOwner {
        require(contracts.length == statuses.length, "input length mismatch");
        for (uint256 i = 0; i < contracts.length; i++) {
            approvedContracts[contracts[i]] = statuses[i];
        }
    }

    function setOnlyApprovedContractOrEOAStatus(
        bool newStatus
    ) external onlyOwner {
        onlyApprovedContractOrEOAStatus = newStatus;
    }

    //STRATEGY MANAGEMENT FUNCTIONS
    function inCaseTokensGetStuck(
        uint256 pid,
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.inCaseTokensGetStuck(token, to, amount);
    }

    function setAllowances(uint256 pid) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.setAllowances();
    }

    function revokeAllowance(
        uint256 pid,
        address token,
        address spender
    ) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.revokeAllowance(token, spender);
    }

    function setPerformanceFeeBips(
        uint256 pid,
        uint256 newPerformanceFeeBips
    ) external onlyOwner {
        IStrategy strat = poolInfo[pid].strategy;
        strat.setPerformanceFeeBips(newPerformanceFeeBips);
    }

    //INTERNAL FUNCTIONS
    // Safe reward transfer function, just in case if rounding error causes pool to not have enough earnings.
    function safeEarningsTransfer(address _to, uint256 _amount) internal {
        uint256 earningsBal = earningToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > earningsBal) {
            earningToken.mint(address(this), _amount - earningsBal);
        }
        transferSuccess = earningToken.transfer(_to, _amount);
        require(transferSuccess, "safeEarningsTransfer: transfer failed");
    }

    // 선형으로 변경
    function getWithdrawFee(
        uint256 _pid,
        address _user
    ) public view returns (uint16) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        if (!pool.isWithdrawFee) return 0;
        uint256 elapsed = block.timestamp - user.lastDepositTimestamp;

        uint16 deductionFee = uint16(
            ((elapsed * 1e18) * pool.withdrawFeeBP) / MAX_LINEAR_DURATION / 1e18
        );
        if (deductionFee > pool.withdrawFeeBP) return 0; // MAX - DEDUCTABLE
        return pool.withdrawFeeBP - deductionFee;
    }

    function setWithdrawalDuration(
        uint256 _maxLenearDuration
    ) public onlyOwner {
        MAX_LINEAR_DURATION = _maxLenearDuration;
    }

    // Update the earning referral contract address by the owner
    function setEarningsReferral(
        IEarningsReferral _earningReferral
    ) public onlyOwner {
        earningReferral = _earningReferral;
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(
        uint16 _referralCommissionRate
    ) public onlyOwner {
        require(
            _referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE,
            "setReferralCommissionRate: invalid referral commission rate basis points"
        );
        referralCommissionRate = _referralCommissionRate;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (
            address(earningReferral) != address(0) && referralCommissionRate > 0
        ) {
            address referrer = earningReferral.getReferrer(_user);
            uint256 commissionAmount = (_pending * referralCommissionRate) /
                10000;

            if (referrer != address(0) && commissionAmount > 0) {
                earningToken.mint(referrer, commissionAmount);
                earningReferral.recordReferralCommission(
                    referrer,
                    commissionAmount
                );
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }
}

