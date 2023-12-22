// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IterableMappingBool.sol";
import "./SafeERC20.sol";

interface IAutoTigAsset is IERC20 {
    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
}

contract TigrisLPStaking is Ownable {

    using SafeERC20 for IERC20;
    using IterableMappingBool for IterableMappingBool.Map;
    IterableMappingBool.Map private assets;
    uint256 public constant DIVISION_CONSTANT = 1e10;
    uint256 public constant MAX_WITHDRAWAL_PERIOD = 30 days;
    uint256 public constant MAX_DEPOSIT_FEE = 1e8; // 1%
    uint256 public constant MAX_EARLY_WITHDRAW_FEE = 25e8; // 25%
    uint256 public constant MIN_INITIAL_DEPOSIT = 1e15;

    address public treasury;
    uint256 public withdrawalPeriod = 7 days;
    uint256 public depositFee;
    uint256 public earlyWithdrawFee = 10e8; // 10%
    bool public earlyWithdrawalEnabled;

    // Assets always have 18 decimals
    mapping(address => uint256) public totalStaked; // [asset] => amount
    mapping(address => uint256) public totalPendingWithdrawal; // [asset] => amount
    mapping(address => mapping(address => bool)) public isUserAutocompounding; // [user][asset] => bool
    mapping(address => mapping(address => uint256)) public userStaked; // [user][asset] => amount
    mapping(address => mapping(address => uint256)) public userPendingWithdrawal; // [user][asset] => amount
    mapping(address => mapping(address => uint256)) public withdrawTimestamp; // [user][asset] => timestamp
    mapping(address => mapping(address => uint256)) public userPaid; // [user][asset] => amount
    mapping(address => uint256) public accRewardsPerToken; // [asset] => amount
    mapping(address => uint256) public compoundedAssetValue; // [asset] => amount
    mapping(address => IAutoTigAsset) public autoTigAsset; // [asset] => autoTigAsset
    mapping(address => uint256) public depositCap; // [asset] => amount

    // Events
    event Staked(address indexed asset, address indexed user, uint256 amount, uint256 fee);
    event WithdrawalInitiated(address indexed asset, address indexed user, uint256 amount, uint256 timestamp);
    event WithdrawalConfirmed(address indexed asset, address indexed user, uint256 amount);
    event WithdrawalCancelled(address indexed asset, address indexed user, uint256 amount);
    event EarlyWithdrawal(address indexed asset, address indexed user, uint256 amount, uint256 fee);
    event LPRewardClaimed(address indexed asset, address indexed user, uint256 amount);
    event LPRewardDistributed(address indexed asset, uint256 amount);
    event AssetWhitelisted(address indexed asset, IAutoTigAsset indexed autoTigAsset);
    event AssetUnwhitelisted(address indexed asset);
    event WithdrawalPeriodUpdated(uint256 newPeriod);
    event TreasuryUpdated(address newTreasury);
    event DepositFeeUpdated(uint256 newFee);
    event EarlyWithdrawFeeUpdated(uint256 newFee);
    event EarlyWithdrawalEnabled(bool enabled);
    event UserAutocompoundingUpdated(address indexed user, address indexed asset, bool isAutocompounding);
    event DepositCapUpdated(address indexed asset, uint256 newCap);

    /**
     * @dev Initializes the TigrisLPStaking contract with the provided treasury address.
     * @param _treasury The address of the treasury where fees will be transferred.
     * @notice The treasury address cannot be the zero address.
     */
    constructor(address _treasury) {
        require(_treasury != address(0), "ZeroAddress");
        treasury = _treasury;
    }

    /**
     * @dev Stakes a specified amount of tigAsset tokens.
     * @param _tigAsset The address of the tigAsset token to stake.
     * @param _amount The amount of tigAsset tokens to stake.
     * @notice The `_amount` will be automatically adjusted to account for the deposit fee, if applicable.
     * @notice If the user has opted for autocompounding, minted AutoTigAsset tokens will be received instead of staking.
     * @notice Emits a `Staked` event on success.
     */
    function stake(address _tigAsset, uint256 _amount) public {
        require(_tigAsset != address(0), "ZeroAddress");
        require(_amount != 0, "ZeroAmount");
        require(assets.get(_tigAsset), "Asset not allowed");
        uint256 _fee;
        if (depositFee != 0) {
            _fee = _amount * depositFee / DIVISION_CONSTANT;
            _amount -= _fee;
        }
        require(totalDeposited(_tigAsset) + totalPendingWithdrawal[_tigAsset] + _amount <= depositCap[_tigAsset], "Deposit cap exceeded");
        _claim(msg.sender, _tigAsset);
        IERC20(_tigAsset).safeTransferFrom(msg.sender, address(this), _amount + _fee);
        IERC20(_tigAsset).safeTransfer(treasury, _fee);
        if (isUserAutocompounding[msg.sender][_tigAsset]) {
            uint256 _autocompoundingAmount = _amount * 1e18 / compoundedAssetValue[_tigAsset];
            autoTigAsset[_tigAsset].mint(msg.sender, _autocompoundingAmount);
        } else {
            totalStaked[_tigAsset] += _amount;
            userStaked[msg.sender][_tigAsset] += _amount;
            userPaid[msg.sender][_tigAsset] = userStaked[msg.sender][_tigAsset] * accRewardsPerToken[_tigAsset] / 1e18;
        }
        emit Staked(_tigAsset, msg.sender, _amount, _fee);
    }

    function initiateWithdrawalMax(address _tigAsset) external {
        initiateWithdrawal(_tigAsset, userDeposited(msg.sender, _tigAsset));
    }

    /**
     * @dev Initiates a withdrawal request for a specified amount of tigAsset tokens.
     * @param _tigAsset The address of the tigAsset token for which the withdrawal is requested.
     * @param _amount The amount of tigAsset tokens to withdraw.
     * @notice Users can initiate withdrawal requests, and the funds will be available for withdrawal after the withdrawal period has elapsed.
     * @notice If the user has opted for autocompounding, AutoTigAsset tokens will be burned instead of withdrawing LP tokens.
     * @notice Emits a `WithdrawalInitiated` event on success.
     */
    function initiateWithdrawal(address _tigAsset, uint256 _amount) public {
        require(_tigAsset != address(0), "ZeroAddress");
        require(_amount != 0, "Amount must be greater than 0");
        require(userDeposited(msg.sender, _tigAsset) >= _amount, "Not enough staked");
        _claim(msg.sender, _tigAsset);
        if (isUserAutocompounding[msg.sender][_tigAsset]) {
            uint256 _autocompoundingAmount = _amount * 1e18 / compoundedAssetValue[_tigAsset];
            autoTigAsset[_tigAsset].burn(msg.sender, _autocompoundingAmount);
        } else {
            totalStaked[_tigAsset] -= _amount;
            userStaked[msg.sender][_tigAsset] -= _amount;
            userPaid[msg.sender][_tigAsset] = userStaked[msg.sender][_tigAsset] * accRewardsPerToken[_tigAsset] / 1e18;
        }
        userPendingWithdrawal[msg.sender][_tigAsset] += _amount;
        totalPendingWithdrawal[_tigAsset] += _amount;
        withdrawTimestamp[msg.sender][_tigAsset] = block.timestamp + withdrawalPeriod;
        emit WithdrawalInitiated(_tigAsset, msg.sender, _amount, withdrawTimestamp[msg.sender][_tigAsset]);
        // No need to wait for a 2-step withdrawal if the withdrawal period is 0
        if (withdrawalPeriod == 0) {
            confirmWithdrawal(_tigAsset);
        }
    }

    /**
     * @dev Confirms a withdrawal request for a specified amount of tigAssets.
     * @param _tigAsset The address of the tigAsset for which the withdrawal is confirmed.
     * @notice Users can confirm their withdrawal request after the withdrawal period has elapsed.
     * @notice Emits a `WithdrawalConfirmed` event on success.
     */
    function confirmWithdrawal(address _tigAsset) public {
        require(_tigAsset != address(0), "ZeroAddress");
        uint256 _pendingWithdrawal = userPendingWithdrawal[msg.sender][_tigAsset];
        require(_pendingWithdrawal != 0, "Nothing to withdraw");
        require(block.timestamp >= withdrawTimestamp[msg.sender][_tigAsset], "Withdrawal not ready");
        delete userPendingWithdrawal[msg.sender][_tigAsset];
        totalPendingWithdrawal[_tigAsset] -= _pendingWithdrawal;
        IERC20(_tigAsset).safeTransfer(msg.sender, _pendingWithdrawal);
        emit WithdrawalConfirmed(_tigAsset, msg.sender, _pendingWithdrawal);
    }

    /**
     * @dev Cancels a withdrawal request for a specified amount of tigAssets.
     * @param _tigAsset The address of the tigAsset for which the withdrawal is cancelled.
     * @notice Users can cancel their withdrawal request before the withdrawal period has elapsed.
     * @notice If the user has opted for autocompounding, the cancelled tigAssets will be converted back to AutoTigAsset tokens.
     * @notice Emits a `WithdrawalCancelled` event on success.
     */
    function cancelWithdrawal(address _tigAsset) external {
        require(_tigAsset != address(0), "ZeroAddress");
        uint256 _pendingWithdrawal = userPendingWithdrawal[msg.sender][_tigAsset];
        require(_pendingWithdrawal != 0, "Nothing to cancel");
        _claim(msg.sender, _tigAsset);
        delete userPendingWithdrawal[msg.sender][_tigAsset];
        totalPendingWithdrawal[_tigAsset] -= _pendingWithdrawal;
        if (isUserAutocompounding[msg.sender][_tigAsset]) {
            uint256 _autocompoundingAmount = _pendingWithdrawal * 1e18 / compoundedAssetValue[_tigAsset];
            autoTigAsset[_tigAsset].mint(msg.sender, _autocompoundingAmount);
        } else {
            totalStaked[_tigAsset] += _pendingWithdrawal;
            userStaked[msg.sender][_tigAsset] += _pendingWithdrawal;
            userPaid[msg.sender][_tigAsset] = userStaked[msg.sender][_tigAsset] * accRewardsPerToken[_tigAsset] / 1e18;
        }
        emit WithdrawalCancelled(_tigAsset, msg.sender, _pendingWithdrawal);
    }

    function earlyWithdrawalMax(address _tigAsset) external {
        earlyWithdrawal(_tigAsset, userDeposited(msg.sender, _tigAsset));
    }

    /**
     * @dev Performs an early withdrawal of a specified amount of tigAssets.
     * @param _tigAsset The address of the tigAsset for which the early withdrawal is performed.
     * @param _amount The amount of tigAssets to withdraw.
     * @notice Early withdrawal incurs a penalty fee, which is defined by the `earlyWithdrawFee` variable.
     * @notice Users can perform early withdrawal if the `earlyWithdrawalEnabled` variable is set to true.
     * @notice Emits an `EarlyWithdrawal` event on success.
     */
    function earlyWithdrawal(address _tigAsset, uint256 _amount) public {
        require(earlyWithdrawalEnabled, "Early withdrawal disabled");
        require(_tigAsset != address(0), "ZeroAddress");
        require(_amount != 0, "Amount must be greater than 0");
        require(userDeposited(msg.sender, _tigAsset) >= _amount, "Not enough staked");
        require(userPendingWithdrawal[msg.sender][_tigAsset] == 0, "Withdrawal already initiated");
        _claim(msg.sender, _tigAsset);
        if (isUserAutocompounding[msg.sender][_tigAsset]) {
            uint256 _autocompoundingAmount = _amount * 1e18 / compoundedAssetValue[_tigAsset];
            autoTigAsset[_tigAsset].burn(msg.sender, _autocompoundingAmount);
        } else {
            totalStaked[_tigAsset] -= _amount;
            userStaked[msg.sender][_tigAsset] -= _amount;
            userPaid[msg.sender][_tigAsset] = userStaked[msg.sender][_tigAsset] * accRewardsPerToken[_tigAsset] / 1e18;
        }
        uint256 _fee = _amount * earlyWithdrawFee / DIVISION_CONSTANT;
        _amount = _amount - _fee;
        IERC20(_tigAsset).safeTransfer(treasury, _fee);
        IERC20(_tigAsset).safeTransfer(msg.sender, _amount);
        emit EarlyWithdrawal(_tigAsset, msg.sender, _amount, _fee);
    }

    /**
     * @dev Allows users to claim their accrued tigAsset rewards.
     * @param _tigAsset The address of the tigAsset token for which the rewards are claimed.
     * @notice The accrued rewards are calculated based on the user's share of staked tigAsset tokens and the distributed rewards.
     * @notice Emits a `LPRewardClaimed` event on success.
     */
    function claim(address _tigAsset) public {
        _claim(msg.sender, _tigAsset);
    }

    function _claim(address _user, address _tigAsset) internal {
        require(_tigAsset != address(0), "ZeroAddress");
        uint256 _pending = pending(_user, _tigAsset);
        if (_pending == 0) return;
        userPaid[_user][_tigAsset] += _pending;
        IERC20(_tigAsset).safeTransfer(_user, _pending);
        emit LPRewardClaimed(_tigAsset, _user, _pending);
    }

    /**
     * @dev Distributes rewards to stakers and autocompounders of a whitelisted tigAsset.
     * @param _tigAsset The address of the tigAsset for which the rewards are being distributed.
     * @param _amount The amount of tigAsset rewards to be distributed.
     * @notice Only the contract owner can distribute rewards to stakers and autocompounders.
     * @notice The rewards are distributed proportionally based on the total staked tigAssets and the total autocompounded tigAssets.
     * @notice The distributed rewards are added to the reward pool and affect the reward accrual rate.
     * @notice Emits an `LPRewardDistributed` event on success.
     */
    function distribute(
        address _tigAsset,
        uint256 _amount
    ) external {
        require(_tigAsset != address(0), "ZeroAddress");
        if (!assets.get(_tigAsset) || totalDeposited(_tigAsset) == 0 || _amount == 0) return;
        try IERC20(_tigAsset).transferFrom(msg.sender, address(this), _amount) {} catch {
            return;
        }
        uint256 _toDistributeToStakers = _amount * totalStaked[_tigAsset] / totalDeposited(_tigAsset);
        uint256 _toDistributeToAutocompounders = _amount - _toDistributeToStakers;
        if (_toDistributeToStakers != 0) {
            accRewardsPerToken[_tigAsset] += _toDistributeToStakers * 1e18 / totalStaked[_tigAsset];
        }
        if (_toDistributeToAutocompounders != 0) {
            compoundedAssetValue[_tigAsset] += _toDistributeToAutocompounders * 1e18 / totalAutocompounding(_tigAsset);
        }
        emit LPRewardDistributed(_tigAsset, _amount);
    }

    /**
     * @dev Sets the autocompounding option for a tigAsset.
     * @param _tigAsset The address of the tigAsset for which the autocompounding option is being set.
     * @param _isAutocompounding A boolean indicating whether autocompounding is enabled or disabled for the user.
     * @notice Users can enable or disable autocompounding for their staked tigAssets.
     * @notice If autocompounding is enabled, tigAssets will be converted to AutoTigAsset tokens.
     * @notice If autocompounding is disabled, AutoTigAsset tokens will be converted back to tigAssets.
     * @notice Emits a `UserAutocompoundingUpdated` event on success.
     */
    function setAutocompounding(address _tigAsset, bool _isAutocompounding) public {
        require(_tigAsset != address(0), "ZeroAddress");
        _claim(msg.sender, _tigAsset);
        isUserAutocompounding[msg.sender][_tigAsset] = _isAutocompounding;
        if (_isAutocompounding) {
            uint256 _toCompoundedAssets = userStaked[msg.sender][_tigAsset] * 1e18 / compoundedAssetValue[_tigAsset];
            totalStaked[_tigAsset] -= userStaked[msg.sender][_tigAsset];
            delete userStaked[msg.sender][_tigAsset];
            autoTigAsset[_tigAsset].mint(msg.sender, _toCompoundedAssets);
        } else {
            uint256 _autoTigAssetBalance = userAutocompounding(msg.sender, _tigAsset);
            uint256 _toStakedAssets = _autoTigAssetBalance * compoundedAssetValue[_tigAsset] / 1e18;
            autoTigAsset[_tigAsset].burn(msg.sender, _autoTigAssetBalance);
            userPaid[msg.sender][_tigAsset] += _toStakedAssets * accRewardsPerToken[_tigAsset] / 1e18;
            totalStaked[_tigAsset] += _toStakedAssets;
            userStaked[msg.sender][_tigAsset] += _toStakedAssets;
        }
        emit UserAutocompoundingUpdated(msg.sender, _tigAsset, _isAutocompounding);
    }

    /**
     * @dev Whitelists an tigAsset for staking.
     * @param _tigAsset The address of the tigAsset to be whitelisted.
     * @param _initialDeposit The initial amount of tigAsset to be deposited after whitelisting.
     * @notice Only the contract owner can whitelist tigAssets.
     * @notice Emits an `AssetWhitelisted` event on success.
     */
    function whitelistAsset(address _tigAsset, uint256 _initialDeposit) external onlyOwner {
        require(_tigAsset != address(0), "ZeroAddress");
        require(!assets.get(_tigAsset), "Already whitelisted");
        assets.set(_tigAsset);
        IAutoTigAsset _autoTigAsset = autoTigAsset[_tigAsset];
        if (address(_autoTigAsset) == address(0)) {
            require(_initialDeposit >= MIN_INITIAL_DEPOSIT, "Initial deposit too small");
            _autoTigAsset = new AutoTigAsset(_tigAsset);
            autoTigAsset[_tigAsset] = _autoTigAsset;
            compoundedAssetValue[_tigAsset] = 1e18;
            // Prevent small malicious first deposit
            setAutocompounding(_tigAsset, true);
            stake(_tigAsset, _initialDeposit);
        }
        emit AssetWhitelisted(_tigAsset, _autoTigAsset);
    }

    /**
     * @dev Removes an tigAsset from the whitelist.
     * @param _tigAsset The address of the tigAsset to be removed from the whitelist.
     * @notice Only the contract owner can remove tigAsset from the whitelist.
     * @notice Emits an `AssetUnwhitelisted` event on success.
     */
    function unwhitelistAsset(address _tigAsset) external onlyOwner {
        require(_tigAsset != address(0), "ZeroAddress");
        require(assets.get(_tigAsset), "Not whitelisted");
        assets.remove(_tigAsset);
        emit AssetUnwhitelisted(_tigAsset);
    }

    /**
     * @dev Updates the withdrawal period.
     * @param _withdrawalPeriod The new withdrawal period, specified in seconds.
     * @notice Only the contract owner can update the withdrawal period.
     * @notice The maximum allowed withdrawal period is `MAX_WITHDRAWAL_PERIOD`.
     * @notice Emits a `WithdrawalPeriodUpdated` event on success.
     */
    function setWithdrawalPeriod(uint256 _withdrawalPeriod) external onlyOwner {
        require(_withdrawalPeriod <= MAX_WITHDRAWAL_PERIOD, "Withdrawal period too long");
        withdrawalPeriod = _withdrawalPeriod;
        emit WithdrawalPeriodUpdated(_withdrawalPeriod);
    }

    /**
     * @dev Updates the treasury address to receive fees.
     * @param _treasury The address of the new treasury contract.
     * @notice Only the contract owner can update the treasury address.
     * @notice Emits a `TreasuryUpdated` event on success.
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "ZeroAddress");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /**
     * @dev Updates the deposit fee for tigAssets.
     * @param _depositFee The new deposit fee, expressed as a percentage with `DIVISION_CONSTANT` divisor.
     * @notice Only the contract owner can update the deposit fee.
     * @notice The maximum allowed deposit fee is `MAX_DEPOSIT_FEE`.
     * @notice Emits a `DepositFeeUpdated` event on success.
     */
    function setDepositFee(uint256 _depositFee) external onlyOwner {
        require(_depositFee <= MAX_DEPOSIT_FEE, "Fee too high");
        depositFee = _depositFee;
        emit DepositFeeUpdated(_depositFee);
    }

    /**
     * @dev Updates the early withdrawal fee for tigAssets.
     * @param _earlyWithdrawFee The new early withdrawal fee, expressed as a percentage with `DIVISION_CONSTANT` divisor.
     * @notice Only the contract owner can update the early withdrawal fee.
     * @notice The maximum allowed early withdrawal fee is `MAX_EARLY_WITHDRAW_FEE`.
     * @notice Emits an `EarlyWithdrawFeeUpdated` event on success.
     */
    function setEarlyWithdrawFee(uint256 _earlyWithdrawFee) external onlyOwner {
        require(_earlyWithdrawFee <= MAX_EARLY_WITHDRAW_FEE, "Fee too high");
        earlyWithdrawFee = _earlyWithdrawFee;
        emit EarlyWithdrawFeeUpdated(_earlyWithdrawFee);
    }

    /**
     * @dev Enables or disables early withdrawal for tigAssets.
     * @param _enabled A boolean indicating whether early withdrawal is enabled or disabled.
     * @notice Only the contract owner can enable or disable early withdrawal.
     * @notice Emits an `EarlyWithdrawalEnabled` event on success.
     */
    function setEarlyWithdrawalEnabled(bool _enabled) external onlyOwner {
        earlyWithdrawalEnabled = _enabled;
        emit EarlyWithdrawalEnabled(_enabled);
    }

    /**
     * @dev Updates the deposit cap for a tigAsset.
     * @param _tigAsset The address of the tigAsset for which the deposit cap is being updated.
     * @param _depositCap The new deposit cap for the tigAsset.
     * @notice Only the contract owner can update the deposit cap for tigAssets.
     * @notice Emits a `DepositCapUpdated` event on success.
     */
    function setDepositCap(address _tigAsset, uint256 _depositCap) external onlyOwner {
        require(_tigAsset != address(0), "ZeroAddress");
        depositCap[_tigAsset] = _depositCap;
        emit DepositCapUpdated(_tigAsset, _depositCap);
    }

    /**
     * @dev Returns the total amount of tigAssets deposited and autocompounded for a specific tigAsset.
     * @param _tigAsset The address of the tigAsset for which the total deposited amount is requested.
     * @return The total amount of tigAssets deposited and autocompounded for the given tigAsset.
     */
    function totalDeposited(address _tigAsset) public view returns (uint256) {
        return totalAutocompounding(_tigAsset) * compoundedAssetValue[_tigAsset] / 1e18 + totalStaked[_tigAsset];
    }

    /**
     * @dev Returns the pending rewards of a user for a specific tigAsset.
     * @param _user The address of the user for whom the pending rewards are requested.
     * @param _tigAsset The address of the tigAsset for which the pending rewards are requested.
     * @return The amount of pending rewards for the user in the given tigAsset.
     * @notice If the user has autocompounding enabled for the tigAsset, the function returns 0, as autocompounders do not earn rewards as pending rewards.
     */
    function pending(address _user, address _tigAsset) public view returns (uint256) {
        if (isUserAutocompounding[_user][_tigAsset]) {
            return 0;
        }
        return userStaked[_user][_tigAsset] * accRewardsPerToken[_tigAsset] / 1e18 - userPaid[_user][_tigAsset];
    }

    /**
     * @dev Returns the total amount of tigAssets deposited by a user for a specific tigAsset.
     * @param _user The address of the user for whom the deposited amount is requested.
     * @param _tigAsset The address of the tigAsset for which the deposited amount is requested.
     * @return The total amount of tigAssets deposited by the user in the given tigAsset.
     * @notice If the user has autocompounding enabled for the tigAsset, the function returns the equivalent amount of tigAssets based on the compoundedAssetValue.
     * @notice If the user does not have autocompounding enabled, the function returns the amount of tigAssets staked directly.
     */
    function userDeposited(address _user, address _tigAsset) public view returns (uint256) {
        if (isUserAutocompounding[_user][_tigAsset]) {
            return userAutocompounding(_user, _tigAsset) * compoundedAssetValue[_tigAsset] / 1e18;
        } else {
            return userStaked[_user][_tigAsset];
        }
    }

    /**
     * @dev Returns the total amount of AutoTigAsset tokens (autocompounded tigAssets) for a specific tigAsset.
     * @param _tigAsset The address of the tigAsset for which the total autocompounded amount is requested.
     * @return The total amount of AutoTigAsset tokens (autocompounded tigAssets) for the given tigAsset.
     */
    function totalAutocompounding(address _tigAsset) public view returns (uint256) {
        return IERC20(autoTigAsset[_tigAsset]).totalSupply();
    }

    /**
     * @dev Returns the amount of AutoTigAsset tokens (autocompounded tigAssets) held by a user for a specific tigAsset.
     * @param _user The address of the user for whom the amount of AutoTigAsset tokens is requested.
     * @param _tigAsset The address of the tigAsset for which the amount of AutoTigAsset tokens is requested.
     * @return The amount of AutoTigAsset tokens held by the user for the given tigAsset.
     */
    function userAutocompounding(address _user, address _tigAsset) public view returns (uint256) {
        return IERC20(autoTigAsset[_tigAsset]).balanceOf(_user);
    }

    /**
     * @dev Checks if a tigAsset is whitelisted.
     * @param _tigAsset The address of the tigAsset to be checked.
     * @return A boolean indicating whether the tigAsset is whitelisted.
     */
    function isAssetWhitelisted(address _tigAsset) external view returns (bool) {
        return assets.get(_tigAsset);
    }
}

/**
 * @title AutoTigAsset
 * @dev A token contract representing AutoTigAsset tokens, which are minted and burned for users who enable autocompounding.
 */
contract AutoTigAsset is ERC20, IAutoTigAsset {

    address public immutable underlying;
    address public immutable factory;

    /**
     * @dev Creates AutoTigAsset tokens for a specific tigAsset.
     * @param _tigAsset The address of the tigAsset to be represented by the AutoTigAsset tokens.
     */
    constructor(
        address _tigAsset
    ) ERC20(
        string(abi.encodePacked("Autocompounding ", ERC20(_tigAsset).name())),
        string(abi.encodePacked("auto", ERC20(_tigAsset).symbol()))
    ) {
        require(_tigAsset != address(0), "ZeroAddress");
        underlying = _tigAsset;
        factory = msg.sender;
    }

    /**
     * @dev Modifier to restrict minting and burning to the contract factory (TigrisLPStaking).
     */
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory");
        _;
    }

    /**
     * @dev Mints AutoTigAsset tokens to a specified address.
     * @param _to The address to which the AutoTigAsset tokens will be minted.
     * @param _amount The amount of AutoTigAsset tokens to mint.
     * @notice Only the contract factory (TigrisLPStaking) can mint AutoTigAsset tokens.
     */
    function mint(address _to, uint256 _amount) external onlyFactory {
        _mint(_to, _amount);
    }

    /**
     * @dev Burns AutoTigAsset tokens from a specified address.
     * @param _from The address from which the AutoTigAsset tokens will be burned.
     * @param _amount The amount of AutoTigAsset tokens to burn.
     * @notice Only the contract factory (TigrisLPStaking) can burn AutoTigAsset tokens.
     */
    function burn(address _from, uint256 _amount) external onlyFactory {
        _burn(_from, _amount);
    }
}


