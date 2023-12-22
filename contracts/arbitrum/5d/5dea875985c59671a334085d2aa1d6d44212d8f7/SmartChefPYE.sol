// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { Ownable } from "./Ownable.sol";
import { Arrays } from "./Arrays.sol";
import { Counters } from "./Counters.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeMath } from "./SafeMath.sol";
import { AccessControl } from "./AccessControl.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { ERC20 } from "./ERC20.sol";
import { IRewardToken } from "./IRewardToken.sol";
import { PYESlice } from "./PYESlice.sol";
import { IPYESlice } from "./IPYESlice.sol";

contract SmartChefPYE is Ownable, ReentrancyGuard, ERC20 {
    using SafeERC20 for IERC20;
    using SafeERC20 for IRewardToken;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 depositTime;    // The last time when the user deposit funds
    }

    struct Share {
        uint256 amount;
        uint256 totalExcludedWETH;
        uint256 totalRealisedWETH;
    }

    // @dev struct containing all elements of pre-sale token. 
    struct PresaleToken {
        string presaleTokenName;
        address presaleTokenAddress;
        uint256 presaleTokenBalance;
        uint256 presaleTokenRewardsPerShare; 
        uint256 presaleTokenTotalDistributed;
        uint256 presaleTokenSnapshotId;
    }

    // PYESliceToken for stakers
    address public pyeSlice;

    // donation state variables
    uint256 public totalDonations;

    // Whether a limit is set for users
    bool public hasUserLimit;

    // Whether it is initialized
    bool public isInitialized;

    // Accrued token per share
    uint256 public accTokenPerShare;

    // The block number when reward mining ends.
    uint256 public bonusEndTime;

    // The block number when reward mining starts.
    uint256 public startTime;

    // The block number of the last pool update
    uint256 public lastRewardTime;

    // The pool limit (0 if none)
    uint256 public poolLimitPerUser;

    // Reward tokens created per second.
    uint256 public rewardPerSecond;

    // Reward tokens created per day.
    uint256 public rewardPerDay;

    // The time for lock funds.
    uint256 public lockTime;

    // Dev fee.
    uint256 public devfee;

    // The precision factor
    uint256 public constant PRECISION_FACTOR = 10**12;

    // The reward token
    IRewardToken public rewardToken;

    // The WETH token
    address public weth;

    // The staked token
    IERC20 public stakedToken;

    // Info of each user that stakes tokens (stakedToken)
    mapping(address => UserInfo) public userInfo;

    // Dev address.
    address public devaddr;

    mapping (address => bool) private isRewardExempt;

    mapping (address => Share) public shares;

    uint256 public unallocatedWETHRewards;
    uint256 public totalShares;
    uint256 public totalRewardsWETH;
    uint256 public totalDistributedWETH;
    uint256 public rewardsPerShareWETH;
    uint256 public rewardsPerShareAccuracyFactor = 10 ** 36;    
    uint256 public totalStakedTokens;

    PresaleToken[] public presaleTokenList;
    bool private checkDuplicateEnabled; 
    mapping(address => uint256) public entitledTokenReward;
    mapping(address => mapping (address => bool)) public hasClaimed;

    event AdminTokenRecovery(address tokenRecovered, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndTimes(uint256 startTime, uint256 endTime);
    event NewRewardPerSecond(uint256 rewardPerSecond, uint256 rewardPerDay);
    event NewPoolLimit(uint256 poolLimitPerUser);
    event RewardsStop(uint256 timestamp);
    event Withdraw(address indexed user, uint256 amount);
    event NewLockTime(uint256 lockTime);
    event StakedAndMinted(address indexed _address, uint256 timestamp);
    event UnstakedAndBurned(address indexed _address, uint256 timestamp);

    // performs safety checks when depositing.
    modifier depositCheck(address _presaleTokenAddress, uint256 _amount) {
        require(IERC20(_presaleTokenAddress).balanceOf(msg.sender) >= _amount, 
            "Deposit amount exceeds balance!"); 
        require(msg.sender != address(0) || msg.sender != 0x000000000000000000000000000000000000dEaD, 
            "Cannot deposit from address(0)!");
        require(_amount != 0 , "Cannot deposit 0 tokens!");
        require(totalStakedTokens != 0 , "Nobody is staked!");
        _;
    }

    modifier onlyToken {
        require(msg.sender == address(stakedToken), "Caller not authorized");
        _;
    }

    modifier whenInitialized {
        require(isInitialized, "Contract not initialized yet");
        _;
    }

    constructor(
        address _deployer,
        address _stakedToken, 
        address _rewardToken
    ) ERC20("","") {
        _transferOwnership(_deployer);
        stakedToken = IERC20(_stakedToken);
        rewardToken = IRewardToken(_rewardToken);
        pyeSlice = address(new PYESlice());
    }

    function initialize(
        uint256 _rewardPerDay, 
        uint256 _startTime, 
        uint256 _lockTime,
        address _weth
    ) external onlyOwner {
        require(!isInitialized, "Contract already initialized");
        rewardPerDay = _rewardPerDay;
        rewardPerSecond = _rewardPerDay / 86400;
        startTime = _startTime;
        bonusEndTime = 9999999999;
        lockTime = _lockTime;
        lastRewardTime = _startTime;
        weth = _weth;

        isRewardExempt[address(this)] = true;

        isInitialized = true;
        emit NewRewardPerSecond(rewardPerSecond, _rewardPerDay);
    }
    
    function deposit(uint256 _amount) external whenInitialized nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        if (hasUserLimit) {
            require(_amount + user.amount <= poolLimitPerUser, "User amount above limit");
        }

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
            }
        }

        if (_amount > 0) {

            // begin slice logic
            uint256 currentStakedBalance = user.amount; // current staked balance
            uint256 currentPYESliceBalance = IERC20(pyeSlice).balanceOf(msg.sender);

            if (currentStakedBalance == 0 && currentPYESliceBalance == 0) {
                _beforeTokenTransfer(msg.sender, address(this), _amount);
                stakedToken.safeTransferFrom(msg.sender, address(this), _amount);
                user.amount += _amount;
                IPYESlice(pyeSlice).mintPYESlice(msg.sender, 1);
                totalStakedTokens += _amount;
                if(!isRewardExempt[msg.sender]){ setShare(msg.sender, user.amount); }
                user.depositTime = block.timestamp;
                emit StakedAndMinted(msg.sender, block.timestamp);
            } else {
                _beforeTokenTransfer(msg.sender, address(this), _amount);
                stakedToken.safeTransferFrom(msg.sender, address(this), _amount);
                user.amount += _amount;
                totalStakedTokens += _amount;
                if(!isRewardExempt[msg.sender]){ setShare(msg.sender, user.amount); }
                user.depositTime = block.timestamp; 
            }
        } else {
            distributeRewardWETH(msg.sender);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;

        emit Deposit(msg.sender, _amount);
    }

    function harvest() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;
            if (pending > 0) {
                safeRewardTransfer(msg.sender, pending);
            }
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");
        require(user.depositTime + lockTime < block.timestamp, "Can not withdraw in lock period");

        _updatePool();

        uint256 pending = ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;

        if (_amount > 0) {

            // begin slice logic
            uint256 currentStakedBalance = user.amount; // current staked balance
            uint256 currentPYESliceBalance = IERC20(pyeSlice).balanceOf(msg.sender);

            if (currentStakedBalance - _amount == 0 && currentPYESliceBalance > 0) {
                user.amount -= _amount;
                _beforeTokenTransfer(address(this), msg.sender, _amount);
                stakedToken.safeTransfer(msg.sender, _amount);
                IPYESlice(pyeSlice).burnPYESlice(msg.sender, currentPYESliceBalance);
                totalStakedTokens -= _amount;
                if(!isRewardExempt[msg.sender]){ setShare(msg.sender, user.amount); }
                emit UnstakedAndBurned(msg.sender, block.timestamp);
            } else {
                user.amount -= _amount;
                _beforeTokenTransfer(address(this), msg.sender, _amount);
                stakedToken.safeTransfer(msg.sender, _amount);
                totalStakedTokens -= _amount;
                if(!isRewardExempt[msg.sender]){ setShare(msg.sender, user.amount); }
            }
        }

        if (pending > 0) {
            safeRewardTransfer(msg.sender, pending);
        }

        user.rewardDebt = (user.amount * accTokenPerShare) / PRECISION_FACTOR;

        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        uint256 currentPYESliceBalance = IERC20(pyeSlice).balanceOf(msg.sender);
        _beforeTokenTransfer(address(this), msg.sender, user.amount);

        if (amountToTransfer > 0) {
            stakedToken.safeTransfer(msg.sender, amountToTransfer);
            IPYESlice(pyeSlice).burnPYESlice(msg.sender, currentPYESliceBalance);
            totalStakedTokens -= amountToTransfer;
            emit UnstakedAndBurned(msg.sender, block.timestamp);
        }

        if(!isRewardExempt[msg.sender]){ setShare(msg.sender, 0); }

        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(stakedToken), "Cannot be staked token");
        require(_tokenAddress != address(rewardToken), "Cannot be reward token");

        IERC20(_tokenAddress).safeTransfer(msg.sender, _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        bonusEndTime = block.timestamp;
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
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
     * @param _lockTime: the time in seconds that staked tokens are locked
     */
    function updateLockTime(uint256 _lockTime) external onlyOwner {
        lockTime = _lockTime;
        emit NewLockTime(_lockTime);
    }

    /*
     * @notice Update reward per second
     * @dev Only callable by owner. Reward per day is converted to rewardPerSecond
     * @param _rewardPerDay: the reward per day
     */
    function updateRewardPerDay(uint256 _rewardPerDay) external onlyOwner {
        rewardPerDay = _rewardPerDay;
        rewardPerSecond = _rewardPerDay / 86400;
        emit NewRewardPerSecond(rewardPerSecond, _rewardPerDay);
    }

    /**
     * @notice It allows the admin to update start and end times
     * @dev This function is only callable by owner.
     * @param _startTime: the new start time
     * @param _bonusEndTime: the new end time
     */
    function updateStartAndEndTimes(uint256 _startTime, uint256 _bonusEndTime) external onlyOwner {
        require(_startTime < _bonusEndTime, "New startTime must be lower than new endTime");
        require(block.timestamp < _startTime, "New startTime must be higher than now");

        startTime = _startTime;
        bonusEndTime = _bonusEndTime;

        // Set the lastRewardTime as the startTime
        lastRewardTime = startTime;

        emit NewStartAndEndTimes(_startTime, _bonusEndTime);
    }

    function setIsRewardExempt(address holder, bool exempt) external onlyOwner {
        require(holder != address(this), "Can not set contract");
        UserInfo storage user = userInfo[holder];
        isRewardExempt[holder] = exempt;
        if(exempt){
            setShare(holder, 0);
        }else{
            setShare(holder, user.amount);
        }
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        
        if (block.timestamp > lastRewardTime && totalStakedTokens != 0) {
            uint256 multiplier = _getMultiplier(lastRewardTime, block.timestamp);
            uint256 reward = multiplier * rewardPerSecond;
            uint256 adjustedTokenPerShare =
                accTokenPerShare + ((reward * PRECISION_FACTOR) / totalStakedTokens);
            return ((user.amount * adjustedTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;
        } else {
            return ((user.amount * accTokenPerShare) / PRECISION_FACTOR) - user.rewardDebt;
        }
    }

    function isExcludedFromReward(address account) external view returns (bool) {
        return isRewardExempt[account];
    }

    // Safe reward transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBalance = rewardToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBalance) {
            transferSuccess = rewardToken.transferReward(_to, tokenBalance);
        } else {
            transferSuccess = rewardToken.transferReward(_to, _amount);
        }
        require(transferSuccess, "safeTokenTransfer: transfer failed");
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.timestamp <= lastRewardTime) {
            return;
        }

        if (totalStakedTokens == 0) {
            lastRewardTime = block.timestamp;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardTime, block.timestamp);
        uint256 reward = multiplier * rewardPerSecond;
        if (devfee > 0) { rewardToken.mint(devaddr, ((reward * devfee) / 10000)); }
        rewardToken.mint(address(this), reward);
        accTokenPerShare = accTokenPerShare + ((reward * PRECISION_FACTOR) / totalStakedTokens);
        lastRewardTime = block.timestamp;
    }
    
    /*
     * @notice Return reward multiplier over the given _from to _to times.
     * @param _from: time to start
     * @param _to: time to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndTime) {
            return _to - _from;
        } else if (_from >= bonusEndTime) {
            return 0;
        } else {
            return bonusEndTime - _from;
        }
    }
    
    function setShare(address staker, uint256 amount) internal {
        if(shares[staker].amount > 0){
            distributeRewardWETH(staker);
        }

        totalShares = (totalShares - shares[staker].amount) + amount;
        shares[staker].amount = amount;
        shares[staker].totalExcludedWETH = getCumulativeRewardsWETH(shares[staker].amount);
    }
    
    // WETH STUFF

    function distributeRewardWETH(address staker) internal {
        if(shares[staker].amount == 0){ return; }

        uint256 amount = getUnpaidEarningsWETH(staker);
        if(amount > 0){
            totalDistributedWETH += amount;
            shares[staker].totalRealisedWETH += amount;
            shares[staker].totalExcludedWETH = getCumulativeRewardsWETH(shares[staker].amount);
            IERC20(weth).safeTransfer(staker, amount);
        }
    }

    function claimWETH() external {
        distributeRewardWETH(msg.sender);
    }

    function getUnpaidEarningsWETH(address staker) public view returns (uint256) {
        if(shares[staker].amount == 0){ return 0; }

        uint256 stakerTotalRewardsWETH = getCumulativeRewardsWETH(shares[staker].amount);
        uint256 stakerTotalExcludedWETH = shares[staker].totalExcludedWETH;

        if(stakerTotalRewardsWETH <= stakerTotalExcludedWETH){ return 0; }

        return stakerTotalRewardsWETH - stakerTotalExcludedWETH;
    }

    function getCumulativeRewardsWETH(uint256 share) internal view returns (uint256) {
        return (share * rewardsPerShareWETH) / rewardsPerShareAccuracyFactor;
    }

    function setFee(address _feeAddress, uint256 _devfee) public onlyOwner {
        devaddr = _feeAddress;
        devfee = _devfee;
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyWETHWithdraw(uint256 _amount) external onlyOwner {
        IERC20(weth).safeTransfer(msg.sender, _amount);
    }

    //--------------------- BEGIN DONATION FUNCTIONS -------------

    function addWETHDonation(uint256 _amount) external nonReentrant {
        IERC20(weth).safeTransferFrom(msg.sender, address(this), _amount);
        totalRewardsWETH += _amount;
        rewardsPerShareWETH += (rewardsPerShareAccuracyFactor * _amount) / totalShares;
        totalDonations += _amount;
    }

    //--------------------BEGIN MODIFIED SNAPSHOT FUNCITONALITY---------------

    // @dev a modified implementation of ERC20 Snapshot to keep track of staked balances rather than balanceOf. 
    // ERC20 Snapshot import/inheritance is avoided in this contract to avoid issues with interface conflicts and 
    // to directly control private functionality to keep snapshots of staked balances instead.
    // copied from source: openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol

    using Arrays for uint256[];
    using Counters for Counters.Counter;
    Counters.Counter private _currentSnapshotId;

    struct Snapshots {
        uint256[] ids;
        uint256[] values;
    }

    mapping(address => Snapshots) private _accountBalanceSnapshots;
    Snapshots private _totalStakedSnapshots;

    // @dev Emitted by {_snapshot} when a snapshot identified by `id` is created.
    event Snapshot(uint256 id);

    // generate a snapshot, calls internal _snapshot().
    function snapshot() public onlyOwner {
        _snapshot();
    }

    function _snapshot() internal returns (uint256) {
        _currentSnapshotId.increment();

        uint256 currentId = _getCurrentSnapshotId();
        emit Snapshot(currentId);
        return currentId;
    }

    function _getCurrentSnapshotId() internal view returns (uint256) {
        return _currentSnapshotId.current();
    }

    // @dev returns shares of a holder, not balanceOf, at a certain snapshot.
    function sharesOfAt(address account, uint256 snapshotId) public view returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _accountBalanceSnapshots[account]);

        return snapshotted ? value : shares[account].amount;
    }

    // @dev returns totalStakedTokens at a certain snapshot
    function totalStakedAt(uint256 snapshotId) public view returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _totalStakedSnapshots);

        return snapshotted ? value : totalStakedTokens;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            // mint
            _updateAccountSnapshot(to);
            _updateTotalStakedSnapshot();
        } else if (to == address(0)) {
            // burn
            _updateAccountSnapshot(from);
            _updateTotalStakedSnapshot();
        } else if (to == address(this)) {
            // user is staking
            _updateAccountSnapshot(from);
            _updateTotalStakedSnapshot();
        } else if (from == address(this)) {
            // user is unstaking
            _updateAccountSnapshot(to);
            _updateTotalStakedSnapshot();
        }
    }

    function _valueAt(uint256 snapshotId, Snapshots storage snapshots) private view returns (bool, uint256) {
        require(snapshotId > 0, "ERC20Snapshot: id is 0");
        require(snapshotId <= _getCurrentSnapshotId(), "ERC20Snapshot: nonexistent id");

        // When a valid snapshot is queried, there are three possibilities:
        //  a) The queried value was not modified after the snapshot was taken. Therefore, a snapshot entry was never
        //  created for this id, and all stored snapshot ids are smaller than the requested one. The value that
        //  corresponds to this id is the current one.
        //  b) The queried value was modified after the snapshot was taken. Therefore, there will be an entry with the
        //  requested id, and its value is the one to return.
        //  c) More snapshots were created after the requested one, and the queried value was later modified. There will
        //  be no entry for the requested id: the value that corresponds to it is that of the smallest snapshot id
        //  that is larger than the requested one.
        //
        // In summary, we need to find an element in an array, returning the index of the smallest value that is larger
        // if it is not found, unless said value doesn't exist (e.g. when all values are smaller).
        // Arrays.findUpperBound does exactly this.

        uint256 index = snapshots.ids.findUpperBound(snapshotId);

        if (index == snapshots.ids.length) {
            return (false, 0);
        } else {
            return (true, snapshots.values[index]);
        }
    }

    function _updateAccountSnapshot(address account) private {
        _updateSnapshot(_accountBalanceSnapshots[account], shares[account].amount);
    }

    function _updateTotalStakedSnapshot() private {
        _updateSnapshot(_totalStakedSnapshots, totalStakedTokens);
    }

    function _updateSnapshot(Snapshots storage snapshots, uint256 currentValue) private {
        uint256 currentId = _getCurrentSnapshotId();
        if (_lastSnapshotId(snapshots.ids) < currentId) {
            snapshots.ids.push(currentId);
            snapshots.values.push(currentValue);
        }
    }

    function _lastSnapshotId(uint256[] storage ids) private view returns (uint256) {
        if (ids.length == 0) {
            return 0;
        } else {
            return ids[ids.length - 1];
        }
    }

    // ------------------ BEGIN PRESALE TOKEN FUNCTIONALITY -------------------

    // @dev deletes the last struct in the presaleTokenList. 
    function popToken() internal {
        presaleTokenList.pop();
    }

    // returns number of presale Tokens stored.
    function getTokenArrayLength() public view returns (uint256) {
        return presaleTokenList.length;
    }

    // @dev enter the address of token to delete. avoids empty gaps in the middle of the array.
    function deleteToken(address _address) public onlyOwner {
        uint tokenLength = presaleTokenList.length;
        for(uint i = 0; i < tokenLength; i++) {
            if (_address == presaleTokenList[i].presaleTokenAddress) {
                if (1 < presaleTokenList.length && i < tokenLength - 1) {
                    presaleTokenList[i] = presaleTokenList[tokenLength - 1]; }
                    delete presaleTokenList[tokenLength - 1];
                    popToken();
                    break;
            }
        }
    }

    // @dev create presale token and fund it. requires allowance approval from token. 
    function createAndFundPresaleToken(
        string memory _presaleTokenName, 
        address _presaleTokenAddress, 
        uint256 _amount
    ) external onlyOwner depositCheck(_presaleTokenAddress, _amount) {
        // check duplicates
        if (checkDuplicateEnabled) { checkDuplicates(_presaleTokenAddress); }

        // deposit the token
        IERC20(_presaleTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        // store staked balances at time of reward token deposit
        _snapshot();
        // push new struct, with most recent snapshot ID
        presaleTokenList.push(PresaleToken(
            _presaleTokenName, 
            _presaleTokenAddress, 
            _amount, 
            (rewardsPerShareAccuracyFactor * _amount) / totalStakedTokens, 
            0,
            _getCurrentSnapshotId()));
    }

    // @dev change whether or not createAndFundToken should check for duplicate presale tokens
    function shouldCheckDuplicates(bool _bool) external onlyOwner {
        checkDuplicateEnabled = _bool;
    }

    // @dev internal helper function that checks the array for preexisting addresses
    function checkDuplicates(address _presaleTokenAddress) internal view {
        for(uint i = 0; i < presaleTokenList.length; i++) {
            if (_presaleTokenAddress == presaleTokenList[i].presaleTokenAddress) {
                revert("Token already exists!");
            }
        }
    }

    //------------------- BEGIN PRESALE-TOKEN TRANSFER FXNS AND STRUCT MODIFIERS --------------------

    // @dev update an existing token's balance based on index.
    function fundExistingToken(
        uint256 _index, 
        uint256 _amount
    ) external onlyOwner depositCheck(
        presaleTokenList[_index].presaleTokenAddress, 
        _amount
    ) {
        require(_index <= presaleTokenList.length , "Index out of bounds!");

        if (
            (bytes(presaleTokenList[_index].presaleTokenName)).length == 0 || 
            presaleTokenList[_index].presaleTokenAddress == address(0)
        ) {
            revert("Attempting to fund non-existant token");
        }

        // do the transfer
        uint256 presaleTokenBalanceBefore = presaleTokenList[_index].presaleTokenBalance;
        uint256 presaleTokenRewardsPerShareBefore = presaleTokenList[_index].presaleTokenRewardsPerShare;
        IERC20(presaleTokenList[_index].presaleTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        _snapshot();
        // update struct balances to add amount
        presaleTokenList[_index].presaleTokenBalance = presaleTokenBalanceBefore + _amount;
        presaleTokenList[_index].presaleTokenRewardsPerShare = presaleTokenRewardsPerShareBefore + 
            ((rewardsPerShareAccuracyFactor * _amount) / totalStakedTokens);
        
    }

    // remove unsafe or compromised token from availability
    function withdrawExistingToken(uint256 _index) external onlyOwner {
        require(_index <= presaleTokenList.length , "Index out of bounds!");
        
        if (
            (bytes(presaleTokenList[_index].presaleTokenName)).length == 0 || 
            presaleTokenList[_index].presaleTokenAddress == address(0)
        ) {
            revert("Attempting to withdraw non-existant token");
        }

        // update struct balances to subtract amount
        presaleTokenList[_index].presaleTokenBalance = 0;
        presaleTokenList[_index].presaleTokenRewardsPerShare = 0;

        // do the transfer
        IERC20(presaleTokenList[_index].presaleTokenAddress).safeTransfer(
            msg.sender, 
            presaleTokenList[_index].presaleTokenBalance
        );
    }

    //-------------------------------- BEGIN PRESALE TOKEN REWARD FUNCTION-----------

    function claimPresaleToken(uint256 _index) external nonReentrant {
        require(_index <= presaleTokenList.length, "Index out of bounds!");
        require(
            !hasClaimed[msg.sender][presaleTokenList[_index].presaleTokenAddress], 
            "You have already claimed your reward!"
        );
        // calculate reward based on share at time of current snapshot (which is when a token is funded or created)
        if (sharesOfAt(msg.sender, presaleTokenList[_index].presaleTokenSnapshotId) == 0) { 
            entitledTokenReward[msg.sender] = 0; 
        } else { 
            entitledTokenReward[msg.sender] = 
                (sharesOfAt(msg.sender, presaleTokenList[_index].presaleTokenSnapshotId) * 
                presaleTokenList[_index].presaleTokenRewardsPerShare) / rewardsPerShareAccuracyFactor; 
        }
        
        require(
            presaleTokenList[_index].presaleTokenBalance >= entitledTokenReward[msg.sender],
            "Insufficient balance"
        );
        // struct balances before transfer
        uint256 presaleTokenBalanceBefore = presaleTokenList[_index].presaleTokenBalance;
        uint256 presaleTokenTotalDistributedBefore = presaleTokenList[_index].presaleTokenTotalDistributed;
        hasClaimed[msg.sender][presaleTokenList[_index].presaleTokenAddress] = true;
        // update struct balances 
        presaleTokenList[_index].presaleTokenBalance = 
            presaleTokenBalanceBefore - entitledTokenReward[msg.sender];
        presaleTokenList[_index].presaleTokenTotalDistributed = 
            presaleTokenTotalDistributedBefore + entitledTokenReward[msg.sender];   

        // transfer
        IERC20(presaleTokenList[_index].presaleTokenAddress).safeTransfer(msg.sender, entitledTokenReward[msg.sender]);    
    }

    // allows user to see their entitled presaleToken reward based on staked balance at time of token creation
    function getUnpaidEarningsPresale(uint256 _index, address staker) external view returns (uint256) {
        uint256 entitled;
        if (hasClaimed[staker][presaleTokenList[_index].presaleTokenAddress]) {
            entitled = 0;
        } else {
            entitled = (sharesOfAt(staker, presaleTokenList[_index].presaleTokenSnapshotId) * 
                presaleTokenList[_index].presaleTokenRewardsPerShare) / rewardsPerShareAccuracyFactor;
        }
        return entitled;
    }
}

