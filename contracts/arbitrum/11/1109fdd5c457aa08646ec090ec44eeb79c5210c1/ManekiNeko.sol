// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./INekoProtocolToken.sol";

contract ManekiNeko is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    
    uint8 public constant KIND_POW = 0;
    uint8 public constant KIND_STAKING = 1;
    uint8 public constant KIND_Q2E = 2;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Tokenes
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTokenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct LockLpInfo {
        uint256 amount;
        uint256 timeUnlock;
    }

    struct Tokenomic {
        address contractAddress;
        uint256 maxAmount;
        uint256 maxTokenPerSecond; //To limit token mint
        uint256 minted;
        uint256 startTime;
        uint256 initToken;
        uint256 lastTimeClaim;
        bool isPause;
    } // MaxAmount / maxTokenPerSecond = Min time to release all maxAmount

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Tokenes to distribute per block.
        uint256 lastRewardBlock; // Last block number that Tokenes distribution occurs.
        uint256 accTokenPerShare; // Accumulated Tokenes per share, times 1e18. See below.
    }

    // The NekoProtocol TOKEN!
    INekoProtocolToken public token;
    address public devAddress;

    //NekoProtocol tokens created per block.
    uint256 public tokenPerBlock = 1875481992000000000000;

    bool public paused = false;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    Tokenomic[] public tokenomics;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Info of each user that lock LP tokens.
    mapping(uint256 => mapping(address => LockLpInfo)) public lockLpInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when Test mining starts.
    uint256 public startBlock;
    // Time lock LP when withdraw
    uint256 lockLpTime = 7 days;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Vesting(address indexed user, uint256 indexed index, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 tokenPerBlock);
    event ClaimTokenomic(address indexed request, address indexed to, uint256 amount);

    constructor(
        INekoProtocolToken _token,
        uint256 _startBlock,
        address _devAddress
    ) {
        token = _token;
        startBlock = _startBlock;
        devAddress = _devAddress;
        
        tokenomics.push(
            Tokenomic({
                contractAddress: address(0),
                maxAmount : 8500000000 * 1e18,
                maxTokenPerSecond : 410 * 1e18,
                minted : 0,
                startTime: block.timestamp,
                initToken: 2000000 * 1e18,
                lastTimeClaim : 0, //compare with firstUnLocktime
                isPause : true
            })
        ); // POW
        tokenomics.push(
            Tokenomic({
                contractAddress: address(0),
                maxAmount : 1717000000 * 1e18,
                maxTokenPerSecond : 100 * 1e18,
                minted : 0,
                startTime: block.timestamp,
                initToken: 0,
                lastTimeClaim : 0, //compare with firstUnLocktime
                isPause : true
            })
        ); // Staking
        tokenomics.push(
            Tokenomic({
                contractAddress: address(0),
                maxAmount : 4675000000 * 1e18,
                maxTokenPerSecond : 145 * 1e17, //14.5 token per second
                minted : 0,
                startTime: block.timestamp,
                initToken: 75000000 * 1e18,
                lastTimeClaim : 0, //compare with firstUnLocktime
                isPause : true
            })
        ); // Q2E
        
        
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    modifier notPause() {
        require(paused == false, "farm pool pause");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken
    ) external onlyOwner nonDuplicated(_lpToken) {
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken : _lpToken,
                allocPoint : _allocPoint,
                lastRewardBlock : lastRewardBlock,
                accTokenPerShare : 0
            })
        );
    }

    // Update the given pool's Test allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint
    ) external onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending tokenes on frontend.
    function pendingToken(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accTokenPerShare).div(1e18).sub(user.rewardDebt);
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
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        token.beckon(address(this), tokenReward);
        token.beckon(devAddress, tokenReward.div(10));

        pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e18).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to ManekiNeko for Test allocation.
    function deposit(uint256 _pid, uint256 _amount) public notPause nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                safeTokenTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from ManekiNeko.
    function withdraw(uint256 _pid, uint256 _amount) public notPause nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount && user.amount > 0, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            safeTokenTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            LockLpInfo storage lockInfo = lockLpInfo[_pid][msg.sender];
            lockInfo.amount.add(_amount);
            lockInfo.timeUnlock = block.timestamp + lockLpTime;
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function unlockLp(uint256 _pid) public notPause nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        LockLpInfo storage lockInfo = lockLpInfo[_pid][msg.sender];
        require(lockInfo.amount > 0 , "unlockLp: not good");
        require(block.timestamp >= lockInfo.timeUnlock , "unlockLp: not time");
        uint256 amount = lockInfo.amount;
        updatePool(_pid);
        lockInfo.amount = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        LockLpInfo storage lockInfo = lockLpInfo[_pid][msg.sender];
        lockInfo.amount.add(amount);
        lockInfo.timeUnlock = block.timestamp + lockLpTime;
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    //Request mint token from contract in tokenomic
    function claimTokenomic(uint8 _indexTokenomic, address _to, uint _amount) external nonReentrant {
        //Function for contract vesting call
        require(_indexTokenomic >= KIND_POW && _indexTokenomic <= KIND_Q2E, "invalid _indexTokenomic");
        Tokenomic storage infoTokenomic = tokenomics[_indexTokenomic];

        require(!infoTokenomic.isPause, "mint not allow");
        require(msg.sender == infoTokenomic.contractAddress, "invalid caller");
        require(infoTokenomic.maxAmount >= infoTokenomic.minted.add(_amount) , "invalid amount");
        uint maxTokenThisTime = ((block.timestamp.sub(infoTokenomic.startTime)).mul(infoTokenomic.maxTokenPerSecond)).add(infoTokenomic.initToken);
        require(maxTokenThisTime >= infoTokenomic.minted.add(_amount) , "over amount");
        token.beckon(_to, _amount);
        infoTokenomic.minted = infoTokenomic.minted.add(_amount);
        infoTokenomic.lastTimeClaim = block.timestamp;
        emit ClaimTokenomic(infoTokenomic.contractAddress, _to, _amount);
    }

    // Safe IToken transfer function, just in case if rounding error causes pool to not have enough FOXs.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = token.transfer(_to, tokenBal);
        } else {
            transferSuccess = token.transfer(_to, _amount);
        }
        require(transferSuccess, "safeTokenTransfer: Transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external onlyOwner {
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function updateEmissionRate(uint256 _tokenPerBlock) external onlyOwner {
        massUpdatePools();
        tokenPerBlock = _tokenPerBlock;
        emit UpdateEmissionRate(msg.sender, tokenPerBlock);
    }


    function setPause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        startBlock = _startBlock;
    }

    // Only update before start of farm
    function updateLockLpTime(uint256 _lockLpTime) external onlyOwner {
        lockLpTime = _lockLpTime;
    }

    function updateAddressTokenomic(uint8 _indexTokenomic, address _newAddress) external  onlyOwner{
        require(_indexTokenomic >= KIND_POW && _indexTokenomic <= KIND_Q2E, "invalid _indexTokenomic");
        require(_newAddress != address(0), "0x is not accepted here");
        Tokenomic storage infoTokenomic = tokenomics[_indexTokenomic];
        require(infoTokenomic.contractAddress != _newAddress , "address exist");
        infoTokenomic.contractAddress = _newAddress;
    }

    //pause mint for contract 
    function updatePauseTokenomic(uint8 _indexTokenomic, bool _isPause) external  onlyOwner{
        require(_indexTokenomic >= KIND_POW && _indexTokenomic <= KIND_Q2E, "invalid _indexTokenomic");
        Tokenomic storage infoTokenomic = tokenomics[_indexTokenomic];
        require(infoTokenomic.isPause != _isPause , "isPause exist");
        infoTokenomic.isPause = _isPause;
    }

    function updateStartTime(uint8 _indexTokenomic, uint _startTime) external  onlyOwner{
        require(_indexTokenomic >= KIND_POW && _indexTokenomic <= KIND_Q2E, "invalid _indexTokenomic");
        Tokenomic storage infoTokenomic = tokenomics[_indexTokenomic];
        require(_startTime >= block.timestamp, "start time must be after now");
        infoTokenomic.startTime = _startTime;
    }

}
