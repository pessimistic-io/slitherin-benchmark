// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./UUPSUpgradeable.sol";

import "./IUnlimitedStaking.sol";
import "./IRewardWallet.sol";
import "./IStakingDepositNFT.sol";


/// @title UnlimitedStaking
/// @notice The UnlimitedStaking contract is a smart contract that allows users to stake their 
/// UWU tokens in order to earn rewards. The contract consists of several parts, including 
/// epochs, rewards, and user information. Epochs represent different staking options, each
/// lock period its unique multiplier. Users can deposit their UWU tokens
/// into a epoch and receive boosted shares, which are used to calculate their share of the
/// epoch's rewards.
contract UnlimitedStaking is IUnlimitedStaking, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice Address of UWU contract.
    IERC20Upgradeable public UWU;
    /// @notice Address of UWU Locked Deposit NFT.
    IStakingDepositNFT public uwuStakingNft;
    /// @notice Total count deposits of all time. Define UWU Locked Deposit NFT Id.
    uint256 public lockedDepositsCount;

    IRewardWallet public uwuStaticRewardWallet;
    IRewardWallet public uwuDynamicRewardWallet;

    RewardInfo[] public rewardInfo;
    DynamicRewardInfo public dynamicRewardInfo;

    mapping(uint256 => EpochInfo) public epochInfo;
    uint256 public currentEpochNumber;
    uint256 public epochPeriod;  

    mapping(uint256 => UserInfo) public userInfo;
    mapping(uint256 => uint256) public lockPeriodMultiplier;
    uint256[] public lockPeriods;

    uint256 public constant ACC_UWU_PRECISION = 1e18;

    /// @notice Basic boost factor, none boosted user's boost factor
    uint256 public constant BOOST_PRECISION = 100 * 1e10;
    /// @notice Hard limit for maxmium boost factor, it must greater than BOOST_PRECISION
    uint256 public constant MAX_BOOST_PRECISION = 200 * 1e10;

    bytes32 public constant INITIALIZER_FIRST_EPOCH_ROLE = keccak256("INITIALIZER_FIRST_EPOCH_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");
    bytes32 public constant LOCK_PERIOD_MANAGER_ROLE = keccak256("LOCK_PERIOD_MANAGER_ROLE");

    modifier onlyDepositOwner(uint256 _tokenId) {
        address depositOwner = uwuStakingNft.ownerOf(_tokenId);
        require(
            depositOwner == msg.sender ||
            uwuStakingNft.getApproved(_tokenId) == msg.sender ||
            uwuStakingNft.isApprovedForAll(depositOwner, msg.sender),
            "Not the owner or approved"
        );
        _;
    }

    function initialize(
        IERC20Upgradeable _UWU,
        IStakingDepositNFT _uwuNft,
        IRewardWallet _uwuStaticRewardWallet,
        IRewardWallet _uwuDynamicRewardWallet,
        uint256 _epochPeriod
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(INITIALIZER_FIRST_EPOCH_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        _grantRole(REWARD_MANAGER_ROLE, msg.sender);
        _grantRole(LOCK_PERIOD_MANAGER_ROLE, msg.sender);

        UWU = _UWU;
        uwuStakingNft = _uwuNft;
        uwuStaticRewardWallet = _uwuStaticRewardWallet;
        uwuDynamicRewardWallet = _uwuDynamicRewardWallet;
        epochPeriod = _epochPeriod;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function initializeFirstEpoch() external onlyRole(INITIALIZER_FIRST_EPOCH_ROLE) {
        require(currentEpochNumber == 0, "Current epoch must be zero");
        uint256 lockSupply = epochInfo[currentEpochNumber].totalNextBoostedShare;
        uint256 totalAmountStaked = epochInfo[currentEpochNumber].totalAmountStaked;

        currentEpochNumber++;
        epochInfo[currentEpochNumber].totalCurrentBoostedShare = lockSupply;
        epochInfo[currentEpochNumber].totalNextBoostedShare = lockSupply;
        epochInfo[currentEpochNumber].totalAmountStaked = totalAmountStaked;
        epochInfo[currentEpochNumber].endTime = block.timestamp.add(epochPeriod);
        
        updateEpoch();
    }

    /**
     * @notice Get the total number of static rewards.
     * @return rewards Total number of static rewards.
     */
    function rewardLength() public view override returns (uint256 rewards) {
        rewards = rewardInfo.length;
    }

    /**
     * @notice Add static reward to the contract.
     * @param _amount Amount of tokens to add.
     * @param _startEpoch Start epoch of the reward.
     * @param _endEpoch End epoch of the reward.
     */
    function addStaticReward(
        uint256 _amount,
        uint256 _startEpoch,
        uint256 _endEpoch
    ) external override onlyRole(REWARD_MANAGER_ROLE) {
        updateEpoch();
        require(_startEpoch > currentEpochNumber, "Start must be > than current");
        require(_endEpoch > _startEpoch, "End must be > than start");
        require(_amount > 0, "Amount must be greater than 0");

        rewardInfo.push(
            RewardInfo({
                totalAmountStatic: _amount,
                startEpoch: _startEpoch,
                endEpoch: _endEpoch
            })
        );

        emit StaticRewardAdded(_amount, _startEpoch, _endEpoch);
    }

    /**
     * @notice Add dynamic reward to the contract.
     * @param _startEpoch Start epoch of the reward.
     * @param _endEpoch End epoch of the reward.
     */
    function addDynamicReward(
        uint256 _startEpoch,
        uint256 _endEpoch
    ) external override onlyRole(REWARD_MANAGER_ROLE) {
        updateEpoch();
        require(_startEpoch > currentEpochNumber, "Start must be > than current");
        require(_endEpoch > _startEpoch, "End must be > than start");
        require(currentEpochNumber > dynamicRewardInfo.endEpoch, "Already initialized");

        dynamicRewardInfo.totalRewardDept = 0;
        dynamicRewardInfo.lastBalance = UWU.balanceOf(address(uwuDynamicRewardWallet));
        dynamicRewardInfo.lastBalanceUpdateTime = block.timestamp;
        dynamicRewardInfo.startEpoch = _startEpoch;
        dynamicRewardInfo.endEpoch = _endEpoch;

        emit DynamicRewardAdded(_startEpoch, _endEpoch);
    }

    /**
     * @notice Add a new lock period.
     * @param _lockPeriod Lock period of the stake.
     * @param _multiplier Multiplier of the stake.
     */
    function addLockPeriod(
        uint256 _lockPeriod,
        uint256 _multiplier
    ) external override onlyRole(LOCK_PERIOD_MANAGER_ROLE) {
        require(_multiplier >= BOOST_PRECISION, "Multiplier must be >= to the min");
        require(_multiplier <= MAX_BOOST_PRECISION, "Multiplier must be <= to the max");
        require(lockPeriodMultiplier[_lockPeriod] == 0, "Lock period already exists");

        lockPeriodMultiplier[_lockPeriod] = _multiplier;
        lockPeriods.push(_lockPeriod);

        emit LockPeriodAdded(_lockPeriod, _multiplier);
    }

    /**
     * @notice Edit an existing lock period.
     * @param _lockPeriod New lock period of the stake.
     * @param _multiplier New multiplier of the stake.
     */
    function editLockPeriod(
        uint256 _lockPeriod,
        uint256 _multiplier
    ) external override onlyRole(LOCK_PERIOD_MANAGER_ROLE) {
        require(_multiplier >= BOOST_PRECISION, "Multiplier must be >= to the min");
        require(_multiplier <= MAX_BOOST_PRECISION, "Multiplier must be <= to the max");
        require(lockPeriodMultiplier[_lockPeriod] != 0, "Lock period does not exist");

        lockPeriodMultiplier[_lockPeriod] = _multiplier;

        emit LockPeriodEdited(_lockPeriod, _multiplier);
    }

    /**
     * @notice Remove an existing lock period.
     * @param _lockPeriod Lock period of the stake to remove.
     */
    function removeLockPeriod(uint256 _lockPeriod) external override onlyRole(LOCK_PERIOD_MANAGER_ROLE) {
        require(lockPeriodMultiplier[_lockPeriod] != 0, "Lock period does not exist");

        uint256 indexToRemove = lockPeriods.length;
        for (uint256 i = 0; i < lockPeriods.length; i++) {
            if (lockPeriods[i] == _lockPeriod) {
                indexToRemove = i;
                break;
            }
        }

        require(indexToRemove < lockPeriods.length, "Lock period not found in array");

        for (uint256 i = indexToRemove; i < lockPeriods.length - 1; i++) {
            lockPeriods[i] = lockPeriods[i + 1];
        }
        lockPeriods.pop();

        delete lockPeriodMultiplier[_lockPeriod];

        emit LockPeriodRemoved(_lockPeriod);
    }

    /**
     * @notice Get the static reward amount per epoch for a specific reward ID.
     * @param _uwuRewardId Reward ID to get the static reward amount for.
     * @return amount Static reward amount per epoch.
     */
    function uwuStaticPerBlock(uint256 _uwuRewardId) public view returns (uint256 amount) {
        RewardInfo memory reward = rewardInfo[_uwuRewardId]; 
        amount = reward.totalAmountStatic.div(reward.endEpoch.sub(reward.startEpoch));
    }

    /**
     * @notice Get the user's pending rewards for a specific token ID.
     * @param _tokenId Token ID to get pending rewards for.
     * @return amount Pending rewards amount.
     */
    function userPendingRewards(uint256 _tokenId) public view returns (uint256 amount) {
        UserInfo memory user = userInfo[_tokenId];
        (uint256 earliestUnclaimedEpoch, uint256 intervalMultiplier, uint256 latestUnclaimedEpoch) =
            calculateUnclaimedEpochIntervals(user.withdrawEpoch, user.resetEpoch, user.lastClaimEpoch, user.multiplier);

        (uint256 totalStaticUnclaimed, uint256 totalDynamicUnclaimed) =
            _calculateRewards(
                user.lastClaimEpoch,
                earliestUnclaimedEpoch,
                latestUnclaimedEpoch,
                user.compoundEpoch,
                user.lastCompoundDelta,
                user.amount,
                intervalMultiplier
            );

        return totalStaticUnclaimed.add(totalDynamicUnclaimed);
    }

    /**
     * @notice Get the user's reward for a specific token ID and epoch.
     * @param _tokenId Token ID to get the reward for.
     * @param _epoch Epoch to get the reward for.
     * @return Reward amount for the specified token ID and epoch.
     */
    function getUserRewardForEpoch(uint256 _tokenId, uint256 _epoch) public view override returns (uint256) {
        UserInfo memory user = userInfo[_tokenId];
        EpochInfo memory epoch = epochInfo[_epoch];

        if (epoch.endTime > user.depositDate.add(epochPeriod)) {
            uint256 userMultiplier = user.resetEpoch >= _epoch ? BOOST_PRECISION : user.multiplier;
            uint256 boostedAmount = user.amount.mul(userMultiplier).div(BOOST_PRECISION);
            uint256 totalStaticUnclaimed = boostedAmount.mul(epoch.accRewardPerShare).div(ACC_UWU_PRECISION);
            uint256 totalDynamicUnclaimed = boostedAmount.mul(epoch.accDynamicRewardPerShare).div(ACC_UWU_PRECISION);

            return totalStaticUnclaimed.add(totalDynamicUnclaimed);
        }

        return 0;
    }

    /**
     * @dev Updates the information related to the current epoch.
     *
     * This function performs the following actions:
     * - If the current epoch has not been updated, it updates the accumulated static reward per share.
     * - Updates the accumulated dynamic reward per share.
     * - Sets the 'isUpdated' flag for the current epoch to true.
     * - If the current epoch has ended, it initializes the next epoch with the appropriate values.
     *
     * @return currentEpoch - The updated EpochInfo struct for the current epoch.
    */
    function updateEpoch() public override whenNotPaused returns (EpochInfo memory) {
        EpochInfo memory currentEpoch = epochInfo[currentEpochNumber];
        uint256 lockSupply = currentEpoch.totalCurrentBoostedShare;

        if (lockSupply > 0) {
            if (!currentEpoch.isUpdated) {
                for (uint256 i = 0; i < rewardInfo.length; i++) {
                    RewardInfo memory reward = rewardInfo[i];
                    if (reward.startEpoch <= currentEpochNumber && reward.endEpoch > currentEpochNumber) {
                        uint256 uwuPerEpoch = reward.totalAmountStatic.div(reward.endEpoch.sub(reward.startEpoch));
                    
                        currentEpoch.accRewardPerShare = currentEpoch.accRewardPerShare.add((uwuPerEpoch.mul(ACC_UWU_PRECISION).div(lockSupply)));
                    }
                    emit EpochUpdated(currentEpochNumber, currentEpoch.accRewardPerShare);
                }
            }

            if (dynamicRewardInfo.startEpoch <= currentEpochNumber && dynamicRewardInfo.endEpoch > currentEpochNumber) {
                uint256 uwuDynamicBalance = UWU.balanceOf(address(uwuDynamicRewardWallet));
                uint256 uwuDynamicReward = uwuDynamicBalance.add(dynamicRewardInfo.totalRewardDept).sub(dynamicRewardInfo.lastBalance);
                currentEpoch.accDynamicRewardPerShare = currentEpoch.accDynamicRewardPerShare.add((uwuDynamicReward.mul(ACC_UWU_PRECISION).div(lockSupply)));

                dynamicRewardInfo.lastBalance = uwuDynamicBalance;
                dynamicRewardInfo.lastBalanceUpdateTime = block.timestamp;
            }
        }

        currentEpoch.isUpdated = true;
        epochInfo[currentEpochNumber] = currentEpoch;

        if (currentEpoch.endTime != 0 && block.timestamp > currentEpoch.endTime) {
            uint256 nextEpochNumber = ++currentEpochNumber;
            EpochInfo memory nextEpoch = epochInfo[nextEpochNumber];
            nextEpoch.endTime = currentEpoch.endTime.add(epochPeriod);
            nextEpoch.totalCurrentBoostedShare = currentEpoch.totalNextBoostedShare.sub(currentEpoch.totalNextResetBoostedShare);
            nextEpoch.totalNextBoostedShare = currentEpoch.totalNextBoostedShare.sub(currentEpoch.totalNextResetBoostedShare);
            nextEpoch.totalAmountStaked = currentEpoch.totalAmountStaked;
            
            epochInfo[nextEpochNumber] = nextEpoch;
            emit EpochChanged(nextEpochNumber, nextEpoch.totalCurrentBoostedShare, nextEpoch.totalAmountStaked);

            return updateEpoch();
        }

        return currentEpoch;
    }

    /**
     * @notice Deposit tokens and create a new stake.
     *
     * This function performs the following actions:
     * - Updates the current epoch information.
     * - Transfers the tokens from the user to the contract.
     * - Creates a new UserInfo struct for the user's deposit.
     * - Mints a new NFT representing the stake.
     * - Updates the total boosted share for the epoch.
     *   it sets a reset epoch for the user's stake and updates the total next reset boosted share.
     *
     * @param _amount Amount of tokens to deposit.
     * @param _lockPeriod Lock period for the stake in epochs.
    */
    function deposit(uint256 _amount, uint256 _lockPeriod) override external nonReentrant {
        _deposit(_amount, _lockPeriod, msg.sender);
    }

    function _deposit(uint256 _amount, uint256 _lockPeriod, address _owner) internal {
        require(_amount > 0, "Amount must be greater than 0");

        EpochInfo memory epoch = updateEpoch();
        uint256 multiplier = lockPeriodMultiplier[_lockPeriod];
        require(multiplier > 0, "Invalid lock period");

        uint256 before = UWU.balanceOf(address(this));
        UWU.safeTransferFrom(_owner, address(this), _amount);
        _amount = UWU.balanceOf(address(this)).sub(before);
        
        uint256 depositId = ++lockedDepositsCount;
        UserInfo storage user = userInfo[depositId];

        user.amount = _amount;
        user.depositDate = block.timestamp;
        user.multiplier = multiplier;
        user.lastClaimEpoch = currentEpochNumber + 1;
        user.lockPeriod = _lockPeriod;
        uwuStakingNft.mint(_owner, depositId);

        // Update total boosted share.
        uint256 userBoostedShare = _amount.mul(multiplier).div(BOOST_PRECISION);
        epoch.totalNextBoostedShare = epoch.totalNextBoostedShare.add(userBoostedShare);
        epoch.totalAmountStaked = epoch.totalAmountStaked.add(_amount);

        epochInfo[currentEpochNumber] = epoch;

        if (multiplier > BOOST_PRECISION && _lockPeriod > 0) {
            uint256 resetEpoch = _lockPeriod.div(epochPeriod).add(currentEpochNumber);
            user.resetEpoch = resetEpoch + 1;
            uint256 resetDelta = userBoostedShare.sub(_amount);
            epochInfo[resetEpoch].totalNextResetBoostedShare = epochInfo[resetEpoch].totalNextResetBoostedShare.add(resetDelta);
        }

        emit Deposited(depositId, _amount, _lockPeriod, multiplier, currentEpochNumber);
    }

    /**
     * @notice Deposit tokens with a permit and create a new stake.
     * @param _amount Amount of tokens to deposit.
     * @param _lockPeriod Lock period for the stake in epochs.
     * @param _depositOwner Owner of the deposit.
     * @param _value Value of the permit.
     * @param _deadline Deadline for the permit.
     * @param _v Recovery byte of the permit signature.
     * @param _r First 32 bytes of the permit signature.
     * @param _s Second 32 bytes of the permit signature.
     */
    function depositPermit(
        uint256 _amount, 
        uint256 _lockPeriod,
        address _depositOwner,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override nonReentrant {
        SafeERC20Upgradeable.safePermit(IERC20PermitUpgradeable(address(UWU)), _depositOwner, address(this), _value, _deadline, _v, _r, _s);

        _deposit(_amount, _lockPeriod, _depositOwner);
    }

    /**
     * @notice Claim rewards for all provided token IDs.
     * @param _tokenIds Array of token IDs to claim rewards for.
     */
    function claimAll(uint256[] memory _tokenIds) external override nonReentrant {
        updateEpoch();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _claim(_tokenIds[i]);
        }
    }

    /**
     * @notice Claim the pending rewards for a specific stake represented by the token ID.
     *
     * This function performs the following actions:
     * - Updates the current epoch information.
     * - Verifies that the caller is the owner, has been approved, or has been granted approval for all.
     * - Ensures that the last claimed epoch is less than the current epoch.
     * - Settles the pending rewards for the stake.
     * - Updates the user's last claimed epoch to the current epoch.
     *
     * @param _tokenId The token ID representing the stake for which to claim rewards.
    */
    function claim(uint256 _tokenId) external override nonReentrant {
        updateEpoch();
        _claim(_tokenId);        
    }

    function _claim(uint256 _tokenId) internal {
        address depositOwner = uwuStakingNft.ownerOf(_tokenId);

        require(depositOwner == msg.sender
            || uwuStakingNft.getApproved(_tokenId) == msg.sender
            || uwuStakingNft.isApprovedForAll(depositOwner, msg.sender), "Not the owner or approved");

        UserInfo storage user = userInfo[_tokenId];
        require(user.amount > 0, "User amount must be > 0");
        require(currentEpochNumber > user.lastClaimEpoch, "User last epoch number must be less than current epoch number");

        uint256 claimedAmount = settlePendingUwu(depositOwner, _tokenId);
        
        user.lastClaimEpoch = currentEpochNumber;
        userInfo[_tokenId] = user;

        emit Claimed(_tokenId, msg.sender, claimedAmount);
    }

    /**
    * @notice Request the withdrawal of a stake represented by the token ID.
     *
     * This function performs the following actions:
     * - Verifies that the caller is the owner, has been approved, or has been granted approval for all.
     * - Updates the current epoch information.
     * - Ensures that the current epoch number is greater than or equal to the user's last claimed epoch.
     * - Ensures that the current time is greater than unlock time.
     * - Sets the withdraw epoch for the user to the next epoch.
     * - Decreases the total boosted shares and total staked amount for the current epoch.
     *
     * @param _tokenId The token ID representing the stake for which to request a withdrawal.
    */
    function withdrawRequest(uint256 _tokenId) external override onlyDepositOwner(_tokenId) nonReentrant {
        EpochInfo memory epoch = updateEpoch();
        UserInfo storage user = userInfo[_tokenId];

        require(user.amount > 0, "Withdraw: Insufficient balance to withdraw");
        require(user.withdrawEpoch == 0, "Withdraw: A withdraw request has already been made for this deposit");
        require(currentEpochNumber >= user.lastClaimEpoch, "Withdraw: Cannot request before token is active");
        require(block.timestamp >= user.depositDate.add(user.lockPeriod), "Withdraw: Cannot request before the lock period is over");
        
        user.withdrawEpoch = currentEpochNumber + 1;
        epoch.totalNextBoostedShare = epoch.totalNextBoostedShare.sub(user.amount);
        epoch.totalAmountStaked = epoch.totalAmountStaked.sub(user.amount);

        epochInfo[currentEpochNumber] = epoch;
        userInfo[_tokenId] = user;

        emit WithdrawalRequested(_tokenId, msg.sender, currentEpochNumber);
    }

    /**
     * @notice Withdraw tokens for a specific token ID.
     * @param _tokenId Token ID to withdraw tokens for.
     */
    function withdraw(uint256 _tokenId) external override onlyDepositOwner(_tokenId) nonReentrant {
        updateEpoch();
        UserInfo storage user = userInfo[_tokenId];

        bool isRequsted = user.withdrawEpoch != 0 && currentEpochNumber >= user.withdrawEpoch;
        require(user.amount > 0, "Withdraw: Nothing to withdraw");
        require(
            isRequsted || user.lastClaimEpoch > currentEpochNumber, 
            "Withdraw: Invalid Epoch"
        );

        if (user.withdrawEpoch > user.lastClaimEpoch) {
            settlePendingUwu(msg.sender, _tokenId);
        }

        UWU.safeTransfer(msg.sender, user.amount);
        delete userInfo[_tokenId];
        uwuStakingNft.burn(_tokenId);

        emit Withdraw(_tokenId, msg.sender, currentEpochNumber);
    }

    /**
     * @notice Compound rewards for a specific token ID.
     * @param _tokenId Token ID to compound rewards for.
     */
    function compound(uint256 _tokenId) external override nonReentrant {
        updateEpoch();
        _compound(_tokenId);
    }

    /**
     * @notice Compound rewards for all provided token IDs.
     * @param _tokenIds Array of token IDs to compound rewards for.
     */
    function compoundAll(uint256[] memory _tokenIds) external override nonReentrant {
        updateEpoch();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _compound(_tokenIds[i]);
        }
    }

    function _compound(uint256 _tokenId) internal onlyDepositOwner(_tokenId) {
        EpochInfo memory epoch = epochInfo[currentEpochNumber];
        UserInfo storage user = userInfo[_tokenId];

        require(user.amount > 0, "Compound: Insufficient balance");
        require(user.withdrawEpoch == 0, "Compound: Withdraw initiated");
        require(currentEpochNumber > user.lastClaimEpoch, "Compound: Invalid epoch");

        uint256 depositAmount = settlePendingUwu(address(this), _tokenId);
        require(depositAmount > 0, "Compound: Reward amount must be greater than 0");

        user.amount = user.amount.add(depositAmount);
        user.compoundEpoch = currentEpochNumber;
        user.lastCompoundDelta = depositAmount;
        user.lastClaimEpoch = currentEpochNumber;

        // Update total boosted share
        bool isActiveMultiplier = user.resetEpoch > currentEpochNumber;
        uint256 userMultiplier = isActiveMultiplier ? user.multiplier : BOOST_PRECISION;
        uint256 userCompBoostedShare = depositAmount.mul(userMultiplier).div(BOOST_PRECISION);
        
        epoch.totalNextBoostedShare = epoch.totalNextBoostedShare.add(userCompBoostedShare);
        epoch.totalAmountStaked = epoch.totalAmountStaked.add(depositAmount);
        epochInfo[currentEpochNumber] = epoch;

        if (isActiveMultiplier) {
            uint256 resetDelta = userCompBoostedShare.sub(depositAmount);
            epochInfo[user.resetEpoch - 1].totalNextResetBoostedShare = epochInfo[user.resetEpoch - 1].totalNextResetBoostedShare.add(resetDelta);
        }

        emit Compounded(_tokenId, depositAmount, currentEpochNumber);
    }

    function setUwuStakingNft(IStakingDepositNFT _uwuStakingNft) external onlyRole(UPGRADER_ROLE) {
        uwuStakingNft = _uwuStakingNft;
    }

    function setStaticRewardWallet(IRewardWallet _staticRewardWallet) external onlyRole(UPGRADER_ROLE) {
        uwuStaticRewardWallet = _staticRewardWallet;
    }

    function setDynamicRewardWallet(IRewardWallet _dynamicRewardWallet) external onlyRole(UPGRADER_ROLE) {
        uwuDynamicRewardWallet = _dynamicRewardWallet;
    }

    /// @notice Settles, distribute the pending UWU rewards for given user.
    /// @param _user The user address for settling rewards.
    /// @param _tokenId The token id.
    function settlePendingUwu(
        address _user,
        uint256 _tokenId
    ) internal returns (uint256) {
        UserInfo memory user = userInfo[_tokenId];

        (uint256 earliestUnclaimedEpoch, uint256 intervalMultiplier, uint256 latestUnclaimedEpoch) =
            calculateUnclaimedEpochIntervals(user.withdrawEpoch, user.resetEpoch, user.lastClaimEpoch, user.multiplier);
        
        (uint256 totalStaticUnclaimed, uint256 totalDynamicUnclaimed) =
            _calculateRewards(
                user.lastClaimEpoch,
                earliestUnclaimedEpoch,
                latestUnclaimedEpoch,
                user.compoundEpoch,
                user.lastCompoundDelta,
                user.amount,
                intervalMultiplier
            );

        if (totalStaticUnclaimed > 0) {
            uwuStaticRewardWallet.safeTransfer(_user, totalStaticUnclaimed);
        }

        if (totalDynamicUnclaimed > 0) {
            dynamicRewardInfo.totalRewardDept = dynamicRewardInfo.totalRewardDept.add(totalDynamicUnclaimed);
            uwuStaticRewardWallet.safeTransfer(_user, totalDynamicUnclaimed);
        }

        return totalStaticUnclaimed.add(totalDynamicUnclaimed);
    }

    function _calculateRewards(
        uint256 fromEpoch,
        uint256 earliestUnclaimedEpoch,
        uint256 latestUnclaimedEpoch,
        uint256 compoundEpoch,
        uint256 lastCompoundDelta,
        uint256 amount,
        uint256 intervalMultiplier
    ) internal view returns (
        uint256 totalStaticUnclaimed,
        uint256 totalDynamicUnclaimed
    ) {
        bool isLastEpochCompound = compoundEpoch == fromEpoch;
        if (isLastEpochCompound && earliestUnclaimedEpoch > compoundEpoch) {
            (uint256 totalCompStaticUnclaimed, uint256 totalCompDynamicUnclaimed) = _calculateCompoundEpochRewards(
                amount, 
                intervalMultiplier, 
                fromEpoch, 
                fromEpoch + 1, 
                lastCompoundDelta
            );

            totalStaticUnclaimed = totalStaticUnclaimed.add(totalCompStaticUnclaimed);
            totalDynamicUnclaimed = totalDynamicUnclaimed.add(totalCompDynamicUnclaimed);
            fromEpoch++;
        }

        uint256 boostedAmount = amount.mul(intervalMultiplier).div(BOOST_PRECISION);
        (uint256 totalIntervalStaticUnclaimed, uint256 totalIntervalDynamicUnclaimed) = getAccumulatedRewards(fromEpoch, earliestUnclaimedEpoch, boostedAmount);
        totalStaticUnclaimed = totalStaticUnclaimed.add(totalIntervalStaticUnclaimed);
        totalDynamicUnclaimed = totalDynamicUnclaimed.add(totalIntervalDynamicUnclaimed);

        if (latestUnclaimedEpoch > 0) {

            // -----resetEpoch, compounEpoch, lastClaimEpoch------currentEpoch
            (uint256 totalStaticUnclaimedReseted, uint256 totalDynamicUnclaimedReseted) = _calculateResetEpochRewards(
                amount,
                earliestUnclaimedEpoch, 
                latestUnclaimedEpoch,
                compoundEpoch,
                lastCompoundDelta,
                isLastEpochCompound
            );

            totalStaticUnclaimed = totalStaticUnclaimed.add(totalStaticUnclaimedReseted);
            totalDynamicUnclaimed = totalDynamicUnclaimed.add(totalDynamicUnclaimedReseted);
        }

        return (totalStaticUnclaimed, totalDynamicUnclaimed);
    }

    function _calculateCompoundEpochRewards(
        uint256 amount,
        uint256 intervalMultiplier,
        uint256 fromEpoch,
        uint256 toEpoch,
        uint256 compoundDelta
    ) internal view returns (uint256, uint256) {
        uint256 boostedAmountSubDelta = amount.sub(compoundDelta).mul(intervalMultiplier).div(BOOST_PRECISION);
        return getAccumulatedRewards(fromEpoch, toEpoch, boostedAmountSubDelta);
    }

    function _calculateResetEpochRewards(
        uint256 amount,
        uint256 earliestUnclaimedEpoch,
        uint256 latestUnclaimedEpoch,
        uint256 compoundEpoch,
        uint256 compoundDelta,
        bool isLastEpochCompound
    ) internal view returns (uint256, uint256) {
        uint256 totalStaticUnclaimed;
        uint256 totalDynamicUnclaimed;
        if (isLastEpochCompound  && earliestUnclaimedEpoch == compoundEpoch && latestUnclaimedEpoch > earliestUnclaimedEpoch) {
            (uint256 totalCompStaticUnclaimed, uint256 totalCompDynamicUnclaimed) = _calculateCompoundEpochRewards(
                amount, 
                BOOST_PRECISION, 
                earliestUnclaimedEpoch, 
                earliestUnclaimedEpoch + 1, 
                compoundDelta
            );

            totalStaticUnclaimed = totalStaticUnclaimed.add(totalCompStaticUnclaimed);
            totalDynamicUnclaimed = totalDynamicUnclaimed.add(totalCompDynamicUnclaimed);
            earliestUnclaimedEpoch++;
        }

        (uint256 totalStaticUnclaimedReseted, uint256 totalDynamicUnclaimedReseted) = getAccumulatedRewards(
            earliestUnclaimedEpoch, 
            latestUnclaimedEpoch, 
            amount
        );

        return (totalStaticUnclaimed.add(totalStaticUnclaimedReseted), totalDynamicUnclaimed.add(totalDynamicUnclaimedReseted));
    }

    function getAccumulatedRewards(
        uint256 start, 
        uint256 end, 
        uint256 _boostedAmount
    ) internal view returns (
        uint256 totalStaticUnclaimed, 
        uint256 totalDynamicUnclaimed
    ) {
        for (uint256 i = start; i < end; i++) {
            EpochInfo memory epoch = epochInfo[i];
            totalStaticUnclaimed = totalStaticUnclaimed.add(_boostedAmount.mul(epoch.accRewardPerShare).div(ACC_UWU_PRECISION));
            totalDynamicUnclaimed = totalDynamicUnclaimed.add(_boostedAmount.mul(epoch.accDynamicRewardPerShare).div(ACC_UWU_PRECISION));
        }
        return (totalStaticUnclaimed, totalDynamicUnclaimed);
    }

    function calculateUnclaimedEpochIntervals(
        uint256 withdrawEpoch,
        uint256 resetEpoch,
        uint256 lastClaimEpoch,
        uint256 userMultiplier
    ) internal view returns (
        uint256 earliestUnclaimedEpoch,
        uint256 intervalMultiplier,
        uint256 latestUnclaimedEpoch
    ) {
        uint256 defaultEpoch = withdrawEpoch != 0 && withdrawEpoch <= currentEpochNumber ? withdrawEpoch : currentEpochNumber;

        if (lastClaimEpoch > resetEpoch) {
            earliestUnclaimedEpoch = defaultEpoch;
            intervalMultiplier = BOOST_PRECISION;
        } else if (currentEpochNumber > resetEpoch) {
            earliestUnclaimedEpoch = resetEpoch;
            intervalMultiplier = userMultiplier;
            latestUnclaimedEpoch = defaultEpoch;
        } else {
            earliestUnclaimedEpoch = currentEpochNumber;
            intervalMultiplier = userMultiplier;
        }
    }

    /**
     * @notice Get the information of the current epoch.
     * @return epochInfo Struct containing the current epoch's information.
     */
    function getCurrentEpochInfo() public view override returns (EpochInfo memory) {
        return epochInfo[currentEpochNumber];
    }

    /**
     * @notice Get current epoch number.
     * @return currentEpochNumber Number of the current epoch.
     */
    function getCurrentEpochNumber() public view override returns (uint256) {
        return currentEpochNumber;
    }

    /**
     * @notice Get the user's staking information for a specific token ID.
     * @param _tokenId Token ID to get the user's staking information for.
     * @return userInfo Struct containing the user's staking information.
     */
    function getUserInfo(uint256 _tokenId) public view override returns (UserInfo memory) {
        return userInfo[_tokenId];
    }

    /**
     * @notice Get the user's multiplier for a specific token ID.
     * @param _tokenId Token ID to get the user's multiplier for.
     * @return multiplier The multiplier for the specified token ID.
     */
    function getUserMultiplier(uint256 _tokenId) public view override returns (uint256 multiplier) {
        UserInfo memory user = userInfo[_tokenId];
        if (user.amount == 0) return 0;
        return user.resetEpoch > currentEpochNumber ? user.multiplier : BOOST_PRECISION;
    }

    /**
     * @notice Get the reward information for a specific reward ID.
     * @param _rewardId Reward ID to get the reward information for.
     * @return rewardInfo Struct containing the reward information for the specified reward ID.
     */
    function getRewardInfo(uint256 _rewardId) public view override returns (RewardInfo memory) {
        return rewardInfo[_rewardId];
    }
}

