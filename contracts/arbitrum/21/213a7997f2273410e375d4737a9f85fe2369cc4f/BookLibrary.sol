// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { Ownable } from "./Ownable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { ILibraryBuilder } from "./ILibraryBuilder.sol";

contract BookLibrary is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; 
        uint256 totalExcluded;
        uint256 totalRealised; 
        uint256 depositTime; 
        uint256 lastClaimed;
    }

    // The name of the Library formatted as 'StakedToken / RewardToken'
    string public LIBRARY_NAME;

    // The address of the Library Builder
    address public libraryBuilder;

    // The address of the CoinBook
    mapping(address => bool) private coinBooks;

    // Whether a limit is set for users
    bool public hasUserLimit;

    // Whether it is initialized
    bool private isInitialized;

    // Whether rewards have started
    bool public rewardsStarted;

    // Whether rewards have started
    bool public rewardsEnded;

    // The block number when REWARD distribution starts
    uint256 public startTime;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // The time for lock funds.
    uint256 public lockTime;

    // The precision factor
    uint256 private pFACTOR;

    // The reward token
    IERC20 public rewardToken;

    // The staked token
    IERC20 public book;

    // Info of each user that stakes tokens
    mapping(address => UserInfo) public userInfo;

    // The total tokens staked
    uint256 public totalShares;

    // The total rewards generated
    uint256 public totalRewards;
    
    // The total rewards distributed
    uint256 public totalDistributed;
    
    // The cumulative rewards allocated per share 
    uint256 private rewardsPerShare;

    // The total rewards deposited while 0 tokens were staked
    uint256 private unallocatedRewards;
    
    event Deposit(address indexed user, uint256 amount);
    
    event EmergencyWithdraw(address indexed user, uint256 amount);
    
    event NewStartTime(uint256 startBlock);
    
    event NewPoolLimit(uint256 poolLimitPerUser);
    
    event Withdraw(address indexed user, uint256 amount);

    event RewardClaimed(address indexed user, uint256 amount);

    event LibraryTransferOut(address indexed user, uint256 amount, address fromLibrary, address toLibrary);

    event LibraryTransferIn(address indexed user, uint256 amount, address fromLibrary, address toLibrary);

    event DepositFromVesting(address indexed user, uint256 amount, address fromVesting, address toLibrary);

    event RewardAdded(uint256 amountAdded, uint256 totalRewardsAdded);

    event RewardsStarted(uint256 timeStamp);

    event RewardsEnded(uint256 timeStamp);
    
    event NewLockTime(uint256 lockTime);
    
    event SetLockTime(address indexed user, uint256 lockTime);

    modifier onlyCoinBook() {
        require(coinBooks[msg.sender] || msg.sender == libraryBuilder, "Caller not allowed");
        _;
    }

    modifier onlyLibraryBuilder() {
        require(msg.sender == libraryBuilder, "Caller not allowed");
        _;
    }

    constructor() {
        libraryBuilder = msg.sender;
    }

    /*
     * @notice Initialize the contract
     * @param _book staked token address
     * @param _rewardToken reward token address
     * @param _startTime reward start time
     * @param _poolLimitPerUser pool limit per user in book (if any, else 0)
     * @param _lockTime The amount of time tokens are locked once deposited
     * @param _admin admin address with ownership
     * @param _books CoinBook contracts that are allowed to deposit reward tokens
     */
    function initialize(
        address _book,
        address _rewardToken,
        uint256 _startTime,
        uint256 _poolLimitPerUser,
        uint256 _lockTime,
        address _admin,
        address[] calldata _books
    ) external {
        require(!isInitialized, "Already initialized");
        require(msg.sender == libraryBuilder, "Not builder");

        // Make this contract initialized
        isInitialized = true;

        book = IERC20(_book);
        rewardToken = IERC20(_rewardToken);
        startTime = _startTime;
        lockTime = _lockTime;
        
        for (uint i = 0; i < _books.length; i++) {
            coinBooks[_books[i]] = true;
        }

        if (_poolLimitPerUser > 0) {
            hasUserLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
        }

        uint256 decimalsRewardToken = uint256(IERC20Metadata(_rewardToken).decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        pFACTOR = uint256(10**(uint256(30) - decimalsRewardToken));

        LIBRARY_NAME = string.concat(IERC20Metadata(_book).symbol(), " / ", IERC20Metadata(_rewardToken).symbol());

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);
    }

    /*
     * @notice Deposit stake tokens and collect earned reward tokens (if any)
     * @param _amount The amount to stake (in stakeToken)
     */
    function deposit(uint256 _amount) external nonReentrant {
        require(!rewardsEnded, "Rewards have ended");
        UserInfo storage user = userInfo[msg.sender];

        if (hasUserLimit) {
            require(_amount + user.amount <= poolLimitPerUser, "User amount above limit");
        }

        if (user.amount > 0) {
            _distributeBounty(msg.sender);
        }

        if (_amount > 0) {
            user.amount += _amount;
            ILibraryBuilder(libraryBuilder).handleTransfer(address(book), msg.sender, address(this), _amount);
            user.depositTime = block.timestamp > startTime ? block.timestamp : startTime; 

            totalShares += _amount;
            user.totalExcluded = _getCumulativeRewards(user.amount);
        }

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @notice Harvest earned reward tokens
     */
    function harvest() external nonReentrant {
        require(userInfo[msg.sender].amount > 0, "User not staked");
        require(_getUnpaidEarnings(msg.sender) > 0, "No rewards to claim");
        _distributeBounty(msg.sender);
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount The amount to withdraw (in stakeToken)
     */
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");
        require(_amount > 0, "Amount must be greater than 0");
        require(user.depositTime + lockTime < block.timestamp || rewardsEnded, "Can not withdraw in lock period");

        _distributeBounty(msg.sender);
        user.amount -= _amount;
        totalShares -= _amount;
        user.totalExcluded = _getCumulativeRewards(user.amount);
        book.safeTransfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @notice Transfers specified amount of staked tokens to a different library
     * @dev Verifies that a library exists for _newRewardToken
     * @param _amount The amount to transfer to new library (in stakeToken)
     * @param _newRewardToken The address of the reward token to find the newPool address
     */
    function transferToNewPool(uint256 _amount, address _newRewardToken) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(_amount > 0, "Amount must be greater than 0");
        require(user.amount >= _amount, "Amount to withdraw too high");

        (bool hasLibrary, address _newPool) = 
            ILibraryBuilder(libraryBuilder).getLibraryPool(_newRewardToken);
        require(hasLibrary, "No library for new reward token");

        _distributeBounty(msg.sender);
        user.amount -= _amount;
        totalShares -= _amount;
        user.totalExcluded = _getCumulativeRewards(user.amount);
        IERC20(book).approve(_newPool, _amount);
        ILibraryBuilder(libraryBuilder).executeTransfer(msg.sender, _amount, address(this), _newPool);

        emit LibraryTransferOut(msg.sender, _amount, address(this), _newPool);
        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @notice Receives a transfer of staked tokens from a different library
     * @dev Only callable by LibraryBuilder contract
     * @param _account The account of the staker transferring
     * @param _amount The amount to transfer to new library (in stakeToken)
     * @param _oldPool The address of the Library that is being transferred from
     */
    function receiveTransfer(address _account, uint256 _amount, address _oldPool, bool _isFromVesting) external onlyLibraryBuilder {
        require(!rewardsEnded, "Rewards have ended");
        UserInfo storage user = userInfo[_account];

        if (hasUserLimit) {
            require(_amount + user.amount <= poolLimitPerUser, "User amount above limit");
        }

        if (user.amount > 0) {
            _distributeBounty(msg.sender);
        }

        if (_amount > 0) {
            user.amount += _amount;
            book.safeTransferFrom(_oldPool, address(this), _amount);
            user.depositTime = block.timestamp > startTime ? block.timestamp : startTime;  

            totalShares += _amount;
            user.totalExcluded = _getCumulativeRewards(user.amount);
        }

        if (_isFromVesting) {
            emit DepositFromVesting(_account, _amount, _oldPool, address(this));
        } else {
            emit LibraryTransferIn(_account, _amount, _oldPool, address(this));
        }
        emit Deposit(_account, _amount);
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        uint256 amountToTransfer = userInfo[msg.sender].amount;
        delete userInfo[msg.sender];

        if (amountToTransfer > 0) {
            book.safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, amountToTransfer);
    }

    /*
     * @notice Deposit reward tokens to be allocated to users currently staked
     * @dev Only callable by CoinBook or LibraryBuilder contracts
     * @param _amount The amount of reward tokens to allocate
     */
    function depositReward(uint256 _amount) external onlyCoinBook {
        require(!rewardsEnded, "Rewards have ended");
        if (totalShares == 0) {
            unallocatedRewards = _amount;
            return;
        } else if (unallocatedRewards > 0) {
            _amount += unallocatedRewards;
            unallocatedRewards = 0;
        }
        if (block.timestamp < startTime) {
            totalRewards += _amount;
        } else {
            if (rewardsStarted) {
                totalRewards += _amount;
                rewardsPerShare += (_amount * pFACTOR) / totalShares;
            } else {
                totalRewards += _amount;
                rewardsPerShare += (totalRewards * pFACTOR) / totalShares;
                rewardsStarted = true;
                emit RewardsStarted(block.timestamp);
            }
        }
        emit RewardAdded(_amount, totalRewards);
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit whether the limit remains forced
     * @param _poolLimitPerUser new pool limit per user
     */
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyOwner {
        require(hasUserLimit, "Must be set");
        if (_hasUserLimit) {
            require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            hasUserLimit = _hasUserLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update lock time
     * @dev Only callable by owner.
     * @param _lockTime the time in seconds that staked tokens are locked
     */
    function updateLockTime(uint256 _lockTime) external onlyOwner {
        lockTime = _lockTime;
        emit NewLockTime(_lockTime);
    }

    /*
     * @notice Update rewards start time
     * @dev Only callable by owner.
     * @param _newStartTime the time in seconds that rewards will start being allocated
     */
    function updateStartTime(uint256 _newStartTime) external onlyOwner {
        require(!rewardsStarted, "Rewards already started");
        startTime = _newStartTime;
        emit NewStartTime(_newStartTime);
    }

    /*
     * @notice End Rewards for this Library. This can not be undone.
     * @dev Only callable by LibraryBuilder contract
     */
    function endRewards() external onlyLibraryBuilder {
        rewardsEnded = true;
        emit RewardsEnded(block.timestamp);
    }

    /*
     * @notice Add or remove a CoinBook contract address.
     * @dev Only callable by LibraryBuilder contract
     * @param _coinBook The address to set or remove
     * @param _isCoinBook Whether to set or remove the address as a CoinBook contract
     */
    function editCoinBooks(address _coinBook, bool _isCoinBook) external onlyLibraryBuilder {
        coinBooks[_coinBook] = _isCoinBook;
    }

    /*
     * @notice Get amount of reward tokens claimable by a staker.
     * @param account The account to get earnings for
     * @return unpaidReward The amount claimable by staker
     */
    function getUnpaidEarnings(address account) external view returns (uint256 unpaidReward) {
        return _getUnpaidEarnings(account);
    }

    function _distributeBounty(address account) internal {
        if(userInfo[account].amount == 0){ return; }

        uint256 amount = _getUnpaidEarnings(account);
        if(amount > 0){
            totalDistributed += amount;
            userInfo[account].lastClaimed = block.timestamp;
            userInfo[account].totalRealised += amount;
            userInfo[account].totalExcluded = _getCumulativeRewards(userInfo[account].amount);
            rewardToken.transfer(account, amount);
            emit RewardClaimed(account, amount);
        }
    }

    function _getCumulativeRewards(uint256 share) internal view returns (uint256) {
        return (share * rewardsPerShare) / pFACTOR;
    }

    function _getUnpaidEarnings(address account) internal view returns (uint256) {
        if(userInfo[account].amount == 0){ return 0; }

        uint256 userTotalRewards = _getCumulativeRewards(userInfo[account].amount);
        uint256 userTotalExcluded = userInfo[account].totalExcluded;

        if(userTotalRewards <= userTotalExcluded){ return 0; }

        return userTotalRewards - userTotalExcluded;
    }
}
