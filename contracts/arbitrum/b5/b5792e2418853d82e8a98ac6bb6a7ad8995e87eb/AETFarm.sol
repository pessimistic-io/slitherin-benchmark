// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IWETH.sol";

import "./IStrategy.sol";
import "./WETHelper.sol";
import "./AntiFlashload.sol";

interface IMint {
    function mint(address _to, uint256 _amount) external;
}

contract AETFarm is Ownable, ReentrancyGuard, AntiFlashload {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 shares;
        uint256 update;
        uint256 rewardDebt; // Reward debt. See explanation below.

        // We do some fancy math here. Basically, any point in time, the amount of Sushi
        // entitled to a user but is pending to be distributed is:
        //
        //   amount = user.shares / sharesTotal * wantLockedTotal
        //   pending reward = (amount * pool.accTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws want tokens to a pool. Here's what happens:
        //   1. The pool's `accTokenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    uint256 public constant depositFeeFactorMax = 100; //10%
    uint256 public constant withdrawFeeFactorMax = 100; //10%

    uint256 public constant STRAT_MODE_NONE = 0;
    uint256 public constant STRAT_MODE_MORE_LP = 1;
    uint256 public constant STRAT_MODE_MORE_EARN = 2;

    uint256 public totalTokenPerBlock = 0;

    struct PoolInfo {
        IERC20 lpToken; // Address of the want token.
        uint256 tokenPerBlock;
        uint256 lastRewardBlock;
        uint256 accTokenPerShare;
        uint256 accInterestPerShare;
        uint256 depositFee; // default is 0%.
        uint256 withdrawFee; // default is 0%.
        address strat0; // Strategy mode0 STRAT_MODE_MORE_TOKEN
    }

    address public farmToken;
    // Bonus muliplier for early impulse makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    uint256 public startBlock;
    address public devaddr;
    address public WETH;
    // ETH Helper for the transfer, stateless.
    WETHelper public wethelper;

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    uint256 public totalAllocPoint = 0; // Total allocation points. Must be the sum of all allocation points in all pools.
    address[] public accounts;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 shares
    );
    event Withdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 shares
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event DepositRewards(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event Mint(address indexed to, uint256 amount);

    function initialize(
        address _farmToken,
        address _devaddr,
        address _weth
    ) public initializer {
        Ownable.__Ownable_init();
        AntiFlashload.__Flashload_init(1);
        farmToken = _farmToken;
        devaddr = _devaddr;
        WETH = _weth;
        wethelper = new WETHelper();
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function changeWeth(address _weth) public onlyOwner {
        WETH = _weth;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _tokenPerBlock,
        address _want,
        bool _withUpdate,
        uint256 _depositFee,
        uint256 _withdrawFee,
        address _strat0
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.timestamp > startBlock
            ? block.timestamp
            : startBlock;
        totalTokenPerBlock = totalTokenPerBlock.add(_tokenPerBlock);

        require(
            _depositFee < depositFeeFactorMax &&
                _withdrawFee < withdrawFeeFactorMax,
            "!deposit/withdraw fee"
        );
        poolInfo.push(
            PoolInfo({
                lpToken: IERC20(_want),
                tokenPerBlock: _tokenPerBlock,
                lastRewardBlock: lastRewardBlock,
                accTokenPerShare: 0,
                accInterestPerShare: 0,
                depositFee: _depositFee,
                withdrawFee: _withdrawFee,
                strat0: _strat0
            })
        );
    }

    function doCompound() public onlyOwner {
        uint256 length = poolLength();
        for (uint256 _pid = 0; _pid < length; ++_pid) {
            PoolInfo storage pool = poolInfo[_pid];
            IStrategy strat = _UserStrategy(pool);
            strat.earn();
        }
    }

    function doCompound1(uint _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        IStrategy strat = _UserStrategy(pool);
        strat.earn();
    }

    function setAccounts(address _user) internal {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == _user) {
                return;
            }
        }
        accounts.push(_user);
    }

    function isContract(address addr) public view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // Update the given pool's Impulse allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _tokenPerBlock,
        bool _withUpdate,
        uint256 _depositFee,
        uint256 _withdrawFee
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalTokenPerBlock = totalTokenPerBlock
            .sub(poolInfo[_pid].tokenPerBlock)
            .add(_tokenPerBlock);
        require(
            _depositFee < depositFeeFactorMax &&
                _withdrawFee < withdrawFeeFactorMax,
            "!deposit/withdraw fee"
        );
        poolInfo[_pid].tokenPerBlock = _tokenPerBlock;
        poolInfo[_pid].depositFee = _depositFee;
        poolInfo[_pid].withdrawFee = _withdrawFee;
    }

    function setToken(uint256 _pid, address _token) public onlyOwner {
        poolInfo[_pid].lpToken = IERC20(_token);
    }

    function setVault(uint256 _pid, address _strat0) public onlyOwner {
        poolInfo[_pid].strat0 = _strat0;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function pendingToken(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 sharesTotal = _sharesTotal(pool);
        if (block.timestamp > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.timestamp
            );
            uint256 tokenReward = multiplier.mul(pool.tokenPerBlock);
            accTokenPerShare = accTokenPerShare.add(
                tokenReward.mul(1e12).div(sharesTotal)
            );
        }
        uint256 pending = user.shares.mul(accTokenPerShare).div(1e12).sub(
            user.rewardDebt
        );

        return (pending);
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
        uint256 multiplier = getMultiplier(
            pool.lastRewardBlock,
            block.timestamp
        );
        if (multiplier <= 0) {
            return;
        }
        uint256 tokenReward = multiplier.mul(pool.tokenPerBlock);

        pool.accTokenPerShare = pool.accTokenPerShare.add(
            tokenReward.mul(1e12).div(sharesTotal)
        );
        pool.lastRewardBlock = block.timestamp;
    }

    function harvest(
        PoolInfo storage pool,
        UserInfo storage user
    ) internal returns (uint256) {
        uint256 pending;
        if (user.shares > 0) {
            pending = user.shares.mul(pool.accTokenPerShare).div(1e12).sub(
                user.rewardDebt
            );
            if (pending > 0) {
                safeFTokenTransfer(msg.sender, pending);
            }
        }
        return pending;
    }

    function harvestCToken(address _user, uint _pid) public {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        if (user.shares > 0) {
            IStrategy(pool.strat0).harvest(_user);
        }
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        IStrategy strat = _UserStrategy(pool);

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

    function _sharesTotal(
        PoolInfo storage pool
    ) internal view returns (uint256 sharesTotal) {
        if (pool.strat0 != address(0)) {
            sharesTotal += IStrategy(pool.strat0).sharesTotal();
        }
    }

    function _UserStrategy(
        PoolInfo storage pool
    ) internal view returns (IStrategy) {
        return IStrategy(pool.strat0);
    }

    function UserStrategy(uint256 _pid) external view returns (IStrategy) {
        PoolInfo storage pool = poolInfo[_pid];
        return _UserStrategy(pool);
    }

    function deposit(
        uint256 _pid,
        uint256 _wantAmt
    ) public payable enterFlashload(_pid) nonReentrant {
        require(!isContract(msg.sender));
        setAccounts(msg.sender);
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        harvest(pool, user);

        if (msg.value > 0) {
            IWETH(WETH).deposit{value: msg.value}();
        }
        if (address(pool.lpToken) == WETH) {
            if (_wantAmt > 0) {
                pool.lpToken.safeTransferFrom(
                    msg.sender,
                    address(this),
                    _wantAmt
                );
            }
            if (msg.value > 0) {
                _wantAmt = _wantAmt.add(msg.value);
            }
        } else if (_wantAmt > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _wantAmt);
        }
        IStrategy strat = _UserStrategy(pool);
        uint256 sharesAdded;
        uint256 buybackAmount;
        if (_wantAmt > 0) {
            buybackAmount = _wantAmt.mul(pool.depositFee).div(1000);
            if (buybackAmount > 0) {
                pool.lpToken.safeTransfer(devaddr, buybackAmount);
                _wantAmt = _wantAmt.sub(buybackAmount);
            }
            user.update = block.timestamp;
        }
        pool.lpToken.safeApprove(address(strat), _wantAmt);
        sharesAdded = strat.deposit(msg.sender, _wantAmt);
        // sharesAdded = _wantAmt;
        user.shares = user.shares.add(sharesAdded);
        user.amount = user.amount.add(_wantAmt);

        user.rewardDebt = user.shares.mul(pool.accTokenPerShare).div(1e12);

        // transfer the earn token if have
        // strat.onRewardEarn(msg.sender, user.shares);

        emit Deposit(msg.sender, _pid, _wantAmt, sharesAdded);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(
        uint256 _pid,
        uint256 _wantAmt
    ) public leaveFlashload(_pid) nonReentrant {
        require(!isContract(msg.sender));
        setAccounts(msg.sender);
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IStrategy strat = _UserStrategy(pool);

        (uint256 wantLockedTotal, uint256 sharesTotal) = strat.sharesInfo();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw pending Sushi
        harvest(pool, user);

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
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

        user.rewardDebt = user.shares.mul(pool.accTokenPerShare).div(1e12);

        emit Withdraw(msg.sender, _pid, _wantAmt, sharesRemoved);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IStrategy strat = _UserStrategy(pool);

        (uint256 wantLockedTotal, uint256 sharesTotal) = strat.sharesInfo();
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);

        strat.withdraw(msg.sender, amount);

        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        user.shares = 0;
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe Sushi transfer function, just in case if rounding error causes pool to not have enough
    function safeFTokenTransfer(address _to, uint256 _amt) internal {
        uint256 bal = IERC20(farmToken).balanceOf(address(this));
        if (_amt > bal) {
            IERC20(farmToken).transfer(_to, bal);
        } else {
            IERC20(farmToken).transfer(_to, _amt);
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
            (bool success, ) = _to.call{value: _amount}(new bytes(0));
            require(success, "!WETHelper: ETH_TRANSFER_FAILED");
        }
    }

    function setFlashloadBlk(uint256 _flashloadBlk) public onlyOwner {
        flashloadBlk = _flashloadBlk;
    }
}

