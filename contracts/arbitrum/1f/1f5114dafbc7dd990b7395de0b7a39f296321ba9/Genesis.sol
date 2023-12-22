// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

interface ITradingHelper {

    function profitTax() external view returns (uint256);
    function fundsBackTax() external view  returns (uint256);
    function isAutoEnder(address autoEnder) external view  returns (bool);
    function getMaxBorrowAmount(uint256 pid) external view  returns (uint256);
    function getMaxMultiplier(uint256 pid) external view  returns (uint256);
    function getETHprice() external view returns (uint256);
    function SwapToWETH(uint256 inAmount) external returns (uint256 outAmount);
    function getEstimateWETH(uint256 inAmount) external view returns (uint256 estOutAmount);
    function SwapWETH(uint256 inAmount) external returns (uint256 outAmount);
    function getEstimateUSDC(uint256 inAmount) external view returns (uint256 estOutAmount);
}

interface IReferalHelper {

    function totalReferNum() external view returns (uint256);
    function totalReferProfitInUSDC() external view  returns (uint256);
    function totalReferProfitInWETH() external view  returns (uint256);
    function addReferWETHAmount(address depositor, address referrer, address token, uint256 amount) external;
    function addReferUSDCAmount(address depositor, address referrer, address token, uint256 amount) external;
}

// Note that this pool has no minter key of HOPE (rewards).
// Instead, the governance will call HOPE distributeReward method and send reward to this pool at the beginning.
contract GenesisRewardPool is ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        bool isTrading;
        int256 totalProfit;
        uint256 currentTradeId;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. HOPE to distribute.
        uint256 lastRewardTime; // Last time that HOPE distribution occurs.
        uint256 accRewardPerShare; // Accumulated HOPE per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
        uint256 depositFeeBP;
        uint256 minAmountFortrading;
        uint256 totalDepositAmount;
    }

    IERC20 public hope;
    address public daoAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => uint256) public investAmount;
        
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when HOPE mining starts.
    uint256 public poolStartTime;

    // The time when HOPE mining ends.
    uint256 public poolEndTime;

    uint256 public hopePerSecond =  0.0496 ether; // 30000 HOPE / (24 * 7 * 60min * 60s)
    uint256 public runningTime =  7 days;
    uint256 public constant TOTAL_REWARDS = 30000 ether;
    
    // For Leverage Trading
    struct Trade {
        uint256 id;
        address user;
        uint256 pid;
        bool isTrading;
        uint256 borrowAmount;
        uint256 swappedAmount;
        uint256 returnAmount;
        uint256 startPrice;
        uint256 endPrice;
        uint256 limitPrice;
        int256 profit;
        uint256 startTime;
        uint256 endTime;
    }

    struct TradeInfo {
        uint256 totalBorrowedAmount;
        uint256 totalReturnedAmount;
        uint256 feeAmount;
        uint256 totalProfit;
        uint256 totalLoss;
        uint256 count;
        uint256 lastTradeEndTime;
    }

    mapping(uint256 => Trade) public trades;
    mapping(uint256 => TradeInfo) public tradeInfos;

    uint256 public feeDenominator = 10000;
    uint256 public tradeCount = 0;
    ITradingHelper public tradingHelper;
    IReferalHelper public referalHelper;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _hope,
        uint256 _poolStartTime,
        address _tradingHelper,
        address _referalHelper
    ) {
        require(block.timestamp < _poolStartTime, "late");
        if (_hope != address(0)) hope = IERC20(_hope);
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
        daoAddress = msg.sender;
        tradingHelper = ITradingHelper(_tradingHelper);
        referalHelper = IReferalHelper(_referalHelper);
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "RewardGenesisPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "RewardGenesisPool: existing pool?");
        }
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime,
        uint256 _depositFeeBP,
        uint256 _minAmountFortrading
    ) external onlyOperator nonReentrant {
        require(_depositFeeBP <= 100, "add: invalid deposit fee basis points");
        checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }
        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }
        bool _isStarted =
        (_lastRewardTime <= poolStartTime) ||
        (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
            token : _token,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accRewardPerShare : 0,
            isStarted : _isStarted,
            depositFeeBP: _depositFeeBP,
            minAmountFortrading: _minAmountFortrading,
            totalDepositAmount: 0
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's HOPE allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFeeBP, uint256 _minAmountFortrading) external onlyOperator nonReentrant {
        require(_depositFeeBP <= 100, "set: invalid deposit fee basis points");
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].minAmountFortrading = _minAmountFortrading;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(hopePerSecond);
            return poolEndTime.sub(_fromTime).mul(hopePerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(hopePerSecond);
            return _toTime.sub(_fromTime).mul(hopePerSecond);
        }
    }

    // View function to see pending HOPE on frontend.
    function pendingHOPE(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 tokenSupply = pool.totalDepositAmount;
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _hopeReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(_hopeReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
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
        uint256 tokenSupply = pool.totalDepositAmount;
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _hopeReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accRewardPerShare = pool.accRewardPerShare.add(_hopeReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) external nonReentrant {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeRewardTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalDepositAmount = pool.totalDepositAmount.add(_amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(feeDenominator);
                user.amount = user.amount.sub(depositFee);
                pool.totalDepositAmount = pool.totalDepositAmount.sub(depositFee);

                if(_amount >= pool.minAmountFortrading && _referrer != address(0) && _referrer != msg.sender) {

                    uint256 referFee = depositFee.div(2);
                    pool.token.safeTransfer(_referrer, referFee);

                    if(_pid == 0) {
                        referalHelper.addReferWETHAmount(msg.sender, _referrer, address(pool.token), referFee);
                    } else {
                        referalHelper.addReferUSDCAmount(msg.sender, _referrer, address(pool.token), referFee);
                    }
                    depositFee = depositFee.sub(referFee);
                }
                pool.token.safeTransfer(daoAddress, depositFee);
            }
        }

        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        require(!user.isTrading, "withdraw: you are trading now, end trade first");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeRewardTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalDepositAmount = pool.totalDepositAmount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if(user.isTrading) {
            endTrade(user.currentTradeId);
        }
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalDepositAmount = pool.totalDepositAmount.sub(_amount);
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe HOPE transfer function, just in case if rounding error causes pool to not have enough HOPEs.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 _hopeBalance = hope.balanceOf(address(this));
        if (_hopeBalance > 0) {
            if (_amount > _hopeBalance) {
                hope.safeTransfer(_to, _hopeBalance);
            } else {
                hope.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setDaoAddress(address _daoAddress) external{
        require(msg.sender == daoAddress, "setDaoAddress: FORBIDDEN");
        require(_daoAddress != address(0), "setDaoAddress: ZERO");
        daoAddress = _daoAddress;
    }

    function invest(address _token, uint256 _amount) external {
        require(msg.sender == daoAddress, "invest: FORBIDDEN");
        investAmount[_token] = investAmount[_token].add(_amount);
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function getInvestAmount(address _token) external {
        require(msg.sender == daoAddress, "invest: FORBIDDEN");
        require(investAmount[_token] > 0, "invest first");
        uint256 getAmount = investAmount[_token];
        investAmount[_token] = 0;
        require(IERC20(_token).balanceOf(address(this)) >= getAmount, 'balance');
        IERC20(_token).safeTransfer(msg.sender, getAmount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (HOPE or lps) if less than 90 days after pool ends
            require(_token != hope, "hope");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }

    function updateTradingHelper(address _tradingHelper) external onlyOperator {
        require(_tradingHelper != address(0), "invalid address");
        tradingHelper = ITradingHelper(_tradingHelper);
    }

    function updateReferalHelper(address _referalHelper) external onlyOperator {
        require(_referalHelper != address(0), "invalid address");
        referalHelper = IReferalHelper(_referalHelper);
    }

    function openTrade(uint256 _pid, uint256 _borrowAmount, uint256 _limitPrice) external nonReentrant {
        require(block.timestamp < poolEndTime.sub(1 hours), "leverage trading is disabled");
        address _trader = msg.sender;
        // _pid = 0: weth pool, _pid = 1: usdc pool
        // _pid = 0 ? short : long
        require(_pid < 2, "wrong pool id");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_trader];
        TradeInfo storage tradeInfo = tradeInfos[_pid];

        require(!user.isTrading, "already started one trading");
        require(user.amount.mul(feeDenominator).div(feeDenominator.sub(pool.depositFeeBP)) >= pool.minAmountFortrading, "need to deposit min amount for trading");
        require(user.amount.mul(tradingHelper.getMaxMultiplier(_pid)) >= _borrowAmount, "exceed max multiplier");
        
        uint256 borrowableAmount = getBorrowableAmount(_pid);
        require(_borrowAmount <= borrowableAmount, "wrong borrow amount for trade");
        require(_borrowAmount >= user.amount, "wrong borrow amount");

        tradeInfo.totalBorrowedAmount = tradeInfo.totalBorrowedAmount.add(_borrowAmount);

        uint256 swappedAmount = 0;
        uint256 liqPrice = 0;

        pool.token.safeIncreaseAllowance(address(tradingHelper), _borrowAmount);
        if(_pid == 1) {
            swappedAmount = tradingHelper.SwapToWETH(_borrowAmount);
            liqPrice = _borrowAmount.sub(user.amount).mul(1e14).div(swappedAmount);
            liqPrice = liqPrice.mul(105).div(100);
        } else {
            swappedAmount = tradingHelper.SwapWETH(_borrowAmount);
            liqPrice = swappedAmount.mul(1e14).div(_borrowAmount.sub(user.amount));
            liqPrice = liqPrice.mul(95).div(100);
        }

        uint256 startPrice = tradingHelper.getETHprice();
        
        user.isTrading = true;
        user.currentTradeId = tradeCount;
        trades[tradeCount] = Trade(
            tradeCount,
            msg.sender,
            _pid,
            true,
            _borrowAmount,
            swappedAmount,
            0,
            startPrice,
            liqPrice,
            _limitPrice,
            0,
            block.timestamp,
            0
        );
        tradeCount = tradeCount + 1;
        tradeInfo.count = tradeInfo.count + 1;
    }

    function getBorrowableAmount(uint256 _pid) public view returns(uint256) {
        TradeInfo storage tradeInfo = tradeInfos[_pid];
        PoolInfo storage pool = poolInfo[_pid];
        uint256 available = pool.totalDepositAmount.add(tradeInfo.totalReturnedAmount).sub(tradeInfo.totalBorrowedAmount).add(investAmount[address(pool.token)]);
        uint256 maxAmount = tradingHelper.getMaxBorrowAmount(_pid);
        return available >= maxAmount ? maxAmount : available;
    }

    function getEstLiqudationPrice(uint256 _pid, uint256 _borrowAmount, uint256 _collateralAmount) public view returns(uint256) {
        uint256 estimateSwapAmount = 0;
        require(_borrowAmount >= _collateralAmount, "wrong borrow amount");
        if(_pid == 0) {
            estimateSwapAmount = tradingHelper.getEstimateUSDC(_borrowAmount);
            return estimateSwapAmount.mul(1e14).div(_borrowAmount.sub(_collateralAmount));
        } else {
            estimateSwapAmount = tradingHelper.getEstimateWETH(_borrowAmount);
            return _borrowAmount.sub(_collateralAmount).mul(1e14).div(estimateSwapAmount);
        }
    }

    function getBorrowFee(uint256 _tradeId) public view returns(uint256) {
        Trade storage trade = trades[_tradeId];
        uint256 endTime = trade.endTime;
        if(trade.isTrading) {
            endTime = block.timestamp;
        }
        uint256 fee = trade.borrowAmount.mul(endTime.sub(trade.startTime)).mul(tradingHelper.fundsBackTax()).div(1 days).div(feeDenominator);
        return fee;
    }

    function endTrade(uint256 _tradeId) public {
        Trade storage trade = trades[_tradeId];
        require(msg.sender == trade.user || tradingHelper.isAutoEnder(msg.sender), "wrong permission");
        // _pid = 0: weth pool, _pid = 1: usdc pool
        // _pid = 0 ? short : long
        require(trade.pid < 2, "wrong pool id");
        PoolInfo storage pool = poolInfo[trade.pid];
        UserInfo storage user = userInfo[trade.pid][trade.user];
        TradeInfo storage tradeInfo = tradeInfos[trade.pid];

        require(user.isTrading, "not started yet");
        require(trade.isTrading, "not started yet");

        uint256 lastAmount;

        if(trade.pid == 1) {
            poolInfo[0].token.safeIncreaseAllowance(address(tradingHelper), trade.swappedAmount);
            lastAmount = tradingHelper.SwapWETH(trade.swappedAmount);
        } else {
            poolInfo[1].token.safeIncreaseAllowance(address(tradingHelper), trade.swappedAmount);
            lastAmount = tradingHelper.SwapToWETH(trade.swappedAmount);
        }

        trade.returnAmount = lastAmount;
        trade.endPrice = tradingHelper.getETHprice();
        tradeInfo.totalReturnedAmount = tradeInfo.totalReturnedAmount.add(lastAmount);

        updatePool(trade.pid);
        uint256 _pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeRewardTransfer(trade.user, _pending);
            emit RewardPaid(trade.user, _pending);
        }

        uint256 borrowFee = getBorrowFee(_tradeId);
        uint256 feeAmount = 0;
        if(lastAmount >= trade.borrowAmount.add(borrowFee)) {
            uint256 profit = lastAmount.sub(trade.borrowAmount).sub(borrowFee);
            tradeInfo.totalProfit = tradeInfo.totalProfit.add(profit);
            uint256 profitFee = profit.mul(tradingHelper.profitTax()).div(feeDenominator);
            profit = profit.sub(profitFee);
            feeAmount = borrowFee.add(profitFee);
            if(profit > 0) {
                user.amount = user.amount.add(profit);
                user.totalProfit += int256(profit);
                trade.profit += int256(profit);
            }
        } else {
            uint256 loss = 0;
            if(lastAmount < trade.borrowAmount) {
                loss = trade.borrowAmount.sub(lastAmount);
                if(user.amount > loss) {
                    user.amount = user.amount.sub(loss);
                    if(user.amount > borrowFee) {
                        user.amount = user.amount.sub(borrowFee);
                        feeAmount = borrowFee;
                    } else {
                        feeAmount = user.amount;
                        user.amount = 0;
                    }
                } else {
                    user.amount = 0;
                }
                loss = loss.add(borrowFee);
            } else {
                loss = trade.borrowAmount.add(borrowFee).sub(lastAmount);
                if(user.amount > loss) {
                    user.amount = user.amount.sub(loss);
                    feeAmount = borrowFee;
                } else {
                    feeAmount = user.amount;
                    user.amount = 0;
                }
            }
            user.totalProfit -= int256(loss);
            tradeInfo.totalLoss = tradeInfo.totalLoss.add(loss);
            trade.profit -= int256(loss);
        }
        pool.token.safeTransfer(daoAddress, feeAmount);
        trade.endTime = block.timestamp;
        tradeInfo.feeAmount = tradeInfo.feeAmount.add(feeAmount);
        tradeInfo.lastTradeEndTime = block.timestamp;
        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        user.isTrading = false;
        trade.isTrading = false;
    }

    function needToEnd(uint256 _tradeId) public view returns (bool) {
        Trade storage trade = trades[_tradeId];
        // PoolInfo storage pool = poolInfo[trade.pid];
        UserInfo storage user = userInfo[trade.pid][trade.user];

        require(trade.isTrading, "not started yet");

        uint256 borrowFee = getBorrowFee(_tradeId);
        uint256 estimateAmount = 0;

        if(trade.pid == 0) {
            estimateAmount = tradingHelper.getEstimateWETH(trade.swappedAmount);
        } else {
            estimateAmount = tradingHelper.getEstimateUSDC(trade.swappedAmount);
        }

        if(estimateAmount.mul(95).div(100) <= trade.borrowAmount.add(borrowFee).sub(user.amount)){
            return true;
        } else {
            if(trade.limitPrice == 0) {
                return false;
            } else {
                if(trade.pid == 1) {
                    return trade.limitPrice <= tradingHelper.getETHprice();
                } else {
                    return trade.limitPrice >= tradingHelper.getETHprice();
                }
            }
        }
    }

    function getUserTradeInfo(uint256 _pid, address _account) external view returns(Trade memory) {
        UserInfo storage user = userInfo[_pid][_account];
        return trades[user.currentTradeId];
    }

    function getActiveTrades() public view returns(uint256[] memory) {
        uint256 count = 0;
        for(uint256 i = 0; i < tradeCount; i++) {
            if(trades[i].isTrading) {
                count += 1;
            }
        }
        uint256[] memory activeTrades = new uint256[](count);
        uint256 k = 0;
        for(uint256 i = 0; i < tradeCount; i++) {
            if(trades[i].isTrading) {
                activeTrades[k] = trades[i].id;
                k += 1;
            }
        }
        return activeTrades;
    }

    function getNeedToEndTrades() external view returns(uint256[] memory) {
        uint256[] memory activeTrades = getActiveTrades();
        uint256 count = 0;
        for(uint256 i = 0; i < activeTrades.length; i++) {
            if(needToEnd(activeTrades[i])) {
                count += 1;
            }
        }

        uint256[] memory needEndTrades = new uint256[](count);
        uint256 k = 0;
        for(uint256 i = 0; i < activeTrades.length; i++) {
            if(needToEnd(activeTrades[i])) {
                needEndTrades[k] = activeTrades[i];
                k += 1;
            }
        }
        return needEndTrades;
    }

    function getLatestEndTrades(uint256 length) external view returns(Trade[] memory) {
        uint256 tEndCount = 0;
        if(tradeCount < 1) {
            length = 0;
        } else {
            for(uint256 i = tradeCount; i > 0; i-- ){
                if(!trades[i-1].isTrading) {
                    tEndCount += 1;
                }
            }
            if(length > tEndCount) {
                length = tEndCount;
            }
        }
        Trade[] memory endTrades = new Trade[](length);
        if(length > 0) {
            uint256 k = 0;
            for(uint256 i = tradeCount; i > 0; i-- ){
                if(!trades[i-1].isTrading) {
                    endTrades[k] = trades[i-1];
                    k += 1;
                    if(k == length) {
                        break;
                    }
                }
            }
        }
        return endTrades;
    }
}
