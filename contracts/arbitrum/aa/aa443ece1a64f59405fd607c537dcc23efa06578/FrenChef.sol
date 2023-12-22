// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./wGM.sol";

import "./IERC721.sol";
import "./IERC1155.sol";

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw an error.
 * Based off of https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/math/SafeMath.sol.
 */
library SafeMath {
    /*
     * Internal functions
     */

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for ERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require((value == 0) || (token.allowance(address(this), spender) == 0));
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must equal true).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.

        // A Solidity high level call has three parts:
        //  1. The target address is checked to verify it contains contract code
        //  2. The call itself is made, and success asserted
        //  3. The return value is decoded, which in turn checks the size of the returned data.

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success);

        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)));
        }
    }
}

// MasterChef is the master of Apollo. He can make Apollo and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Apollo is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
// European boys play fair, don't worry.

contract MasterFren is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of WGM
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accWGMPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accWGMPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. IRISes to distribute per block.
        uint256 lastRewardBlock; // Last block number that IRISes distribution occurs.
        uint256 accWGMPerShare; // Accumulated IRISes per share, times 1e18. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
        uint256 lpSupply;
    }

    // The WGM TOKEN!
    Wrapped_GM public wgm;
    IERC721 public nft;
    IERC1155 public nft1155;
    address public devAddress;
    address public feeAddress;
    uint256 constant max_wgm_supply = 420_000_000 ether;

    // WGM tokens created per block.
    uint256 public wgmPerBlock = 1 ether;

    mapping(uint256 => uint256) public PID_LP;
    uint256 public mul = 1;
    uint256 public div = 3;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when WGM mining starts.
    uint256 public startBlock;

    uint256 public constant MAXIMUM_EMISSION_RATE = 5 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 wgmPerBlock);
    event PoolAdd(
        address indexed user,
        IERC20 lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint16 depositFeeBP
    );
    event PoolSet(
        address indexed user,
        IERC20 lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint16 depositFeeBP
    );
    event UpdateStartBlock(address indexed user, uint256 startBlock);

    constructor(uint256 _startBlock) public {
        wgm = Wrapped_GM(0x8cF0713C0bCb774FEB845e93208698510D5971a1);
        nft = IERC721(0x249bB0B4024221f09d70622444e67114259Eb7e8);
        nft1155 = IERC1155(0x5A8b648dcc56e0eF241f0a39f56cFdD3fa36AfD5);
        startBlock = _startBlock;

        devAddress = owner();
        feeAddress = owner();
        wgm.balanceOf(address(this));
        nft.balanceOf(address(this));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint16 _depositFeeBP
    ) external onlyOwner nonDuplicated(_lpToken) {
        _lpToken.balanceOf(address(this));
        require(_depositFeeBP <= 500, "add: invalid deposit fee basis points");
        _lpToken.balanceOf(address(this));
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accWGMPerShare: 0,
                depositFeeBP: _depositFeeBP,
                lpSupply: 0
            })
        );
        emit PoolAdd(msg.sender, _lpToken, _allocPoint, lastRewardBlock, _depositFeeBP);
    }

    // Update the given pool's WGM allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP) external onlyOwner {
        require(_depositFeeBP <= 500, "set: invalid deposit fee basis points");
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        emit PoolSet(msg.sender, poolInfo[_pid].lpToken, _allocPoint, poolInfo[_pid].lastRewardBlock, _depositFeeBP);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (wgm.totalSupply() >= max_wgm_supply) return 0;

        return _to.sub(_from);
    }

    // View function to see pending IRISes on frontend.
    function pendingWGM(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accWGMPerShare = pool.accWGMPerShare;
        if (block.number > pool.lastRewardBlock && pool.lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 wgmReward = multiplier.mul(wgmPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accWGMPerShare = accWGMPerShare.add(wgmReward.mul(1e18).div(pool.lpSupply));
        }
        return user.amount.mul(accWGMPerShare).div(1e18).sub(user.rewardDebt);
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
        if (pool.lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 wgmReward = multiplier.mul(wgmPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        if (wgm.totalSupply().add(wgmReward.mul(105).div(100)) <= max_wgm_supply) {
            wgm.mint(address(this), wgmReward);
        } else if (wgm.totalSupply() < max_wgm_supply) {
            wgm.mint(address(this), max_wgm_supply.sub(wgm.totalSupply()));
        }
        pool.accWGMPerShare = pool.accWGMPerShare.add(wgmReward.mul(1e18).div(pool.lpSupply));
        pool.lastRewardBlock = block.number;
    }

    event Bonus(address to, uint256 multiplier, uint256 bonus);

    // Deposit LP tokens to MasterChef for WGM allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 FrensRewards = nft1155.balanceOf(msg.sender, PID_LP[_pid]);
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accWGMPerShare).div(1e18).sub(user.rewardDebt);

            // add additional % bonus
            uint256 multiplier = calculateBonus(msg.sender);
            if (multiplier > 0 && pending > 0) {
                uint256 bonus = pending.mul(multiplier).div(1000);
                emit Bonus(msg.sender, multiplier, bonus);
                wgm.mint(address(this), bonus);
                pending = pending.add(bonus);
            }
            if (FrensRewards > 0) {
                uint256 frenbonus = (FrensRewards * pending * mul) / div;
                pending = pending.add(frenbonus);
            }

            if (pending > 0) {
                safeWGMTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);
            require(_amount > 0, "we dont accept deposits of 0");
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
                pool.lpSupply = pool.lpSupply.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
                pool.lpSupply = pool.lpSupply.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accWGMPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accWGMPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            // add additional % bonus
            uint256 multiplier = calculateBonus(msg.sender);
            if (multiplier > 0 && pending > 0) {
                uint256 bonus = pending.mul(multiplier).div(1000);
                emit Bonus(msg.sender, multiplier, bonus);
                wgm.mint(address(this), bonus);
                pending = pending.add(bonus);
            }

            safeWGMTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accWGMPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        pool.lpSupply = pool.lpSupply.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    event ApolloTransfer(address to, uint256 requested, uint256 amount);

    // Safe wgm transfer function, just in case if rounding error causes pool to not have enough WGM.
    function safeWGMTransfer(address _to, uint256 _amount) internal {
        uint256 wgmBal = wgm.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > wgmBal) {
            transferSuccess = wgm.transfer(_to, wgmBal);
            emit ApolloTransfer(_to, _amount, wgmBal);
        } else {
            transferSuccess = wgm.transfer(_to, _amount);
        }
        require(transferSuccess, "safeWGMTransfer: Transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external onlyOwner {
        require(_devAddress != address(0), "!nonzero");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "!nonzero");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _apolloPerBlock) external onlyOwner {
        require(_apolloPerBlock <= MAXIMUM_EMISSION_RATE, "Too High");
        massUpdatePools();
        wgmPerBlock = _apolloPerBlock;
        emit UpdateEmissionRate(msg.sender, _apolloPerBlock);
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock) external onlyOwner {
        require(startBlock > block.number, "Farm already started");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = _startBlock;
        }
        startBlock = _startBlock;
        emit UpdateStartBlock(msg.sender, _startBlock);
    }

    uint256 public minNftToBoost = 5;
    uint256 public nftBoost = 50; // 5%

    function setMinNftBoost(uint256 _minNftToBoost) external onlyOwner {
        minNftToBoost = _minNftToBoost;
    }

    function setNftBoost(uint256 _nftBoost) external onlyOwner {
        nftBoost = _nftBoost;
    }

    function isNftHolder(address _address) public view returns (bool) {
        return nft.balanceOf(_address) >= minNftToBoost;
    }

    uint256 public constant BONUS_MULTIPLIER = 0;

    function calculateBonus(address _user) public view returns (uint256) {
        uint256 _isNftHolder = 0;
        if (isNftHolder(_user)) {
            _isNftHolder = nftBoost;
        }
        uint totalReward = _isNftHolder;
        return BONUS_MULTIPLIER.add(totalReward);
    }

    modifier onlyOperator() {
        require(devAddress == msg.sender, "caller is not dev");
        _;
    }

    function setERC1155LPs(uint256 _pid, uint256 _lp, uint256 _mul, uint256 _div) external onlyOperator {
        PID_LP[_pid] = _lp;
        mul = _mul;
        div = _div;
    }

    function setRewardTo09() external onlyOperator {
        wgmPerBlock = 0.9 ether;
    }

    function setRewardTo06() external onlyOperator {
        wgmPerBlock = 0.6 ether;
    }

    function setRewardTo03() external onlyOperator {
        wgmPerBlock = 0.3 ether;
    }

    function setRewardTo01() external onlyOperator {
        wgmPerBlock = 0.1 ether;
    }
}

