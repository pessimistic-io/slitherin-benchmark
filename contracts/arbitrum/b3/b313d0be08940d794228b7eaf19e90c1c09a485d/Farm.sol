// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./TransferHelper.sol";
import "./IWETH.sol";
import "./WETHelper.sol";

contract QQFarm is Ownable {
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 amount;
        uint256 lastRewardBlock;
        uint256 accGovTokenPerShare;
    }
    address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    IERC20 public govToken;
    address public devaddr;
    uint256 public govTokenPerBlock;
    uint256 public blocksHalving;
    PoolInfo[] public poolInfo;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;
    uint256 public bonusEndBlock;
    uint256 public constant BONUS_MULTIPLIER = 2;
    WETHelper public wethelper;
    bool farmStarted;

    event Deposit(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 liquidity
    );
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Mint(address indexed user, uint256 amount);

    function initialize(IERC20 _govToken, address _devaddr) public initializer {
        Ownable.__Ownable_init();
        govToken = _govToken;
        devaddr = _devaddr;
        govTokenPerBlock = 0;
        wethelper = new WETHelper();
    }

    receive() external payable {}

    function startFarming(uint256 _govTokenPerBlock) public {
        require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
        require(!farmStarted, "farmStarted");
        farmStarted = true;
        govTokenPerBlock = _govTokenPerBlock;
        startBlock = block.number;
        bonusEndBlock = startBlock + 288000 * 30;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public {
        require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
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
                amount: 0,
                lastRewardBlock: lastRewardBlock,
                accGovTokenPerShare: 0
            })
        );
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public {
        require(msg.sender == owner() || msg.sender == devaddr, "!dev addr");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public view returns (uint256) {
        if (_from < startBlock) {
            _from = startBlock;
        }
        if (_to < _from) {
            _to = _from;
        }
        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from);
        } else {
            return
                bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                    _to.sub(bonusEndBlock)
                );
        }
    }

    function pendingGovToken(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accGovTokenPerShare = pool.accGovTokenPerShare;
        uint256 lpSupply = pool.amount;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 govTokenReward = multiplier
                .mul(govTokenPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accGovTokenPerShare = accGovTokenPerShare.add(
                govTokenReward.mul(1e12).div(lpSupply)
            );
        }
        return
            user.amount.mul(accGovTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (block.number >= bonusEndBlock) {
            bonusEndBlock = bonusEndBlock + blocksHalving;
            govTokenPerBlock = govTokenPerBlock.div(2);
        }
        uint256 lpSupply = pool.amount;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 govTokenReward = multiplier
            .mul(govTokenPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        pool.accGovTokenPerShare = pool.accGovTokenPerShare.add(
            govTokenReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount) public payable {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accGovTokenPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                safeGovTokenTransfer(msg.sender, pending);
            }
        }

        if (address(pool.lpToken) == WETH) {
            if (_amount > 0) {
                TransferHelper.safeTransferFrom(
                    address(pool.lpToken),
                    address(msg.sender),
                    address(this),
                    _amount
                );
                TransferHelper.safeTransfer(WETH, address(wethelper), _amount);
                wethelper.withdraw(WETH, address(this), _amount);
            }
            if (msg.value > 0) {
                _amount = _amount.add(msg.value);
            }
        } else if (_amount > 0) {
            TransferHelper.safeTransferFrom(
                address(pool.lpToken),
                address(msg.sender),
                address(this),
                _amount
            );
        }

        if (_amount > 0) {
            pool.amount = pool.amount.add(_amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);

        emit Deposit(msg.sender, _pid, _amount, 0);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user
            .amount
            .mul(pool.accGovTokenPerShare)
            .div(1e12)
            .sub(user.rewardDebt);
        if (pending > 0) {
            safeGovTokenTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.amount = pool.amount.sub(_amount);
            TransferHelper.safeTransfer(
                address(pool.lpToken),
                address(msg.sender),
                _amount
            );
        }
        user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function safeGovTokenTransfer(address _to, uint256 _amount) internal {
        if (govToken.balanceOf(address(this)) < _amount) {
            _amount = govToken.balanceOf(address(this));
        } else {
            return;
        }
        govToken.transfer(_to, _amount);
        emit Mint(_to, _amount);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}

