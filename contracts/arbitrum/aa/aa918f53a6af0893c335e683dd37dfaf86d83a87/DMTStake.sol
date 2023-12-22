// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity ^0.8.0;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: contracts/dmt_staking.sol



//  ██▄   █▀▄▀█    ▄▄▄▄▀        ▄▄▄▄▄      ▄▄▄▄▀ ██   █  █▀ ▄█    ▄     ▄▀  
//  █  █  █ █ █ ▀▀▀ █          █     ▀▄ ▀▀▀ █    █ █  █▄█   ██     █  ▄▀    
//  █   █ █ ▄ █     █        ▄  ▀▀▀▀▄       █    █▄▄█ █▀▄   ██ ██   █ █ ▀▄  
//  █  █  █   █    █          ▀▄▄▄▄▀       █     █  █ █  █  ▐█ █ █  █ █   █ 
//  ███▀     █    ▀                       ▀         █   █    ▐ █  █ █  ███  
//          ▀                                      █   ▀       █   ██       
//   

pragma solidity >=0.7.0 <0.9.0;


interface IERC20 {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract DMTStake is Ownable {
    IERC20 public token;
    uint256 public prizePool;
    uint256 public APY = 420;
    uint256 public LOCKING_PERIOD = 14 days;

    event WithdrawalRequested(
        address indexed user,
        uint256 amount,
        uint256 requrstTS,
        uint256 releaseTime
    );
    event TokensLocked(address indexed user, uint256 amount, uint256 timestamp);
    event TokensUnlocked(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    event RewardsClaimed(
        address indexed user,
        uint256 reward,
        uint256 timestamp
    );

    struct UserInfo {
        uint256 lockedTokens;
        uint256 amountWithdrawTokens;
        uint256 lastRewardClaimTimeStamp;
        uint256 withdrawTimes;
        mapping(uint256 => uint256) withdrawrequest;
        mapping(uint256 => uint256) UnlockTimeStamp;
    }

    mapping(address => UserInfo) public userInfo;

    constructor(IERC20 _token) {
        token = _token;
    }

    function stake(uint256 amount) public {
        require(amount <= token.balanceOf(msg.sender), "Not enough tokens");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        UserInfo storage user = userInfo[msg.sender];
        user.lockedTokens += amount;
        user.lastRewardClaimTimeStamp = block.timestamp;
        emit TokensLocked(msg.sender, amount, block.timestamp);
    }

    function stakeAll(address useraddress) public {
        uint256 amount = token.balanceOf(useraddress);
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        require(useraddress == msg.sender, "Not owner");
        require(amount > 0, "Not enough tokens to stake");
        UserInfo storage user = userInfo[useraddress];
        user.lockedTokens += amount;
        user.lastRewardClaimTimeStamp = block.timestamp;
        emit TokensLocked(msg.sender, amount, block.timestamp);
    }

    function unstake(uint256 amount) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.lockedTokens > 0, "No tokens locked");
        require(
            amount + user.amountWithdrawTokens <= user.lockedTokens,
            "Cannot withdraw more than locked"
        );
        user.withdrawTimes += 1;
        uint256 withdrwID = user.withdrawTimes;
        uint256 unlockTimestamp = block.timestamp + LOCKING_PERIOD;
        user.UnlockTimeStamp[withdrwID] = unlockTimestamp;
        user.amountWithdrawTokens += amount;
        user.withdrawrequest[withdrwID] = amount;
        emit WithdrawalRequested(
            msg.sender,
            amount,
            block.timestamp,
            unlockTimestamp
        );
    }

    function unstakeAll() public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.lockedTokens - user.amountWithdrawTokens;
        require(amount != 0, "You requested to withdraw all locked tokens");
        user.withdrawTimes += 1;
        uint256 withdrwID = user.withdrawTimes;
        uint256 unlockTimestamp = block.timestamp + LOCKING_PERIOD;
        user.UnlockTimeStamp[withdrwID] = unlockTimestamp;
        user.amountWithdrawTokens += amount;
        user.withdrawrequest[withdrwID] = amount;
        emit WithdrawalRequested(
            msg.sender,
            amount,
            block.timestamp,
            unlockTimestamp
        );
    }

    function claimTokens(uint256 _id, address userAddress) public {
        UserInfo storage user = userInfo[userAddress];
        uint256 amount = user.withdrawrequest[_id];
        require(amount > 0, "No pending withdrawal");
        require(
            block.timestamp >= user.UnlockTimeStamp[_id],
            "No time to claim"
        );
        claimRewards(userAddress);
        user.lockedTokens -= amount;
        user.amountWithdrawTokens -= amount;
        user.withdrawrequest[_id] = 0;
        token.transfer(userAddress, amount);
        emit TokensUnlocked(userAddress, amount, block.timestamp);
    }

    function calculateReward(address userAddress)
        public
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[userAddress];
        uint256 stakedAmount = user.lockedTokens;
        uint256 lastClaimTime = user.lastRewardClaimTimeStamp;
        uint256 RewardforYear = (stakedAmount * APY) / 100;
        uint256 RewardperDay = RewardforYear / 365;
        uint256 timeelapsed = block.timestamp - lastClaimTime;
        uint256 rewards = (RewardperDay * timeelapsed) / 1 days;

        return rewards;
    }

    function stakerewards() public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 rewards = calculateReward(msg.sender);
        require(rewards > 0, "No rewards to stake");
        claimRewardstoStake(msg.sender, rewards);
        user.lockedTokens += rewards;
        emit TokensLocked(msg.sender, rewards, block.timestamp);
    }

    function claimRewards(address userAddress) public {
        UserInfo storage user = userInfo[userAddress];
        uint256 reward = calculateReward(userAddress);
        require(reward > 0, "No rewards to claim");
        require(prizePool - reward >= 0, "Prize Pool is Empty");
        if (reward > 0) {
            token.transfer(userAddress, reward);
            user.lastRewardClaimTimeStamp = block.timestamp;
            prizePool -= reward;
            emit RewardsClaimed(userAddress, reward, block.timestamp);
        }
    }

    function claimRewardstoStake(address userAddress, uint256 rewards)
        internal
    {
        UserInfo storage user = userInfo[userAddress];
        require(rewards > 0, "No rewards to claim");

        if (rewards > 0) {
            user.lastRewardClaimTimeStamp = block.timestamp;
            emit RewardsClaimed(msg.sender, rewards, block.timestamp);
        }
    }

    function changeAPY(uint256 _newapy) public onlyOwner {
        APY = _newapy;
    }

    function changeLockPeriod(uint256 _newtimestamp) public onlyOwner {
        LOCKING_PERIOD = _newtimestamp;
    }

    function getWithdraws(address userAddr, uint256 _id)
        public
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[userAddr];
        return user.withdrawrequest[_id];
    }

    function getWithdrawunlock(address userAddr, uint256 _id)
        public
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[userAddr];
        return user.UnlockTimeStamp[_id];
    }

    function chargePool(uint256 amount) public onlyOwner {
    token.transferFrom(msg.sender, address(this), amount);
    prizePool += amount;
    }

    function WithdrawPool(uint256 amount, address _address) public onlyOwner {
       token.transfer(_address, amount);
       prizePool -= amount;
    }
}