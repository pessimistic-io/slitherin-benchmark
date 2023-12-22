//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Libs
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {FixedPointMath} from "./FixedPointMath.sol";
import {AccessControl} from "./AccessControl.sol";
import {OneInchZapLib} from "./OneInchZapLib.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {UserLPStorage} from "./UserLPStorage.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IFeeReceiver} from "./IFeeReceiver.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {IStakingRewardsV3} from "./IStakingRewardsV3.sol";
import {ILPVault} from "./ILPVault.sol";

abstract contract LPVault is ILPVault, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;
    using FixedPointMath for uint256;
    using OneInchZapLib for I1inchAggregationRouterV4;

    enum VaultType {
        BULL,
        BEAR
    }

    uint256 public constant ACCURACY = 1e12;

    // Role for the keeper used to call the vault methods
    bytes32 public constant KEEPER = keccak256("KEEPER_ROLE");

    // Role for the governor to enact emergency and management methods
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR_ROLE");

    // Role for the strategy contract to pull funds from the vault
    bytes32 public constant STRATEGY = keccak256("STRATEGY_ROLE");

    // Token being deposited
    IERC20 public depositToken;

    // Token Storage contract for unusable tokens
    UserLPStorage public lpStorage;

    // Vault name because all contracts deserve names
    string public name;

    VaultType public vaultType;

    // Epoch data
    Epoch[] public epochs;

    // Current epoch number
    uint256 public epoch;

    // Max cap for the current epoch
    uint256 public cap;

    // Current cap
    uint256 public totalDeposited;

    // Mapping user => user data
    mapping(address => UserEpochs) public userEpochs;

    // Mapping user => (epoch => amount)
    mapping(address => mapping(uint256 => uint256)) public userDepositPerEpoch;

    // Risk % (12 decimals) used to the define the percentage vaults can borrow each epoch
    uint256 public riskPercentage;

    // Flag to see if any funds have been borrowed this epoch
    bool public borrowed;

    // Percentage of vault ownership leaving in the next epoch
    uint256 private exitingPercentage;

    // Percentage of vault ownership fliping to another vault
    uint256 private flipingPercentage;

    // Percentage of each user fliping to another vault next epoch
    mapping(address => Flip) public flipUserInfo;

    // Users fliping next epoch
    address[] private usersFliping;

    // Paused for security reasons
    bool public paused;

    // Vault end epoch (only present if paused)
    uint256 public finalEpoch;

    // Epoch ended
    bool public epochEnded;

    // Whitelisted vaults to flip to
    mapping(address => bool) public whitelistedFlipVaults;

    // Fee (12 decimals)
    uint256 public feePercentage;

    // Fee recever contract
    IFeeReceiver public feeReceiver;

    // 1Inch router for auto compounding
    I1inchAggregationRouterV4 internal router;

    // Staking rewards
    IStakingRewardsV3 public farm;

    constructor(
        address _depositToken,
        address _storage,
        string memory _name,
        uint256 _riskPercentage,
        uint256 _feePercentage,
        address _feeReceiver,
        address payable _router,
        uint256 _cap,
        address _farm
    ) {
        if (
            _depositToken == address(0) || _storage == address(0) || _feeReceiver == address(0) || _router == address(0)
                || _farm == address(0) || _cap == 0 || _riskPercentage == 0
        ) {
            revert WRONG_VAULT_ARGS();
        }
        epochs.push(Epoch(0, 0));
        depositToken = IERC20(_depositToken);
        lpStorage = UserLPStorage(_storage);
        name = _name;
        borrowed = false;
        paused = false;
        epochEnded = false;
        riskPercentage = _riskPercentage;
        feePercentage = _feePercentage;
        feeReceiver = IFeeReceiver(_feeReceiver);
        router = I1inchAggregationRouterV4(_router);
        cap = _cap;
        farm = IStakingRewardsV3(_farm);
        depositToken.safeApprove(_storage, type(uint256).max);
        depositToken.safeApprove(_farm, type(uint256).max);
        _grantRole(KEEPER, msg.sender);
        _grantRole(GOVERNOR, msg.sender);
    }

    // ============================= View Functions =====================

    /**
     * Returns the working balance in this vault ( unused + staked)
     */
    function workingBalance() external view returns (uint256) {
        return depositToken.balanceOf(address(this)) + _getStakedAmount();
    }

    /**
     * Represents the amount the user earned so far + the deposits this epoch.
     * @param _user user to see the balanceOf.
     */
    function balanceOf(address _user) public view returns (uint256) {
        uint256 rewardsSoFar = 0;
        uint256 currentEpoch = epoch;
        uint256 depositsThisEpoch = userDepositPerEpoch[_user][currentEpoch + 1]; // Deposits are stored in next epoch
        Flip memory userFlip = flipUserInfo[_user];

        // If the user triggered the flip this is the only way to calculate his balance
        if (userFlip.userPercentage != 0) {
            Epoch memory currentEpochData = epochs[currentEpoch];
            uint256 totalAmount = epochEnded ? currentEpochData.endAmount : currentEpochData.startAmount;
            rewardsSoFar = totalAmount.mulDivDown(userFlip.userPercentage, ACCURACY);
        }
        // If the user has not signaled flip we must do different calculations
        else {
            // If epoch == 0 then there are no profits to be calculated only deposits
            if (currentEpoch != 0) {
                // If we are in a closed epoch we already have the final data for this epoch
                // But If we are in an open epoch we give the scenario where PnL for this epoch is 0 (because we still dont know if we are going to have profits)
                uint256 targetEpoch = epochEnded || currentEpoch == 0 ? currentEpoch : (currentEpoch - 1);
                rewardsSoFar = calculateRewardsAtEndOfEpoch(_user, targetEpoch);
            }
            if (!epochEnded) {
                depositsThisEpoch += userDepositPerEpoch[_user][currentEpoch]; // We have to account for the deposits the user made last epoch that are now being used
            }
        }
        return rewardsSoFar + depositsThisEpoch;
    }

    /**
     * @notice Calculates the amount deposited by the user so far (ignores rewards or losses)
     * @param _user user address
     */
    function deposited(address _user) public view returns (uint256) {
        return userEpochs[_user].deposited;
    }

    /**
     * @notice Calculates the amount of tokens the user owns at the start of the epoch
     * @param _user the user address
     * @param _epoch the epoch we want to calculate the rewards to
     */
    function calculateRewardsAtStartOfEpoch(address _user, uint256 _epoch) public view returns (uint256) {
        if (_epoch > epoch) {
            revert OPERATION_IN_FUTURE();
        }

        uint256 rewards = 0;
        UserEpochs memory userEpochData = userEpochs[_user];

        // We must only calculate the rewards until the signal exit
        uint256 lastEpoch = userEpochData.end != 0 ? userEpochData.end : _epoch;
        lastEpoch = lastEpoch < _epoch ? lastEpoch : _epoch;
        // No rewards for the future

        // Only if user actually deposited something
        if (userEpochData.epochs.length != 0) {
            for (uint256 currEpoch = userEpochData.epochs[0]; currEpoch <= lastEpoch; currEpoch++) {
                // If the user deposited to this epoch we must accomulate the deposits with the rewards already received
                uint256 userDepositsOnEpoch = userDepositPerEpoch[_user][currEpoch];
                rewards += userDepositsOnEpoch;

                // Only acommulate for other epochs
                if (currEpoch < lastEpoch) {
                    // The rewards are now based on the ratio of this epoch
                    Epoch memory epochData = epochs[currEpoch];
                    rewards = rewards.mulDivDown(epochData.endAmount, epochData.startAmount);
                }
            }
        }

        return rewards;
    }

    /**
     * @notice Calculates the amount of tokens the user owns at the end of the epoch
     * @param _user the user address
     * @param _epoch the epoch we want to calculate the rewards to
     */
    function calculateRewardsAtEndOfEpoch(address _user, uint256 _epoch) public view returns (uint256) {
        uint256 currentEpoch = epoch;

        if (_epoch > currentEpoch) {
            revert OPERATION_IN_FUTURE();
        }

        uint256 rewards = 0;
        UserEpochs memory userEpochData = userEpochs[_user];

        // We must only calculate the rewards until the signal exit
        uint256 lastEpoch = userEpochData.end != 0 ? userEpochData.end : _epoch;
        lastEpoch = lastEpoch < _epoch ? lastEpoch : _epoch;
        // No rewards for the future
        if (_epoch < currentEpoch || (_epoch == currentEpoch && epochEnded)) {
            // Only if user actually deposited something
            if (userEpochData.epochs.length != 0) {
                for (uint256 currEpoch = userEpochData.epochs[0]; currEpoch <= lastEpoch; currEpoch++) {
                    // If the user deposited to this epoch we must accomulate the deposits with the rewards already received
                    uint256 userDepositedThisEpoch = userDepositPerEpoch[_user][currEpoch];
                    rewards += userDepositedThisEpoch;

                    // The rewards are now based on the ratio of this epoch
                    Epoch memory epochData = epochs[currEpoch];
                    rewards = rewards.mulDivDown(epochData.endAmount, epochData.startAmount);
                }
            }
        }

        return rewards;
    }

    // ============================= User Functions =====================

    /**
     * @notice Deposits the given value to the users balance
     * @param _user the user to deposits funds to (can be != msg.sender)
     * @param _value the value being deposited
     */
    function deposit(address _user, uint256 _value) external nonReentrant {
        UserEpochs memory userEpochData = userEpochs[_user];
        uint256 currentEpoch = epoch;
        if (paused) {
            revert VAULT_PAUSED();
        }
        if (userEpochData.end != 0) {
            revert ALREADY_EXITED();
        }
        if (_value == 0 || _user == address(0)) {
            revert ZERO_VALUE();
        }
        if (totalDeposited + _value > cap && !whitelistedFlipVaults[msg.sender]) {
            revert VAULT_FULL();
        }

        depositToken.safeTransferFrom(msg.sender, address(this), _value);
        lpStorage.storeDeposit(_value);

        // If this is the first deposit this epoch
        uint256 userEpochDeposit = userDepositPerEpoch[_user][currentEpoch + 1];
        if (userEpochDeposit == 0) {
            userEpochs[_user].epochs.push(currentEpoch + 1);
        }
        // Update the deposited amount for the given epoch
        userDepositPerEpoch[_user][currentEpoch + 1] = userEpochDeposit + _value;
        userEpochs[_user].deposited += _value;
        totalDeposited += _value;

        emit Deposited(msg.sender, _user, _value);
    }

    function cancelDeposit() external nonReentrant {
        uint256 currentEpoch = epoch;
        uint256 amountDeposited = userDepositPerEpoch[msg.sender][currentEpoch + 1];
        if (paused) {
            revert VAULT_PAUSED();
        }
        if (epochEnded) {
            revert EPOCH_ENDED();
        }
        if (amountDeposited == 0) {
            revert ACTION_FORBIDEN_IN_USER_STATE();
        }

        userDepositPerEpoch[msg.sender][currentEpoch + 1] = 0;
        totalDeposited -= amountDeposited;
        userEpochs[msg.sender].deposited -= amountDeposited;

        lpStorage.refundDeposit(msg.sender, amountDeposited);
        emit CanceledDeposit(msg.sender, amountDeposited);
    }

    /**
     * @notice Signal flip to another vault for msg.sender (flip auto done at start of next epoch)
     * @param _destination destination vault
     * @dev _destination should be whitelisted and should hold the same tokens as this vault
     */
    function signalFlip(address _destination) external nonReentrant {
        UserEpochs memory userEpochData = userEpochs[msg.sender];
        Flip memory userFlip = flipUserInfo[msg.sender];
        uint256 currentEpoch = epoch;

        if (!whitelistedFlipVaults[_destination]) {
            revert NON_WHITELISTED_FLIP();
        }

        if (paused) {
            revert VAULT_PAUSED();
        }

        if (userEpochData.epochs.length == 0) {
            revert NO_DEPOSITS_FOR_USER();
        }

        if (userEpochData.end != 0 || userFlip.userPercentage != 0) {
            revert USER_ALREADY_EXITING();
        }

        // Estimate just to check if it will overflow the destination vault
        uint256 userAmountEstimate = calculateRewardsAtStartOfEpoch(msg.sender, currentEpoch);
        LPVault destVault = LPVault(_destination);
        uint256 currentDestDeposits = destVault.totalDeposited();
        if (currentDestDeposits != 0 && currentDestDeposits + userAmountEstimate > destVault.cap()) {
            revert TARGET_VAULT_FULL();
        }

        uint256 userFlipingPercentage = _calculateUserPercentage(msg.sender);

        // Increment fliping percentage
        flipingPercentage += userFlipingPercentage;

        // Add users fliping data
        usersFliping.push(msg.sender);
        flipUserInfo[msg.sender] = Flip(userFlipingPercentage, _destination);

        uint256 currentEpochDeposit = userDepositPerEpoch[msg.sender][currentEpoch + 1];

        // Send user deposits this epoch to the fliping vault now
        if (currentEpochDeposit != 0) {
            lpStorage.depositToVault(currentEpochDeposit);
            LPVault(_destination).deposit(msg.sender, currentEpochDeposit);
        }

        // Update leaving deposits
        totalDeposited -= userEpochs[msg.sender].deposited;

        // Deletes the user data to avoid double withdraws
        _deleteUserData(msg.sender);

        emit Flipped(msg.sender, _destination);
    }

    /**
     * @notice Signal exit for the msg.sender, user will be able to withdraw next epoch.
     */
    function signalExit() external nonReentrant {
        UserEpochs memory userEpochData = userEpochs[msg.sender];
        Flip memory userFlip = flipUserInfo[msg.sender];
        if (paused) {
            revert VAULT_PAUSED();
        }

        // User will have to wait to exit, cant leave now, wait for next epoch (can cancel and then signal exit)
        if (userDepositPerEpoch[msg.sender][epoch + 1] != 0) {
            revert DEPOSITED_THIS_EPOCH();
        }

        // User already exiting the vault
        if (userEpochData.epochs.length == 0 || userEpochData.end != 0 || userFlip.userPercentage != 0) {
            revert USER_ALREADY_EXITING();
        }

        uint256 userExitPercentage = _calculateUserPercentage(msg.sender);
        exitingPercentage += userExitPercentage;

        userEpochs[msg.sender].end = epoch;
        totalDeposited -= userEpochs[msg.sender].deposited;

        emit UserSignalExit(msg.sender);
    }

    /**
     * @notice Allows user to cancel a signal exit done this epoch
     */
    function cancelSignalExit() external nonReentrant {
        UserEpochs memory userEpochData = userEpochs[msg.sender];
        if (paused) {
            revert VAULT_PAUSED();
        }
        if (epochEnded) {
            revert EPOCH_ENDED();
        }
        if (userEpochData.end != 0 && userEpochData.end != epoch) {
            revert ACTION_FORBIDEN_IN_USER_STATE();
        }
        uint256 userExitPercentage = _calculateUserPercentage(msg.sender);
        exitingPercentage -= userExitPercentage;

        userEpochs[msg.sender].end = 0;
        totalDeposited += userEpochs[msg.sender].deposited;

        emit UserCancelSignalExit(msg.sender);
    }

    /**
     * @notice withdraw's user's tokens fom the vault and sends it to the user.
     */
    function withdraw() external nonReentrant {
        UserEpochs memory userEpochData = userEpochs[msg.sender];
        if (userEpochData.epochs.length == 0 || userEpochData.end >= epoch) {
            revert CANNOT_WITHDRAW();
        }
        // Calculate total rewards for every lock
        uint256 rewards = calculateRewardsAtEndOfEpoch(msg.sender, userEpochData.end);

        // Deletes the user data to avoid double withdraws
        _deleteUserData(msg.sender);

        // Transfer tokens out to the user
        lpStorage.refundCustomer(msg.sender, rewards);

        emit Withdrew(msg.sender, rewards);
    }

    // ============================= KEEPER Functions =====================

    /**
     * @notice closes the current epoch.
     * Before closing the profits for the epoch, it harvests and Zaps farming rewards
     * And after those calculations are done it deposits in behalf of the users to their respective flip vaults
     * @param _intermediateZapSwaps zaping arguments for tokens that are NOT part of the base pair
     * @param _directZapSwaps zaping arguments for tokens that are part of the base pair
     */
    function endEpoch(
        OneInchZapLib.ZapInIntermediateParams[] calldata _intermediateZapSwaps,
        OneInchZapLib.ZapInParams[] calldata _directZapSwaps
    )
        external
        onlyRole(KEEPER)
        nonReentrant
    {
        uint256 currentEpoch = epoch;
        uint256 endingEpoch = finalEpoch;
        if (epochEnded) {
            revert EPOCH_ENDED();
        }
        if (endingEpoch != 0 && currentEpoch == endingEpoch) {
            revert VAULT_PAUSED();
        }

        // Harvests from farm before doing any maths
        _harvestAndZap(_intermediateZapSwaps, _directZapSwaps);

        // Get balance of unused LP
        uint256 unused = depositToken.balanceOf(address(this));

        // Get the amount at the end of the epoch
        uint256 endBalance = unused + _getStakedAmount();

        // Calculate profit for fees (only charge fee on profit)
        Epoch memory currentEpochData = epochs[currentEpoch];
        uint256 profit = currentEpochData.startAmount > endBalance ? 0 : endBalance - currentEpochData.startAmount;

        // Div down because we are nice
        uint256 fees = feePercentage > 0 || profit > 0 ? profit.mulDivDown(feePercentage, ACCURACY) : 0;

        // Handle fees
        if (fees > 0) {
            if (fees > unused) {
                _unstake(fees - unused);
            }
            depositToken.safeApprove(address(feeReceiver), fees);
            feeReceiver.deposit(address(depositToken), fees);
            depositToken.safeApprove(address(feeReceiver), 0);
            endBalance -= fees;
        }

        // Update storage
        currentEpochData.endAmount = endBalance;
        epochs[currentEpoch] = currentEpochData;

        if (flipingPercentage != 0) {
            // Diving up to avoid not having enough funds, whatever is left unused is later staked
            uint256 flipingAmount = flipingPercentage.mulDivUp(endBalance, ACCURACY);

            if (flipingAmount != 0) {
                unused = depositToken.balanceOf(address(this));
                // If we dont have enough balance we will need to unstake what we need to refund
                if (flipingAmount > unused) {
                    _unstake(flipingAmount - unused);
                }
            }

            // Flip all users to their respective vaults
            address[] memory usersFlipingList = usersFliping;
            for (uint256 i = 0; i < usersFlipingList.length; i++) {
                _flipUser(usersFlipingList[i]);
            }
            delete usersFliping;
            flipingPercentage = 0;
        }

        epochEnded = true;

        emit EpochEnded(currentEpoch, currentEpochData.endAmount, currentEpochData.startAmount);
    }

    /**
     * @notice Starts a new epoch.
     * Before starting a new epoch it calculates the amount of users wanting to exit and sends their balance to the storage contract
     * After increasing the epoch number it pulls in the balance from the storage contract and calculates the next epoch start amount.
     * @param _intermediateZapSwaps zaping arguments for tokens that are NOT part of the base pair (only required to be non empty when its paused)
     * @param _directZapSwaps zaping arguments for tokens that are part of the base pair (onlu required to be non empty when its paused)
     */
    function startEpoch(
        OneInchZapLib.ZapInIntermediateParams[] calldata _intermediateZapSwaps,
        OneInchZapLib.ZapInParams[] calldata _directZapSwaps
    )
        external
        onlyRole(KEEPER)
        nonReentrant
    {
        uint256 currentEpoch = epoch;
        uint256 endingEpoch = finalEpoch;
        if (!epochEnded) {
            revert STARTING_EPOCH_BEFORE_ENDING_LAST();
        }
        if (endingEpoch != 0 && currentEpoch == endingEpoch) {
            revert VAULT_PAUSED();
        }

        // Get the amount at the end of the epoch
        uint256 endBalance = epochs[currentEpoch].endAmount;

        // Add the exited funds to the unusable balance (dividing up to avoid any issues)
        uint256 unusableExited = exitingPercentage.mulDivUp(endBalance, ACCURACY);

        // Get balance of unused LP
        uint256 unused = depositToken.balanceOf(address(this));

        // Send unusable to lpStorage
        if (unusableExited != 0) {
            // If we dont have enough balance we will need to unstake what we need to refund
            if (unusableExited > unused) {
                _unstake(unusableExited - unused);
            }

            lpStorage.storeRefund(unusableExited);
        }

        // Start new Epoch
        epoch = currentEpoch + 1;

        // Get the deposited last epoch
        lpStorage.depositToVault();

        // Calculate starting balance for this epoch
        uint256 starting = depositToken.balanceOf(address(this)) + _getStakedAmount();

        // Everyone already exited to storage
        exitingPercentage = 0;

        // Update new epoch data
        epochs.push(Epoch(starting, 0));

        // If it is paused we dont want to stake, we want to unstake everything
        if (paused) {
            _exitFarm(_intermediateZapSwaps, _directZapSwaps);
        }
        // If its not paused resume normal course
        else {
            // Funds never stop
            _stakeUnused();
        }

        borrowed = false;
        epochEnded = false;

        emit EpochStart(currentEpoch, starting);
    }

    /**
     * @notice Auto compounds all the farming rewards.
     * @param _intermediateZapSwaps zaping arguments for tokens that are NOT part of the base pair
     * @param _directZapSwaps zaping arguments for tokens that are part of the base pair
     * @dev only KEEPER
     */
    function autoCompound(
        OneInchZapLib.ZapInIntermediateParams[] calldata _intermediateZapSwaps,
        OneInchZapLib.ZapInParams[] calldata _directZapSwaps
    )
        external
        onlyRole(KEEPER)
        returns (uint256)
    {
        uint256 earned = _harvestAndZap(_intermediateZapSwaps, _directZapSwaps);
        _stakeUnused();
        return earned;
    }

    // ============================= Strategy Functions =====================

    /**
     * @notice this function can be called by a strategy to request the funds to apply.
     * It only sends the risk percentage to the strategy, never more, nor less.
     * @dev This function can only be called once every epoch
     * @dev This is the default borrow function that sends in LP tokens, some vaults might have specific implementations
     */
    function borrowLP() external onlyRole(STRATEGY) {
        if (paused) {
            revert VAULT_PAUSED();
        }
        // Can only borrow once per epoch
        if (borrowed) {
            revert ALREADY_BORROWED();
        }
        uint256 tokenBalance = depositToken.balanceOf(address(this));
        uint256 amount = (tokenBalance + _getStakedAmount()).mulDivDown(riskPercentage, ACCURACY);
        if (tokenBalance < amount) {
            _unstake(amount - tokenBalance);
        }
        borrowed = true;
        depositToken.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    // ============================= Management =============================

    /**
     * @notice Updates the Farm address and stakes all the balance in there
     * @param _farm new farm to deposit to
     * @dev only GOVERNOR
     */
    function updateFarm(address _farm) external onlyRole(GOVERNOR) {
        IStakingRewardsV3 currentFarm = farm;
        currentFarm.exit();
        depositToken.safeApprove(address(currentFarm), 0);
        farm = IStakingRewardsV3(_farm);
        depositToken.safeApprove(_farm, type(uint256).max);
        _stakeUnused();
    }

    /**
     * @notice Allows governor to set the fee percentage (0 means no fees).
     * @param _feePercentage the fee percentage with 12 decimals
     * @dev only GOVERNOR
     */
    function setFeePercentage(uint256 _feePercentage) external onlyRole(GOVERNOR) {
        feePercentage = _feePercentage;
    }

    /**
     * @notice Allows governor to set the fee receiver contract.
     * @param _feeReceiver the fee receiver address
     * @dev only GOVERNOR
     */
    function setFeeReceiver(address _feeReceiver) external onlyRole(GOVERNOR) {
        depositToken.safeApprove(address(feeReceiver), 0);
        feeReceiver = IFeeReceiver(_feeReceiver);
    }

    /**
     * @notice Allows governor to set the risk percentage
     * @param _riskPercentage risk percentage with 12 decimals
     * @dev only GOVERNOR
     */
    function setRiskPercentage(uint256 _riskPercentage) external onlyRole(GOVERNOR) {
        if (riskPercentage == 0) {
            revert ZERO_VALUE();
        }
        uint256 oldRisk = riskPercentage;
        riskPercentage = _riskPercentage;
        emit RiskPercentageUpdated(msg.sender, oldRisk, _riskPercentage);
    }

    /**
     * @notice Updates the current vault cap
     * @param _newCap the new vault cap
     * @dev only GOVERNOR
     */
    function setVaultCap(uint256 _newCap) external onlyRole(GOVERNOR) {
        cap = _newCap;
    }

    /**
     * @notice Allows governor to add a vault to the whitelist for flips
     * @param _vault vault address
     * @dev only GOVERNOR
     */
    function addWhitelistedVault(address _vault) external onlyRole(GOVERNOR) {
        if (whitelistedFlipVaults[_vault]) {
            revert ALREADY_WHITELISTED();
        }
        whitelistedFlipVaults[_vault] = true;
        depositToken.safeApprove(_vault, type(uint256).max);
    }

    /**
     * @notice Allows governor to remove a vault from the whitelist for flips
     * @param _vault vault address
     * @dev only GOVERNOR
     */
    function removeWhitelistedVault(address _vault) external onlyRole(GOVERNOR) {
        if (!whitelistedFlipVaults[_vault]) {
            revert NOT_WHITELISTED();
        }
        whitelistedFlipVaults[_vault] = false;
        depositToken.safeApprove(_vault, 0);
    }

    /**
     * @notice Allows governor to provide the STRATEGY role to a strategy contract
     * @param _strat strategy address
     * @dev only GOVERNOR
     */
    function addStrategy(address _strat) external onlyRole(GOVERNOR) {
        _grantRole(STRATEGY, _strat);
    }

    /**
     * @notice Allows governor to remove the strategy STRATEGY role from a strategy contract
     * @param _strat strategy address
     * @dev only GOVERNOR
     */
    function removeStrategy(address _strat) external onlyRole(GOVERNOR) {
        _revokeRole(STRATEGY, _strat);
    }

    /**
     * @notice Allows governor to provide the KEEPER role to any address (usually a BOT)
     * @param _keeper keeper address
     * @dev only GOVERNOR
     */
    function addKeeper(address _keeper) external onlyRole(GOVERNOR) {
        _grantRole(KEEPER, _keeper);
    }

    /**
     * @notice Allows governor to remove the KEEPER from any address
     * @param _keeper keeper address
     * @dev only GOVERNOR
     */
    function removeKeeper(address _keeper) external onlyRole(GOVERNOR) {
        _revokeRole(KEEPER, _keeper);
    }

    /**
     * @notice Transfer the governor role to another address
     * @param _newGovernor The new governor address
     * @dev Will revoke the governor role from `msg.sender`. `_newGovernor` cannot be the zero
     * address
     */
    function transferGovernor(address _newGovernor)
        external
        onlyRole(GOVERNOR)
    {
        if (_newGovernor == address(0)) {
            revert ZERO_VALUE();
        }

        _revokeRole(GOVERNOR, msg.sender);
        _grantRole(GOVERNOR, _newGovernor);
    }

    // ============================= Migration/Emergency Functions =====================

    /**
     * @notice Allows governor to stop the vault
     * Stoping means the vault will no longer accept deposits and will allow all users to exit on the next epoch
     * @dev only GOVERNOR and only for emergencies
     */
    function stopVault() external onlyRole(GOVERNOR) {
        if (paused) {
            revert VAULT_PAUSED();
        }
        paused = true;
        finalEpoch = epoch + 1;
        emit VaultPaused(msg.sender, finalEpoch);
    }

    /**
     * Allows users to withdraw when an emergency is in place.
     * Only for the ones that did not signal before
     */
    function emergencyWithdraw() external nonReentrant {
        UserEpochs memory userEpochData = userEpochs[msg.sender];
        if (!paused) {
            revert EMERGENCY_OFF_NOT_PAUSED();
        }
        if (userEpochData.epochs.length == 0) {
            revert NO_DEPOSITS_FOR_USER();
        }
        if (epoch < finalEpoch) {
            revert TERMINAL_EPOCH_NOT_REACHED();
        }
        if (userEpochData.end != 0) {
            revert EMERGENCY_AFTER_SIGNAL();
        }

        // Calculate total rewards at the start of this epoch
        uint256 rewards = calculateRewardsAtStartOfEpoch(msg.sender, finalEpoch);

        totalDeposited -= userEpochData.deposited;

        // Deletes the user data to avoid double withdraws
        _deleteUserData(msg.sender);

        // Transfer tokens out to the user
        depositToken.safeTransfer(msg.sender, rewards);
        emit Withdrew(msg.sender, rewards);
    }

    /**
     * @notice Zaps the rewards to LP tokens just in case there is some emergency.
     * @param _intermediateZapSwaps zaping arguments for tokens that are NOT part of the base pair
     * @param _directZapSwaps zaping arguments for tokens that are part of the base pair
     * @dev only KEEPER
     */
    function zapToken(
        OneInchZapLib.ZapInIntermediateParams[] calldata _intermediateZapSwaps,
        OneInchZapLib.ZapInParams[] calldata _directZapSwaps
    )
        external
        onlyRole(KEEPER)
        returns (uint256)
    {
        return _zap(_intermediateZapSwaps, _directZapSwaps);
    }

    // ============================= Internal Functions ================================

    function _calculateUserPercentage(address _user) internal view returns (uint256) {
        uint256 userPercentage = 0;
        uint256 currentEpoch = epoch;
        Epoch memory epochData = epochs[currentEpoch];
        // If it ended now we can use the new data
        if (epochEnded) {
            // This calculates the amount the user is owed
            uint256 owedAmount = calculateRewardsAtEndOfEpoch(_user, currentEpoch);
            // Using the owed amount to calculate the percentage the user owns
            userPercentage = epochData.endAmount == 0 ? 0 : owedAmount.mulDivDown(ACCURACY, epochData.endAmount);
        }
        // If epoch not ended yet we must use data from last epoch
        else {
            // This calculates the amount the user owned on the vault at the end of last epoch
            uint256 owedAmount = calculateRewardsAtStartOfEpoch(_user, currentEpoch);
            // Considering the amount the user owned at the end of the last epoch we calculate the % he owns at the start of this epoch
            // So we know what percentage he will own at the end of the epoch (because percentages owned dont change mid epochs)
            userPercentage = epochData.startAmount == 0 ? 0 : owedAmount.mulDivDown(ACCURACY, epochData.startAmount);
        }
        return userPercentage;
    }

    function _deleteUserData(address _user) internal {
        // Deletes the user data to avoid double withdraws
        for (uint256 i = 0; i < userEpochs[_user].epochs.length; i++) {
            delete userDepositPerEpoch[_user][userEpochs[_user].epochs[i]];
        }
        delete userEpochs[_user];
    }

    function _flipUser(address _user) internal {
        Flip memory userFlip = flipUserInfo[_user];
        uint256 userAmount = epochs[epoch].endAmount.mulDivDown(userFlip.userPercentage, ACCURACY);

        if (userAmount != 0) {
            LPVault(userFlip.destinationVault).deposit(_user, userAmount);
        }
        delete flipUserInfo[_user];
    }

    function _stakeUnused() internal {
        uint256 unused = depositToken.balanceOf(address(this));
        if (unused > 0) {
            farm.stake(unused);
        }
    }

    function _unstake(uint256 _value) internal {
        farm.unstake(_value);
    }

    function _exitFarm(
        OneInchZapLib.ZapInIntermediateParams[] calldata _intermediateZapSwaps,
        OneInchZapLib.ZapInParams[] calldata _directZapSwaps
    )
        internal
    {
        farm.exit();
        _harvestAndZap(_intermediateZapSwaps, _directZapSwaps);
    }

    function _harvestAndZap(
        OneInchZapLib.ZapInIntermediateParams[] calldata _intermediateZapSwaps,
        OneInchZapLib.ZapInParams[] calldata _directZapSwaps
    )
        internal
        returns (uint256)
    {
        _harvest();
        uint256 zapped = _zap(_intermediateZapSwaps, _directZapSwaps);
        return zapped;
    }

    function _harvest() internal {
        farm.claim();
    }

    function _getStakedAmount() internal view returns (uint256) {
        return farm.balanceOf(address(this));
    }

    function _zap(
        OneInchZapLib.ZapInIntermediateParams[] calldata _intermediateZapSwaps,
        OneInchZapLib.ZapInParams[] calldata _directZapSwaps
    )
        internal
        returns (uint256)
    {
        uint256 total = 0;
        for (uint256 i = 0; i < _intermediateZapSwaps.length; i++) {
            _validateDesc(_intermediateZapSwaps[i].swapFromIntermediate.desc);
            _validateDesc(_intermediateZapSwaps[i].toPairTokens.desc);
            uint256 rewardBalance =
                IERC20(_intermediateZapSwaps[i].swapFromIntermediate.desc.srcToken).balanceOf(address(this));
            if (rewardBalance > 0) {
                total += router.zapInIntermediate(
                    _intermediateZapSwaps[i].swapFromIntermediate,
                    _intermediateZapSwaps[i].toPairTokens,
                    address(depositToken),
                    _intermediateZapSwaps[i].token0Amount,
                    _intermediateZapSwaps[i].token1Amount,
                    _intermediateZapSwaps[i].minPairTokens
                );
            }
        }
        for (uint256 i = 0; i < _directZapSwaps.length; i++) {
            _validateDesc(_directZapSwaps[i].toPairTokens.desc);
            uint256 rewardBalance = IERC20(_directZapSwaps[i].toPairTokens.desc.srcToken).balanceOf(address(this));
            if (rewardBalance > 0) {
                total += router.zapIn(
                    _directZapSwaps[i].toPairTokens,
                    address(depositToken),
                    _directZapSwaps[i].token0Amount,
                    _directZapSwaps[i].token1Amount,
                    _directZapSwaps[i].minPairTokens
                );
            }
        }
        return total;
    }

    /**
     * Anti-rugginator 3000.
     */
    function _validateDesc(I1inchAggregationRouterV4.SwapDescription memory desc) internal view {
        if (desc.dstReceiver != address(this) || desc.minReturnAmount == 0) {
            revert INVALID_SWAP();
        }
    }

    // ============================= Events ================================

    /**
     * @notice Emitted when a address deposits
     * @param _from The address that makes the deposit
     * @param _to The address that receives a balance
     * @param _amount The amount that was deposited
     */
    event Deposited(address indexed _from, address indexed _to, uint256 _amount);

    /**
     * @notice Emitted when a user cancels a deposit
     * @param _user The address that receives a balance
     * @param _amount The amount that was deposited
     */
    event CanceledDeposit(address indexed _user, uint256 _amount);

    /**
     * @notice Emitted when a user signals a vault flip
     * @param _user The address that requested the flip
     * @param _vault The vault that is fliping to
     */
    event Flipped(address indexed _user, address indexed _vault);

    /**
     * @notice Emitted when a user signals an exit
     * @param _user The address that requested the exit
     */
    event UserSignalExit(address indexed _user);

    /**
     * @notice Emitted when a user cancels a signal exit
     * @param _user The address that requested the exit
     */
    event UserCancelSignalExit(address indexed _user);

    /**
     * @notice Emitted when a user withdraws
     * @param _user The address that withdrew
     * @param _amount the amount sent out
     */
    event Withdrew(address indexed _user, uint256 _amount);

    /**
     * @notice Emitted when epoch ends
     * @param _epoch epoch that ended
     * @param _endBalance epoch end balance
     * @param _startBalance epoch start balance
     */
    event EpochEnded(uint256 indexed _epoch, uint256 _endBalance, uint256 _startBalance);

    /**
     * @notice Emitted when epoch starts
     * @param _epoch epoch started
     * @param _startBalance epoch start balance
     */
    event EpochStart(uint256 indexed _epoch, uint256 _startBalance);

    /**
     * @notice Emitted when a strategy borrows funds from the vault
     * @param _strategy address of the strategy
     * @param _amount the amount taken
     */
    event Borrowed(address indexed _strategy, uint256 _amount);

    /**
     * @notice Emitted when a strategy repays funds to the vault
     * @param _strategy address of the strategy
     * @param _amount the amount taken
     */
    event Repayed(address indexed _strategy, uint256 _amount);

    /**
     * @notice Emitted when someone updates the risk percentage
     * @param _governor governor that ran the update
     * @param _oldRate rate before the update
     * @param _newRate rate after the update
     */
    event RiskPercentageUpdated(address indexed _governor, uint256 _oldRate, uint256 _newRate);

    /**
     * @notice Emitted when the vault is paused
     * @param _governor governor that paused the vault
     * @param _epoch final epoch
     */
    event VaultPaused(address indexed _governor, uint256 indexed _epoch);

    // ============================= Errors ================================

    error STARTING_EPOCH_BEFORE_ENDING_LAST();
    error VAULT_PAUSED();
    error EMERGENCY_OFF_NOT_PAUSED();
    error EMERGENCY_AFTER_SIGNAL();
    error TERMINAL_EPOCH_NOT_REACHED();
    error ALREADY_EXITED();
    error ZERO_VALUE();
    error NON_WHITELISTED_FLIP();
    error NO_DEPOSITS_FOR_USER();
    error USER_ALREADY_EXITING();
    error EPOCH_ENDED();
    error CANNOT_WITHDRAW();
    error ALREADY_BORROWED();
    error ALREADY_WHITELISTED();
    error NOT_WHITELISTED();
    error OPERATION_IN_FUTURE();
    error DEPOSITED_THIS_EPOCH();
    error INVALID_SWAP();
    error TARGET_VAULT_FULL();
    error VAULT_FULL();
    error WRONG_VAULT_ARGS();
    error ACTION_FORBIDEN_IN_USER_STATE();
    error FORBIDDEN_SWAP_RECEIVER();
    error FORBIDDEN_SWAP_SOURCE();
    error FORBIDDEN_SWAP_DESTINATION();
    error HIGH_SLIPPAGE();

    // ============================= Structs ================================

    struct Flip {
        uint256 userPercentage;
        address destinationVault;
    }

    struct Epoch {
        uint256 startAmount;
        uint256 endAmount;
    }

    struct UserEpochs {
        uint256[] epochs;
        uint256 end;
        uint256 deposited;
    }
}

