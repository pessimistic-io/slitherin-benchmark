// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IWETH.sol";

import "./IStrategy.sol";
import "./IPermit.sol";
import "./WETHelper.sol";
import "./AntiFlashload.sol";

interface IMint {
    function mint(address _to, uint256 _amount) external;
}
interface IBot {
    function _setBot(address _from, bool _value) external;
}

contract VaultFarm is Ownable, ReentrancyGuard, AntiFlashload {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 shares;
        uint256 update;
        uint256 mode;  // the current strat mode, 0 | 1 | 2
        uint256 rewardDebt; // Reward debt. See explanation below.

        // We do some fancy math here. Basically, any point in time, the amount of Sushi
        // entitled to a user but is pending to be distributed is:
        //
        //   amount = user.shares / sharesTotal * wantLockedTotal
        //   pending reward = (amount * pool.accSushiPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws want tokens to a pool. Here's what happens:
        //   1. The pool's `accSushiPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    uint256 public constant depositFeeFactorMax = 100;
    uint256 public constant withdrawFeeFactorMax = 100;

    uint256 public constant STRAT_MODE_NONE = 0;
    uint256 public constant STRAT_MODE_MORE_LP = 1;
    uint256 public constant STRAT_MODE_MORE_EARN = 2;
    struct PoolInfo {
        IERC20 lpToken; // Address of the want token.
        uint256 allocPoint; // How many allocation points assigned to this pool. Sushi to distribute per block.
        uint256 lastRewardBlock;
        uint256 accSushiPerShare;
        uint256 accInterestPerShare;
        uint256 depositFee; // default is 0%.
        uint256 withdrawFee; // default is 0%.
        uint256 amount;
        uint256 reserve;
        address strat0; // Strategy mode0 STRAT_MODE_MORE_LP
        address strat1; // Strategy mode1 STRAT_MODE_MORE_EARN
    }

    address public sushi;
    uint256 public sushiPerBlock;
    // Bonus muliplier for early impulse makers.
    uint256 public constant BONUS_MULTIPLIER = 2;
    uint256 public startBlock;
    uint256 public bonusEndBlock;
    uint256 public bonusEndBlock1;
    address public devaddr;
    address public WETH;
    // ETH Helper for the transfer, stateless.
    WETHelper public wethelper;

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    uint256 public totalAllocPoint = 0; // Total allocation points. Must be the sum of all allocation points in all pools.

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 shares);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, uint256 shares);
    event DepositRewards(address indexed user, uint256 indexed pid, uint256 amount);

    function initialize(
        address _sushi,
        address _devaddr,
        address _weth,
        uint256 _sushiPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _bonusEndBlock1
    ) public initializer {
        Ownable.__Ownable_init();
        AntiFlashload.__Flashload_init(1);
        sushi = _sushi;
        devaddr = _devaddr;
        WETH = _weth;
        sushiPerBlock = _sushiPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        bonusEndBlock1 = _bonusEndBlock1;
        wethelper = new WETHelper();
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        address _want,
        bool _withUpdate,
        uint256 _depositFee,
        uint256 _withdrawFee,
        address _strat0,
        address _strat1
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.timestamp > startBlock ? block.timestamp : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        require(_depositFee < depositFeeFactorMax && _withdrawFee < withdrawFeeFactorMax,
                "!deposit/withdraw fee");
        poolInfo.push(
            PoolInfo({
                lpToken: IERC20(_want),
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accSushiPerShare: 0,
                accInterestPerShare: 0,
                depositFee: _depositFee,
                withdrawFee: _withdrawFee,
                amount:0,
                reserve:0,
                strat0: _strat0,
                strat1: _strat1
            })
        );
    }

    // Update the given pool's Impulse allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate,
        uint256 _depositFee,
        uint256 _withdrawFee
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        require(_depositFee < depositFeeFactorMax && _withdrawFee < withdrawFeeFactorMax,
                "!deposit/withdraw fee");
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFee = _depositFee;
        poolInfo[_pid].withdrawFee = _withdrawFee;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from <= bonusEndBlock && _to >= bonusEndBlock && _to <= bonusEndBlock1
        ) {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(_to.sub(bonusEndBlock));
        } else if (_from >= bonusEndBlock && _to <= bonusEndBlock1) {
            return _to.sub(_from);
        } else if (_from > bonusEndBlock && _to > bonusEndBlock1) {
            return bonusEndBlock1.sub(_from).add(_to.sub(bonusEndBlock1).div(5));
        } else if (_from >= bonusEndBlock1) {
            return _to.sub(_from).div(5);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(bonusEndBlock1.sub(bonusEndBlock)).add(
            	_to.sub(bonusEndBlock1).div(5));
        }
    }

    function pendingToken(uint256 _pid, address _user)
        external
        view
        returns (uint256, IStrategy.EarnInfo[] memory)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSushiPerShare = pool.accSushiPerShare;
        uint256 sharesTotal = _sharesTotal(pool);
        if (block.timestamp > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.timestamp);
            uint256 sushiReward =
                multiplier.mul(sushiPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accSushiPerShare = accSushiPerShare.add(
                sushiReward.mul(1e12).div(sharesTotal)
            );
        }
        uint256 pending = user.shares.mul(accSushiPerShare).div(1e12).sub(user.rewardDebt);
        IStrategy.EarnInfo[] memory earnPending = _UserStrategy(pool, user).pendingEarn(_user);

        return (pending, earnPending);
    }

    function harvest(PoolInfo storage pool, UserInfo storage user) internal returns (uint256) {
        uint256 pending;
        if (user.shares > 0) {
            pending =
                user.shares.mul(pool.accSushiPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                safeSushiTransfer(msg.sender, pending);
            }
        }
        return pending;
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        IStrategy strat = _UserStrategy(pool, user);

        (uint256 wantLockedTotal, uint256 sharesTotal) = strat.sharesInfo();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function _sharesTotal(PoolInfo storage pool) internal view returns (uint256 sharesTotal) {
        if (pool.strat0 != address(0)) {
            sharesTotal += IStrategy(pool.strat0).sharesTotal();
        }
        if (pool.strat1 != address(0)) {
            sharesTotal += IStrategy(pool.strat1).sharesTotal();
        }
    }

    function _UserStrategy(PoolInfo storage pool, UserInfo storage user) internal view returns (IStrategy) {
        if (user.mode == STRAT_MODE_MORE_LP) {
            return IStrategy(pool.strat0);
        } else if (user.mode == STRAT_MODE_MORE_EARN) {
            return IStrategy(pool.strat1);
        }
        return IStrategy(address(0));
    }
    function UserStrategy(uint256 _pid, address _user) external view returns (IStrategy) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        return _UserStrategy(pool, user);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardBlock) {
            return;
        }
        uint256 sharesTotal = _sharesTotal(pool);
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.timestamp);
        if (multiplier <= 0) {
            return;
        }
        uint256 sushiReward =
            multiplier.mul(sushiPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );

        //IMint(sushi).mint(address(this), sushiReward);
        mint(address(this), sushiReward);

        pool.accSushiPerShare = pool.accSushiPerShare.add(
            sushiReward.mul(1e12).div(sharesTotal)
        );
        pool.lastRewardBlock = block.timestamp;
    }

    function changeMode(uint256 _pid, uint256 _newMode) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IStrategy strat = _UserStrategy(pool, user);
        require(_newMode != STRAT_MODE_NONE, "new strat mode is none!");
        require(_newMode != user.mode, "new strat mode is same with old!");

        updatePool(_pid);

        if (user.mode == STRAT_MODE_NONE) {
            user.mode = _newMode;
            return;
        }
        if (user.shares == 0) {
            return;
        }

        // harvest(pool, user);
        // transfer the earn token if have

        // withdraw all
        (uint256 wantLockedTotal, uint256 sharesTotal) = strat.sharesInfo();

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        strat.withdraw(msg.sender, amount);
        strat.onRewardEarn(msg.sender, 0);

        // Deposit again
        user.mode = _newMode;
        strat = _UserStrategy(pool, user);
        uint256 wantBal = IERC20(pool.lpToken).balanceOf(address(this));

        if (wantBal > 0) {
            pool.lpToken.safeApprove(address(strat), wantBal);
            uint256 sharesAdded = strat.deposit(msg.sender, wantBal);

            user.shares = sharesAdded;
            user.amount = wantBal;
            user.update = block.timestamp;
            strat.onRewardEarn(msg.sender, user.shares);
        }

        user.rewardDebt = user.shares.mul(pool.accSushiPerShare).div(1e12);
    }

    // Want tokens moved from user -> Sushi Farm (Impulse allocation) -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt, uint256 _mode)
        public
        payable
        enterFlashload(_pid)
        nonReentrant
    {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
		harvest(pool, user);

        if (user.mode == STRAT_MODE_NONE) {
            user.mode = _mode;
        }
        if (msg.value > 0) {
            IWETH(WETH).deposit{value: msg.value}();
        }
        if (address(pool.lpToken) == WETH) {
            if(_wantAmt > 0) {
                pool.lpToken.safeTransferFrom(msg.sender, address(this), _wantAmt);
            }
            if (msg.value > 0) {
                _wantAmt = _wantAmt.add(msg.value);
            }
        } else if(_wantAmt > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _wantAmt);
        }
        IStrategy strat = _UserStrategy(pool, user);
        uint256 sharesAdded;
        uint256 buybackAmount;
        if (_wantAmt > 0) {
            buybackAmount = _wantAmt.mul(pool.depositFee).div(1000);
            if (buybackAmount > 0) {
                pool.lpToken.safeTransfer(devaddr, buybackAmount);
                _wantAmt = _wantAmt.sub(buybackAmount);
            }

            pool.lpToken.safeApprove(address(strat), _wantAmt);
            sharesAdded = strat.deposit(msg.sender, _wantAmt);

            user.shares = user.shares.add(sharesAdded);
            user.amount = user.amount.add(_wantAmt);
            user.update = block.timestamp;


		}
        user.rewardDebt = user.shares.mul(pool.accSushiPerShare).div(1e12);

        // transfer the earn token if have
        strat.onRewardEarn(msg.sender, user.shares);

        emit Deposit(msg.sender, _pid, _wantAmt, sharesAdded);
    }
    function depositWithPermit(uint256 _pid, uint256 _wantAmt, uint256 _mode,
        uint256 deadline, uint256 value, uint8 v, bytes32 r, bytes32 s)
        public
        payable
    {
        PoolInfo storage pool = poolInfo[_pid];
        IPermit(address(pool.lpToken)).permit(msg.sender, address(this), value, deadline, v, r, s);
        deposit(_pid, _wantAmt, _mode);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt)
        public
        leaveFlashload(_pid)
        nonReentrant
    {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IStrategy strat = _UserStrategy(pool, user);

        (uint256 wantLockedTotal, uint256 sharesTotal) = strat.sharesInfo();
        

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw pending Sushi
		harvest(pool, user);

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        require(_wantAmt <= amount, "withdraw: not good");
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        uint256 buybackAmount;
        uint256 sharesRemoved;
        if (_wantAmt > 0) {
            sharesRemoved = strat.withdraw(msg.sender, _wantAmt);

            // set shares to zero once _wantAmt == amount (means withdraw all of token)
            if (sharesRemoved > user.shares || _wantAmt == amount) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            uint256 wantBal = IERC20(pool.lpToken).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            if (user.amount > _wantAmt) {
				user.amount = user.amount.sub(_wantAmt);
            } else {
				user.amount = 0;
            }


            buybackAmount = _wantAmt.mul(pool.withdrawFee).div(1000);
            if (buybackAmount > 0) {
                pool.lpToken.safeTransfer(devaddr, buybackAmount);
                _wantAmt = _wantAmt.sub(buybackAmount);
            }

            if (address(pool.lpToken) == WETH) {
                withdrawEth(address(msg.sender), _wantAmt, false);
            } else {
                pool.lpToken.safeTransfer(address(msg.sender), _wantAmt);
            }

		}

        user.rewardDebt = user.shares.mul(pool.accSushiPerShare).div(1e12);
        // transfer the earn token if have
        strat.onRewardEarn(msg.sender, user.shares);

        if (user.shares == 0) {
            user.mode = STRAT_MODE_NONE;
        }

        emit Withdraw(msg.sender, _pid, _wantAmt, sharesRemoved);
    }

    function withdrawAll(uint256 _pid) external
    {
        withdraw(_pid, type(uint256).max);
    }

    // Safe Sushi transfer function, just in case if rounding error causes pool to not have enough
    function safeSushiTransfer(address _to, uint256 _amt) internal {
        uint256 bal = IERC20(sushi).balanceOf(address(this));
        if (_amt > bal) {
            IERC20(sushi).transfer(_to, bal);
        } else {
            IERC20(sushi).transfer(_to, _amt);
        }
    }
    function withdrawEth(address _to, uint256 _amount, bool _isWeth) internal {
        bool isInProxy = true;
        if (_isWeth) {
            IERC20(WETH).safeTransfer(_to, _amount);
        } else if (isInProxy) {
            IERC20(WETH).safeTransfer(address(wethelper), _amount);
            wethelper.withdraw(WETH, _to, _amount);
        } else {
            IWETH(WETH).withdraw(_amount);
            (bool success,) = _to.call{value:_amount}(new bytes(0));
            require(success, '!WETHelper: ETH_TRANSFER_FAILED');
        }
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock)
        external
        onlyOwner
    {
        startBlock = _startBlock;
    }
    function updateEndBlock(uint256 _endBlock)
        external
        onlyOwner
    {
        bonusEndBlock = _endBlock;
    }
    function setSushiPerBlk(uint256 _sushiPerBlock)
        public
        onlyOwner
    {
        sushiPerBlock = _sushiPerBlock;
    }

    function setFlashloadBlk(uint256 _flashloadBlk)
        public
        onlyOwner
    {
        flashloadBlk = _flashloadBlk;
    }

    function userInfo2(uint256 _pid, address _user)
        view
        external
        returns (uint256, uint256, uint256, uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        IStrategy strat = _UserStrategy(pool, user);

        (uint256 wantLockedTotal, uint256 sharesTotal) = strat.sharesInfo();
        uint256 realAmount = 0;
        if (sharesTotal > 0) {
            realAmount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        }
        return (user.amount, realAmount, user.shares, user.update);
    }

    function poolInfo2(uint256 _pid)
        view
        external
        returns (address lpToken, uint256 allocPoint,
            address strat0, uint256 amount0, uint256 share0,
            address strat1, uint256 amount1, uint256 share1)
    {
        PoolInfo storage pool = poolInfo[_pid];
        lpToken = address(pool.lpToken);
        allocPoint = pool.allocPoint;
        strat0 = pool.strat0;
        strat1 = pool.strat1;
        if (pool.strat0 != address(0)) {
            (amount0, share0) = IStrategy(pool.strat0).sharesInfo();
        }
        if (pool.strat1 != address(0)) {
            (amount1, share1) = IStrategy(pool.strat1).sharesInfo();
        }
    }


    function mint(address to, uint256 rewardAmount) internal {
        if (rewardAmount == 0) {
            //emit Mint(to, 0);
            return;
        }
        //emit Mint(to, rewardAmount);
    }
}

