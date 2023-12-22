//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "./Ownable.sol";
import "./IERC721Metadata.sol";
import "./IERC20Metadata.sol";
import "./IERC721Receiver.sol";
import "./EnumerableSet.sol";

contract DynamicNFTStaking is Ownable, IERC721Receiver {
    using EnumerableSet for EnumerableSet.UintSet;
// bool
    bool public hasUserLimit;
    bool public isInitialized;
    bool public poolIsOnline;
    bool public withdrawTimerStatus;
    bool public depositEnabled;
    bool public withdrawEnabled;
    bool public emergencyWithdrawEnabled;
    bool public hasMinimumDeposit;
    bool private tempLock;
    bool private isSameToken;

// uint
    uint256 public totalUsersInStaking;
    uint256 public poolTotalReward;
    uint256 public minimumDeposit;
    uint256 public accTokenPerShare;
    uint256 public bonusEndBlock;
    uint256 public startBlock;
    uint256 public lastRewardBlock;
    uint256 public poolLimitPerUser;
    uint256 public rewardPerBlock;
    uint256 public minimumLockTime = 7 days;
    uint256 public PRECISION_FACTOR;
    uint256 public totalUsersStake;
    uint256 public totalUsersRewards;
    uint256 public emergencyWithdrawFee;

// custom
    EnumerableSet.UintSet private _tokensInPool;
    IERC20Metadata public rewardToken;
    IERC721Metadata public stakedToken;

// mapping
    mapping(address => UserInfo) public userInfo;
    mapping(uint => address) public depositedNFTs;
    mapping(address => UserDepositedNFTs) private _userDepositedNFTs;

// struct
    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 lockTime; // time when locked
    }
    struct UserDepositedNFTs {
        EnumerableSet.UintSet userDepositedNFTs;
    }

// event
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event PoolFunded(uint256 amount);
    event ClaimReward(address indexed user, uint256 amount);

// constructor
    constructor() {
    }

// receive ERC721
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 /* tokenId */,
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

// set pool state
    function setPoolState(bool _poolIsOnline, bool _depositEnabled, bool _withdrawEnabled,
                          bool _emergencyWithdrawEnabled) external onlyOwner {
        poolIsOnline = _poolIsOnline;
        depositEnabled = _depositEnabled;
        withdrawEnabled = _withdrawEnabled;
        emergencyWithdrawEnabled = _emergencyWithdrawEnabled;
    }

    function enablePool() external onlyOwner {
        poolIsOnline = true;
        depositEnabled = true;
        withdrawEnabled = true;
        withdrawTimerStatus = true;
        emergencyWithdrawEnabled = true;
    }
    

// set emergency withdraw fee
    function setEmergencyWithdrawFee(uint256 _fee) external onlyOwner {
        emergencyWithdrawFee = _fee;
        require(emergencyWithdrawFee <= 30, "max fee is 30%");
    }

// set minimum deposit
    function setMinimumDeposit(bool _state, uint256 value) external onlyOwner {
        hasMinimumDeposit = _state;
        minimumDeposit = value;
    }

// set withdraw timer status
    function setwithdrawTimerStatus(bool _state) external onlyOwner {
        withdrawTimerStatus = _state;
    }

// set lock time
    function setLockTime(uint256 _deposit) external onlyOwner {
        minimumLockTime = _deposit;
        require(minimumLockTime <= 90 days, "max lock time is 90 days");
    }

    function fundPool(uint256 amount) external onlyOwner {
        poolTotalReward += amount;
        rewardToken.transferFrom(address(msg.sender), address(this), amount);
        emit PoolFunded(amount);
    }

    function istart(
        IERC721Metadata _stakedToken,
        IERC20Metadata _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _poolLimitPerUser
    ) external onlyOwner {
        require(!isInitialized, "Already initialized");

        isInitialized = true;
        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        emergencyWithdrawFee = 5;
        minimumLockTime = 30 days;

        if (_poolLimitPerUser > 0) {
            hasUserLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
        }

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30) - decimalsRewardToken));

        lastRewardBlock = startBlock;

        if(address(rewardToken) == address(stakedToken)) {
            isSameToken = true;
        }
    }

    modifier isPoolOnline(uint8 action_type) {
        require(poolIsOnline,"staking platform not available now.");
        if (action_type == 0) {
            require(depositEnabled,"deposits not available now.");
        }
        else if (action_type == 1) {
            require(withdrawEnabled,"withdraws not available now.");
        }
        else if (action_type == 6) {
            require(emergencyWithdrawEnabled,"emergency withdraws not available now.");
        }
        _;
    }

// user functions
    function deposit(uint256 tokenId) external isPoolOnline(0) {
        require(!tempLock,"safety block");
        tempLock = true;
        UserInfo storage user = userInfo[msg.sender];
        if (hasUserLimit) {
            require(1 + user.amount <= poolLimitPerUser, "User amount above limit");
        }
        if (hasMinimumDeposit) {
            require(1 >= minimumDeposit,"deposit too low.");
        }
        _updatePool();

        if (user.amount > 0) {
            uint256 pending = user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
            if (pending > 0) {
                totalUsersRewards += pending;
                poolTotalReward -= pending;
                rewardToken.transfer(address(msg.sender), pending);
                emit ClaimReward(msg.sender,pending);
            }
        } else {
            totalUsersInStaking += 1;
        }

        user.amount += 1;
        totalUsersStake += 1;
        depositedNFTs[tokenId] = msg.sender;
        _userDepositedNFTs[msg.sender].userDepositedNFTs.add(tokenId);
        _tokensInPool.add(tokenId);
        stakedToken.safeTransferFrom(address(msg.sender), address(this), tokenId);

        user.rewardDebt = user.amount * accTokenPerShare / PRECISION_FACTOR;

        user.lockTime = block.timestamp + minimumLockTime;
        tempLock = false;
        emit Deposit(msg.sender, tokenId);
    }
    function withdraw(uint256 tokenId) external isPoolOnline(1) {
        require(!tempLock,"safety block");
        tempLock = true;
        UserInfo storage user = userInfo[msg.sender];
        require(depositedNFTs[tokenId] == msg.sender,"You do not own this NFT");
        require(user.amount >= 1, "Amount to withdraw too high");
        if(withdrawTimerStatus) {
            require(block.timestamp >= user.lockTime,"locking period has not expired"
            );
        }

        _updatePool();

        uint256 pending = user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;

        user.amount -= 1;
        totalUsersStake -= 1;
        depositedNFTs[tokenId] = address(0);
        _userDepositedNFTs[msg.sender].userDepositedNFTs.remove(tokenId);
        _tokensInPool.remove(tokenId);
        stakedToken.safeTransferFrom(address(this),address(msg.sender), tokenId);
        

        if (pending > 0) {
            totalUsersRewards += pending;
            poolTotalReward -= pending;
            rewardToken.transfer(address(msg.sender), pending);
            emit ClaimReward(msg.sender,pending);
        }

        user.rewardDebt = user.amount * accTokenPerShare / PRECISION_FACTOR;
        
        if (user.amount == 0) {
            user.lockTime = 0;
            totalUsersInStaking -= 1;
        }

        tempLock = false;
        emit Withdraw(msg.sender, tokenId);
    }

    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
    }
    
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyOwner {
        hasUserLimit = _hasUserLimit;
        poolLimitPerUser = _poolLimitPerUser;
    }
    
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        rewardPerBlock = _rewardPerBlock;
    }

    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _bonusEndBlock) external onlyOwner {
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        lastRewardBlock = startBlock;
    }

    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply;
        if(isSameToken) {
            stakedTokenSupply = stakedToken.balanceOf(address(this)) - poolTotalReward;
        } else {
            stakedTokenSupply = stakedToken.balanceOf(address(this));
        }
        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 cakeReward = multiplier * rewardPerBlock;
            uint256 adjustedTokenPerShare =
                accTokenPerShare + (cakeReward * PRECISION_FACTOR / stakedTokenSupply);
            return user.amount * adjustedTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
        } else {
            return user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
        }
    }

    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 cakeReward = multiplier * rewardPerBlock;
        accTokenPerShare = accTokenPerShare + (cakeReward * PRECISION_FACTOR / stakedTokenSupply);
        lastRewardBlock = block.number;
    }

    function getBlockData() public view returns(uint blockNumber,uint blockTime) {
        blockNumber = block.number;
        blockTime = block.timestamp;
        return (blockNumber,blockTime);
    }

    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to - _from;
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock - _from;
        }
    }

    function getDepositedNfts() public view returns(uint[] memory) {
        uint length = _tokensInPool.length();
        uint[] memory tokenIds = new uint[](length);
        for(uint i = 0; i < length; i++) {
            tokenIds[i] = _tokensInPool.at(i);
        }
        return(tokenIds);
    }

    function getUserDepositedNFTs(address user) external view returns(uint[] memory) {
        uint length = _userDepositedNFTs[user].userDepositedNFTs.length();
        uint[] memory tokenIds = new uint[](length);
        for(uint i = 0; i < length; i++) {
            tokenIds[i] = _userDepositedNFTs[user].userDepositedNFTs.at(i);
        }
        return(tokenIds);
    }
}
