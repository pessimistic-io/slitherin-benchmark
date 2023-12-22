// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./AccessControlEnumerable.sol";
import "./Context.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./Address.sol";


contract POCOStake is Context, AccessControlEnumerable, ReentrancyGuard, Pausable {
    using Address for address;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // POCO token
    IERC20 public poco;

    struct Period {
        uint256 durationTime;
        uint256 amountPerSec;
    }
    Period[] public periods;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public leftRewardAmount;


    /* 
    Basically, any point in time, the amount of POCOs entitled to a user but is pending to be distributed is:
    
    pending POCO = (user.amount * pool.accPOCOPerToken) - user.finishedPOCO
    
    Whenever a user deposits or withdraws tokens to a pool. Here's what happens:
    1. The pool's `accPOCOPerToken` (and `lastRewardTime`) gets updated.
    2. User receives the pending POCO sent to his/her address.
    3. User's `amount` gets updated.
    4. User's `finishedPOCO` gets updated.
    */
    struct Pool {
        // Address of token
        address tokenAddress;
        // Weight of pool           
        uint256 poolWeight;
        // Last timestamp that POCOs distribution occurs for pool
        uint256 lastRewardTime;
        // Accumulated POCOs per token of pool
        uint256 accPOCOPerToken;
        // Current amount of token
        uint256 totalAmount;
    }

    // Total pool weight / Sum of all pool weights
    uint256 public totalPoolWeight;
    Pool[] public pool;

    struct User {
        // token amount that user provided
        uint256 amount;
        // Finished distributed POCOs to user
        uint256 finishedPOCO;
        // Settled but not transfer POCOs to user
        uint256 pendingPOCO;
    }

    // pool id => user address => user info
    mapping (uint256 => mapping (address => User)) public user;

    event SetPOCO(IERC20 indexed poco);

    event ResetPeriod();

    event SetStartTime(uint256 startTime, uint256 endTime);

    event EditPeriod(uint256 indexed idx, uint256 durationTime, uint256 amountPerSec, uint256 endTime);

    event AddPeriod(uint256 durationTime, uint256 amountPerSec, uint256 endTime);

    event AddPool(address indexed tokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardTime);

    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);

    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardTime, uint256 totalPOCO);

    event DepositReward(uint256 amount, uint256 leftAmount);

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount, uint256 rewardAmount);

    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount, uint256 rewardAmount);

    event EmergencyWithdraw(address indexed user, uint256 indexed poolId, uint256 amount);

    modifier hasAdminRole() {
        require(hasRole(ADMIN_ROLE, _msgSender()), "POCOPresale: must have admin role");
        _;
    }

    modifier isNotContract() {
        require(_msgSender() == tx.origin, "Sender is not EOA");
        _;
    }

    modifier checkPid(uint256 _pid) {
        require(_pid < pool.length, "Invalid pid");
        _;
    }

    /**
     * @notice Set POCO.
     */
    constructor(IERC20 _poco) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ADMIN_ROLE, _msgSender());

        setPOCO(_poco);
    }

    /**
     * @notice Set POCO token address. Can only be called by admin role
     */
    function setPOCO(IERC20 _poco) public hasAdminRole {
        poco = _poco;
    
        emit SetPOCO(poco);
    }

    function resetPeriod() public hasAdminRole {
        for (uint256 i = 0; i < periods.length; i++) {
            periods.pop();
        }
        emit ResetPeriod();
    }

    function setStartTime(uint256 _time) public hasAdminRole {
        startTime = _time;
        endTime = startTime;
        for (uint256 i = 0; i < periods.length; i++) {
            endTime = endTime + periods[i].durationTime;
        }
        emit SetStartTime(startTime, endTime);
    }

    function editPeriod(uint256 _idx, uint256 _durationTime, uint256 _amountPerSec) public hasAdminRole {
        require(_idx < periods.length, "invalid param");
        endTime = endTime - periods[_idx].durationTime + _durationTime;
        periods[_idx].durationTime = _durationTime;
        periods[_idx].amountPerSec = _amountPerSec;
        emit EditPeriod(_idx, _durationTime, _amountPerSec, endTime);
    }

    function addPeriod(uint256 _durationTime, uint256 _amountPerSec) public hasAdminRole {
        periods.push( Period({durationTime: _durationTime, amountPerSec: _amountPerSec}) );
        endTime = endTime + _durationTime;
        emit AddPeriod(_durationTime, _amountPerSec, endTime);
    }

    /** 
     * @notice Get the length/amount of pool
     */
    function getPoolLength() external view returns(uint256) {
        return pool.length;
    } 

    function getPoolInfo(uint256 _pid) external checkPid(_pid) view returns(uint256) {
        return pool[_pid].totalAmount;
    }

    function getUserAmount(address _addr, uint256 _pid) external checkPid(_pid) view returns(uint256) {
        return user[_pid][_addr].amount;
    }

    /** 
     * @notice Return reward multiplier over given _from to _to time. [_from, _to)
     * 
     * @param _from    From timestamp (included)
     * @param _to      To timestamp (exluded)
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256 multiplier) {
        if (_from < startTime) {
            _from = startTime;
        }
        if (_to > endTime) {
            _to = endTime;
        }

        uint256 startTimeTmp = startTime;
        for (uint256 i = 0; i < periods.length; i++) {
            uint256 endTimeTmp = startTimeTmp + periods[i].durationTime;
            if (_from >= startTimeTmp && _from < endTimeTmp) {
                if (_to <= endTimeTmp) {
                    multiplier = multiplier + (_to - _from) * periods[i].amountPerSec;
                    break;
                }
                multiplier = multiplier + (endTimeTmp - _from) * periods[i].amountPerSec;
                _from = endTimeTmp;
            }
            startTimeTmp = endTimeTmp;
        }
    }

    /** 
     * @notice Get pending POCO amount of user in pool
     */
    function pendingPOCO(uint256 _pid, address _user) public checkPid(_pid) view returns(uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];

        uint256 accPOCOPerToken_ = pool_.accPOCOPerToken;

        if (block.timestamp > pool_.lastRewardTime) {
            uint256 totalPOCO = getMultiplier(pool_.lastRewardTime, block.timestamp) * pool_.poolWeight / totalPoolWeight;

            uint256 tokenSupply = pool_.totalAmount;
            if (tokenSupply > 0) {
                accPOCOPerToken_ = accPOCOPerToken_ + totalPOCO * (1 ether) / tokenSupply;
            }
        }

        uint256 pendingPOCO_ = user_.amount * accPOCOPerToken_ / (1 ether) - user_.finishedPOCO + user_.pendingPOCO;

        return pendingPOCO_;
    }

    /** 
     * @notice Add a new Token to pool. Can only be called by admin role
     * DO NOT add the same token more than once. POCO rewards will be messed up if you do
     */
    function addPool(address _tokenAddress, uint256 _poolWeight, bool _withUpdate) public hasAdminRole {
        require(block.timestamp < endTime, "Already ended");
        require(_tokenAddress.isContract(), "Token address should be smart contract address");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.timestamp > startTime ? block.timestamp : startTime;
        totalPoolWeight = totalPoolWeight + _poolWeight;

        pool.push(Pool({
            tokenAddress: _tokenAddress,
            poolWeight: _poolWeight,
            lastRewardTime: lastRewardBlock,
            accPOCOPerToken: 0,
            totalAmount: 0
        }));

        emit AddPool(_tokenAddress, _poolWeight, lastRewardBlock);
    }

    /** 
     * @notice Update the given pool's weight. Can only be called by admin role.
     */
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public hasAdminRole checkPid(_pid) {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalPoolWeight = totalPoolWeight - pool[_pid].poolWeight + _poolWeight;
        pool[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    /** 
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];

        if (block.timestamp <= pool_.lastRewardTime) {
            return;
        }

        uint256 totalPOCO = getMultiplier(pool_.lastRewardTime, block.timestamp) * pool_.poolWeight / totalPoolWeight;

        uint256 tokenSupply = pool_.totalAmount;
        if (tokenSupply > 0) {
            pool_.accPOCOPerToken = pool_.accPOCOPerToken + totalPOCO * (1 ether) / tokenSupply;
        }
        pool_.lastRewardTime = block.timestamp;

        emit UpdatePool(_pid, pool_.lastRewardTime, totalPOCO);
    }

    /** 
     * @notice Update reward variables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = pool.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    function depositReward(uint256 _amount) external hasAdminRole {
        bool success = poco.transferFrom(address(msg.sender), address(this), _amount);
        require(success, "transfer error");
        leftRewardAmount = leftRewardAmount + _amount;
        emit DepositReward(_amount, leftRewardAmount);
    }

    /** 
     * @notice Deposit tokens for POCO rewards
     * Before depositing, user needs approve this contract to be able to spend or transfer their tokens
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of tokens to be deposited
     */
    function deposit(uint256 _pid, uint256 _amount) public checkPid(_pid) {
        require(block.timestamp < endTime, "Staking already ended");

        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        updatePool(_pid);

        uint256 pendingPOCO_;
        if (user_.amount > 0) {
            pendingPOCO_ = user_.amount * pool_.accPOCOPerToken / (1 ether) - user_.finishedPOCO;
            if(pendingPOCO_ > 0) {
                user_.pendingPOCO = user_.pendingPOCO + pendingPOCO_;
                // _safePOCORewardTransfer(msg.sender, pendingPOCO_);
            }
        }

        if(_amount > 0) {
            bool success = IERC20(pool_.tokenAddress).transferFrom(address(msg.sender), address(this), _amount);
            require(success, "transfer error");
            user_.amount = user_.amount + _amount;
            pool_.totalAmount = pool_.totalAmount + _amount;
        }

        user_.finishedPOCO = user_.amount * pool_.accPOCOPerToken / (1 ether);

        emit Deposit(msg.sender, _pid, _amount, pendingPOCO_);
    }

    /** 
     * @notice Withdraw tokens
     *
     * @param _pid       Id of the pool to be withdrawn from
     * @param _amount    amount of tokens to be withdrawn
     */
    function withdraw(uint256 _pid, uint256 _amount) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        require(user_.amount >= _amount, "Not enough token balance");

        updatePool(_pid);

        uint256 pendingPOCO_ = user_.amount * pool_.accPOCOPerToken / (1 ether) - user_.finishedPOCO + user_.pendingPOCO;
        user_.pendingPOCO = 0;

        if(pendingPOCO_ > 0) {
            _safePOCORewardTransfer(msg.sender, pendingPOCO_);
        }

        if(_amount > 0) {
            user_.amount = user_.amount - _amount;
            pool_.totalAmount = pool_.totalAmount - _amount;
            bool success = IERC20(pool_.tokenAddress).transfer(address(msg.sender), _amount);
            require(success, "transfer error");
        }

        user_.finishedPOCO = user_.amount * pool_.accPOCOPerToken / (1 ether);

        emit Withdraw(msg.sender, _pid, _amount, pendingPOCO_);
    }

    /** 
     * @notice Withdraw tokens without caring about POCO rewards. EMERGENCY ONLY
     *
     * @param _pid    Id of the pool to be emergency withdrawn from
     */
    function emergencyWithdraw(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        uint256 amount = user_.amount;

        pool_.totalAmount = pool_.totalAmount - amount;
        user_.amount = 0;
        user_.finishedPOCO = 0;
        user_.pendingPOCO = 0;

        bool success = IERC20(pool_.tokenAddress).transfer(address(msg.sender), amount);
        require(success, "transfer error");

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
     
    /** 
     * @notice Safe POCO transfer function, just in case if rounding error causes pool to not have enough POCOs
     *
     * @param _to        Address to get transferred POCOs
     * @param _amount    Amount of POCO to be transferred
     */
    function _safePOCORewardTransfer(address _to, uint256 _amount) internal {
        _amount = _amount > leftRewardAmount ? leftRewardAmount : _amount;
        poco.transfer(_to, _amount);
        leftRewardAmount = leftRewardAmount - _amount;
    }
}
