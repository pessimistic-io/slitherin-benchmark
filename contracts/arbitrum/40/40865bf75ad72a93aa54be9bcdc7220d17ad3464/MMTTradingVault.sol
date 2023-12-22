// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./ERC20Upgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./MathUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IVault.sol";
import "./IMmtToken.sol";
import "./INft.sol";
import "./IOpenTradesPnlFeed.sol";

contract MMTTradingVault is
    ERC20Upgradeable,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    IVault
{
    using MathUpgradeable for uint256;

    // Contracts & Addresses (constant)
    address public mttToken;
    INft public lockedDepositNft;

    // Contracts & Addresses (adjustable)
    address public manager; // 3-day timelock contract
    address public admin; // bypasses timelock, access to emergency functions

    address public pnlHandler;
    IOpenTradesPnlFeed public openTradesPnlFeed;
    MMTPriceProvider public mmtPriceProvider;

    struct MMTPriceProvider {
        address addr;
        bytes signature;
    }

    // Parameters (constant)
    uint256 constant PRECISION = 1e18; // 18 decimals (acc values & price)
    uint256 constant MMT_PRECISION = 1e10; // 10 decimals (mmt/asset oracle)
    uint256 constant MIN_DAILY_ACC_PNL_DELTA = PRECISION / 10; // 0.1 (price delta)
    uint256 constant MAX_SUPPLY_INCREASE_DAILY_P = 50 * PRECISION; // 50% / day (when under collat)
    uint256 constant MAX_LOSSES_BURN_P = 25 * PRECISION; // 25% of all losses
    uint256 constant MAX_MMT_SUPPLY_MINT_DAILY_P = PRECISION / 20; // 0.05% / day (18.25% / yr max)
    uint256 constant MAX_DISCOUNT_P = 10 * PRECISION; // 10%
    uint256 public MIN_LOCK_DURATION; // min locked asset deposit duration
    uint256 constant MAX_LOCK_DURATION = 365 days; // max locked asset deposit duration
    uint256[] WITHDRAW_EPOCHS_LOCKS; // epochs withdraw locks at over collat thresholds

    // Parameters (adjustable)
    uint256 public maxAccOpenPnlDelta; // PRECISION (max price delta on new epochs from open pnl)
    uint256 public maxDailyAccPnlDelta; // PRECISION (max daily price delta from closed pnl)
    uint256[2] public withdrawLockThresholdsP; // PRECISION (% of over collat, used with WITHDRAW_EPOCHS_LOCKS)
    uint256 public maxSupplyIncreaseDailyP; // PRECISION (% per day, when under collat)
    uint256 public lossesBurnP; // PRECISION (% of all losses)
    uint256 public maxMmtSupplyMintDailyP; // PRECISION (% of mmt supply)
    uint256 public maxDiscountP; // PRECISION (%, maximum discount for locked deposits)
    uint256 public maxDiscountThresholdP; // PRECISION (maximum collat %, for locked deposits)

    // Price state
    uint256 public shareToAssetsPrice; // PRECISION
    int256 public accPnlPerTokenUsed; // PRECISION (snapshot of accPnlPerToken)
    int256 public accPnlPerToken; // PRECISION (updated in real-time)
    uint256 public accRewardsPerToken; // PRECISION

    // Closed Pnl state
    int256 public dailyAccPnlDelta; // PRECISION
    uint256 public lastDailyAccPnlDeltaReset; // timestamp

    // Epochs state (withdrawals)
    uint256 public currentEpoch; // global id
    uint256 public currentEpochStart; // timestamp
    uint256 public currentEpochPositiveOpenPnl; // 1e18

    // Deposit / Withdraw state
    uint256 public currentMaxSupply; // 1e18
    uint256 public lastMaxSupplyUpdate; // timestamp
    mapping(address => mapping(uint256 => uint256)) public withdrawRequests; // owner => unlock epoch => shares

    // Locked deposits state
    uint256 public lockedDepositsCount; // global id
    mapping(uint256 => LockedDeposit) public lockedDeposits;

    // Deplete / Refill state
    uint256 public assetsToDeplete; // 1e18
    uint256 public dailyMintedMmt; // 1e18
    uint256 public lastDailyMintedMmtReset; // timestamp

    // Statistics (not used for contract logic)
    uint256 public totalDeposited; // 1e18 (assets)
    int256 public totalClosedPnl; // 1e18 (assets)
    uint256 public totalRewards; // 1e18 (assets)
    int256 public totalLiability; // 1e18 (assets)
    uint256 public totalLockedDiscounts; // 1e18 (assets)
    uint256 public totalDiscounts; // 1e18 (assets)
    uint256 public totalDepleted; // 1e18 (assets)
    uint256 public totalDepletedMmt; // 1e18 (mmt)
    uint256 public totalRefilled; // 1e18 (assets)
    uint256 public totalRefilledMmt; // 1e18 (mmt)

    // Events
    event AddressParamUpdated(string name, address newValue);
    event MMTPriceProviderUpdated(MMTPriceProvider newValue);
    event NumberParamUpdated(string name, uint256 newValue);
    event WithdrawLockThresholdsPUpdated(uint256[2] newValue);

    event CurrentMaxSupplyUpdated(uint256 newValue);
    event DailyAccPnlDeltaReset();
    event ShareToAssetsPriceUpdated(uint256 newValue);
    event OpenTradesPnlFeedCallFailed();

    event WithdrawRequested(
        address indexed sender,
        address indexed owner,
        uint256 shares,
        uint256 currEpoch,
        uint256 indexed unlockEpoch
    );
    event WithdrawCanceled(
        address indexed sender,
        address indexed owner,
        uint256 shares,
        uint256 currEpoch,
        uint256 indexed unlockEpoch
    );

    event DepositLocked(
        address indexed sender,
        address indexed owner,
        uint256 depositId,
        LockedDeposit d
    );
    event DepositUnlocked(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 depositId,
        LockedDeposit d
    );

    event RewardDistributed(address indexed sender, uint256 assets);

    event AssetsSent(
        address indexed sender,
        address indexed receiver,
        uint256 assets
    );
    event AssetsReceived(
        address indexed sender,
        address indexed user,
        uint256 assets,
        uint256 assetsLessDeplete
    );

    event Depleted(address indexed sender, uint256 assets, uint256 amountMmt);
    event Refilled(address indexed sender, uint256 assets, uint256 amountMmt);

    event AccPnlPerTokenUsedUpdated(
        address indexed sender,
        uint256 indexed newEpoch,
        uint256 prevPositiveOpenPnl,
        uint256 newPositiveOpenPnl,
        uint256 newEpochPositiveOpenPnl,
        int256 newAccPnlPerTokenUsed
    );

    // Prevent stack too deep error
    struct ContractAddresses {
        address asset;
        address owner; // 2-week timelock contract
        address manager; // 3-day timelock contract
        address admin; // bypasses timelock, access to emergency functions
        address mttToken;
        address lockedDepositNft;
        address pnlHandler; //callback
        address openTradesPnlFeed;
        MMTPriceProvider mmtPriceProvider;
    }

    // Initializer function called when this contract is deployed
    function initialize(
        string memory _name,
        string memory _symbol,
        ContractAddresses memory _contractAddresses,
        uint256 _MIN_LOCK_DURATION,
        uint256 _maxAccOpenPnlDelta,
        uint256 _maxDailyAccPnlDelta,
        uint256[2] memory _withdrawLockThresholdsP,
        uint256 _maxSupplyIncreaseDailyP,
        uint256 _lossesBurnP,
        uint256 _maxMmtSupplyMintDailyP,
        uint256 _maxDiscountP,
        uint256 _maxDiscountThresholdP
    ) external initializer {
        require(
            _contractAddresses.asset != address(0) &&
                _contractAddresses.owner != address(0) &&
                _contractAddresses.manager != address(0) &&
                _contractAddresses.admin != address(0) &&
                _contractAddresses.owner != _contractAddresses.manager &&
                _contractAddresses.manager != _contractAddresses.admin &&
                _contractAddresses.mttToken != address(0) &&
                _contractAddresses.lockedDepositNft != address(0) &&
                _contractAddresses.pnlHandler != address(0) &&
                _contractAddresses.openTradesPnlFeed != address(0) &&
                _contractAddresses.mmtPriceProvider.addr != address(0) &&
                _contractAddresses.mmtPriceProvider.signature.length > 0 &&
                _maxDailyAccPnlDelta >= MIN_DAILY_ACC_PNL_DELTA &&
                _withdrawLockThresholdsP[1] > _withdrawLockThresholdsP[0] &&
                _maxSupplyIncreaseDailyP <= MAX_SUPPLY_INCREASE_DAILY_P &&
                _lossesBurnP <= MAX_LOSSES_BURN_P &&
                _maxMmtSupplyMintDailyP <= MAX_MMT_SUPPLY_MINT_DAILY_P &&
                _maxDiscountP <= MAX_DISCOUNT_P &&
                _maxDiscountThresholdP >= 100 * PRECISION,
            "WRONG_PARAMS"
        );

        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20MetadataUpgradeable(_contractAddresses.asset));
        _transferOwnership(_contractAddresses.owner);

        mttToken = _contractAddresses.mttToken;
        lockedDepositNft = INft(_contractAddresses.lockedDepositNft);
        manager = _contractAddresses.manager;
        admin = _contractAddresses.admin;
        pnlHandler = _contractAddresses.pnlHandler;
        openTradesPnlFeed = IOpenTradesPnlFeed(
            _contractAddresses.openTradesPnlFeed
        );
        mmtPriceProvider = _contractAddresses.mmtPriceProvider;

        MIN_LOCK_DURATION = _MIN_LOCK_DURATION;

        maxAccOpenPnlDelta = _maxAccOpenPnlDelta;
        maxDailyAccPnlDelta = _maxDailyAccPnlDelta;
        withdrawLockThresholdsP = _withdrawLockThresholdsP;
        maxSupplyIncreaseDailyP = _maxSupplyIncreaseDailyP;
        lossesBurnP = _lossesBurnP;
        maxMmtSupplyMintDailyP = _maxMmtSupplyMintDailyP;
        maxDiscountP = _maxDiscountP;
        maxDiscountThresholdP = _maxDiscountThresholdP;

        shareToAssetsPrice = PRECISION;
        currentEpoch = 1;
        currentEpochStart = block.timestamp;
        WITHDRAW_EPOCHS_LOCKS = [3, 2, 1];
    }

    // Modifiers
    modifier onlyManager() {
        require(_msgSender() == manager, "ONLY_MANAGER");
        _;
    }

    modifier checks(uint256 assetsOrShares) {
        require(shareToAssetsPrice > 0, "PRICE_0");
        require(assetsOrShares > 0, "VALUE_0");
        _;
    }

    modifier validDiscount(uint256 lockDuration) {
        require(maxDiscountP > 0, "NO_ACTIVE_DISCOUNT");
        require(lockDuration >= MIN_LOCK_DURATION, "BELOW_MIN_LOCK_DURATION");
        require(lockDuration <= MAX_LOCK_DURATION, "ABOVE_MAX_LOCK_DURATION");
        _;
    }

    // Manage addresses
    function transferOwnership(address newOwner) public override onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        require(newOwner != manager && newOwner != admin, "WRONG_VALUE");
        _transferOwnership(newOwner);
    }

    function updateToken(address _mttToken) external onlyOwner {
        mttToken = _mttToken;
    }

    function updateManager(address newValue) external onlyOwner {
        require(newValue != address(0), "ADDRESS_0");
        require(newValue != owner() && newValue != admin, "WRONG_VALUE");
        manager = newValue;
        emit AddressParamUpdated("manager", newValue);
    }

    function updateAdmin(address newValue) external onlyManager {
        require(newValue != address(0), "ADDRESS_0");
        require(newValue != owner() && newValue != manager, "WRONG_VALUE");
        admin = newValue;
        emit AddressParamUpdated("admin", newValue);
    }

    function updatePnlHandler(address newValue) external onlyOwner {
        require(newValue != address(0), "ADDRESS_0");
        pnlHandler = newValue;
        emit AddressParamUpdated("pnlHandler", newValue);
    }

    function updatemmtPriceProvider(MMTPriceProvider memory newValue)
        external
        onlyManager
    {
        require(newValue.addr != address(0), "ADDRESS_0");
        require(newValue.signature.length > 0, "BYTES_0");
        mmtPriceProvider = newValue;
        emit MMTPriceProviderUpdated(newValue);
    }

    function updateOpenTradesPnlFeed(address newValue) external onlyOwner {
        require(newValue != address(0), "ADDRESS_0");
        openTradesPnlFeed = IOpenTradesPnlFeed(newValue);
        emit AddressParamUpdated("openTradesPnlFeed", newValue);
    }

    // Manage parameters
    function updateMaxAccOpenPnlDelta(uint256 newValue) external onlyOwner {
        maxAccOpenPnlDelta = newValue;
        emit NumberParamUpdated("maxAccOpenPnlDelta", newValue);
    }

    function updateMaxDailyAccPnlDelta(uint256 newValue) external onlyManager {
        require(newValue >= MIN_DAILY_ACC_PNL_DELTA, "BELOW_MIN");
        maxDailyAccPnlDelta = newValue;
        emit NumberParamUpdated("maxDailyAccPnlDelta", newValue);
    }

    function updateWithdrawLockThresholdsP(uint256[2] memory newValue)
        external
        onlyOwner
    {
        require(newValue[1] > newValue[0], "WRONG_VALUES");
        withdrawLockThresholdsP = newValue;
        emit WithdrawLockThresholdsPUpdated(newValue);
    }

    function updateMaxSupplyIncreaseDailyP(uint256 newValue)
        external
        onlyManager
    {
        require(newValue <= MAX_SUPPLY_INCREASE_DAILY_P, "ABOVE_MAX");
        maxSupplyIncreaseDailyP = newValue;
        emit NumberParamUpdated("maxSupplyIncreaseDailyP", newValue);
    }

    function updateLossesBurnP(uint256 newValue) external onlyManager {
        require(newValue <= MAX_LOSSES_BURN_P, "ABOVE_MAX");
        lossesBurnP = newValue;
        emit NumberParamUpdated("lossesBurnP", newValue);
    }

    function updateMaxMmtSupplyMintDailyP(uint256 newValue)
        external
        onlyManager
    {
        require(newValue <= MAX_MMT_SUPPLY_MINT_DAILY_P, "ABOVE_MAX");
        maxMmtSupplyMintDailyP = newValue;
        emit NumberParamUpdated("maxMmtSupplyMintDailyP", newValue);
    }

    function updateMaxDiscountP(uint256 newValue) external onlyManager {
        require(newValue <= MAX_DISCOUNT_P, "ABOVE_MAX_DISCOUNT");
        maxDiscountP = newValue;
        emit NumberParamUpdated("maxDiscountP", newValue);
    }

    function updateMaxDiscountThresholdP(uint256 newValue)
        external
        onlyManager
    {
        require(newValue >= 100 * PRECISION, "BELOW_MIN");
        maxDiscountThresholdP = newValue;
        emit NumberParamUpdated("maxDiscountThresholdP", newValue);
    }

    // View helper functions
    function maxAccPnlPerToken() public view returns (uint256) {
        // PRECISION
        return PRECISION + accRewardsPerToken;
    }

    function collateralizationP() public view returns (uint256) {
        // PRECISION (%)
        uint256 _maxAccPnlPerToken = maxAccPnlPerToken();
        return
            ((
                accPnlPerTokenUsed > 0
                    ? (_maxAccPnlPerToken - uint256(accPnlPerTokenUsed))
                    : (_maxAccPnlPerToken + uint256(accPnlPerTokenUsed * (-1)))
            ) *
                100 *
                PRECISION) / _maxAccPnlPerToken;
    }

    function mttTokenToAssetsPrice() public view returns (uint256 price) {
        // MMT_PRECISION
        (bool success, bytes memory result) = mmtPriceProvider.addr.staticcall(
            mmtPriceProvider.signature
        );

        require(success == true, "MMT_PRICE_CALL_FAILED");
        (price) = abi.decode(result, (uint256));

        require(price > 0, "MMT_TOKEN_PRICE_0");
    }

    function withdrawEpochsTimelock() public view returns (uint256) {
        uint256 collatP = collateralizationP();
        uint256 overCollatP = (collatP -
            MathUpgradeable.min(collatP, 100 * PRECISION));

        return
            overCollatP > withdrawLockThresholdsP[1]
                ? WITHDRAW_EPOCHS_LOCKS[2]
                : overCollatP > withdrawLockThresholdsP[0]
                ? WITHDRAW_EPOCHS_LOCKS[1]
                : WITHDRAW_EPOCHS_LOCKS[0];
    }

    function lockDiscountP(uint256 collatP, uint256 lockDuration)
        public
        view
        returns (uint256)
    {
        return
            ((
                collatP <= 100 * PRECISION
                    ? maxDiscountP
                    : collatP <= maxDiscountThresholdP
                    ? (maxDiscountP * (maxDiscountThresholdP - collatP)) /
                        (maxDiscountThresholdP - 100 * PRECISION)
                    : 0
            ) * lockDuration) / MAX_LOCK_DURATION;
    }

    function totalSharesBeingWithdrawn(address owner)
        public
        view
        returns (uint256 shares)
    {
        for (
            uint256 i = currentEpoch;
            i <= currentEpoch + WITHDRAW_EPOCHS_LOCKS[0];
            i++
        ) {
            shares += withdrawRequests[owner][i];
        }
    }

    // Public helper functions
    function tryUpdateCurrentMaxSupply() public {
        if (block.timestamp - lastMaxSupplyUpdate >= 24 hours) {
            currentMaxSupply =
                (totalSupply() * (PRECISION * 100 + maxSupplyIncreaseDailyP)) /
                (PRECISION * 100);
            lastMaxSupplyUpdate = block.timestamp;

            emit CurrentMaxSupplyUpdated(currentMaxSupply);
        }
    }

    function tryResetDailyAccPnlDelta() public {
        if (block.timestamp - lastDailyAccPnlDeltaReset >= 24 hours) {
            dailyAccPnlDelta = 0;
            lastDailyAccPnlDeltaReset = block.timestamp;

            emit DailyAccPnlDeltaReset();
        }
    }

    function tryNewOpenPnlRequestOrEpoch() public {
        // Fault tolerance so that activity can continue anyway
        (bool success, ) = address(openTradesPnlFeed).call(
            abi.encodeWithSignature("newOpenPnlRequestOrEpoch()")
        );
        if (!success) {
            emit OpenTradesPnlFeedCallFailed();
        }
    }

    // Private helper functions
    function updateShareToAssetsPrice() private {
        // PRECISION
        shareToAssetsPrice =
            maxAccPnlPerToken() -
            (accPnlPerTokenUsed > 0 ? uint256(accPnlPerTokenUsed) : uint256(0));

        emit ShareToAssetsPriceUpdated(shareToAssetsPrice);
    }

    function _assetIERC20() private view returns (IERC20Upgradeable) {
        return IERC20Upgradeable(asset());
    }

    // Override ERC-20 functions (prevent sending to address that is withdrawing)
    function transfer(address to, uint256 amount)
        public
        override(ERC20Upgradeable)
        returns (bool)
    {
        address sender = _msgSender();
        require(
            totalSharesBeingWithdrawn(sender) <= balanceOf(sender) - amount,
            "PENDING_WITHDRAWAL"
        );
        _transfer(sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override(ERC20Upgradeable) returns (bool) {
        require(
            totalSharesBeingWithdrawn(from) <= balanceOf(from) - amount,
            "PENDING_WITHDRAWAL"
        );
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);
        return true;
    }

    // Override ERC-4626 view functions
    function decimals()
        public
        view
        override(ERC20Upgradeable, ERC4626Upgradeable)
        returns (uint8)
    {
        return ERC4626Upgradeable.decimals();
    }

    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding)
        internal
        view
        override
        returns (uint256 shares)
    {
        return assets.mulDiv(PRECISION, shareToAssetsPrice, rounding);
    }

    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding)
        internal
        view
        override
        returns (uint256 assets)
    {
        // Prevent overflow when called from maxDeposit with maxMint = uint.max
        if (shares == type(uint256).max && shareToAssetsPrice >= PRECISION) {
            return shares;
        }
        return shares.mulDiv(shareToAssetsPrice, PRECISION, rounding);
    }

    function maxMint(address) public view override returns (uint256) {
        return
            accPnlPerTokenUsed > 0
                ? currentMaxSupply -
                    MathUpgradeable.min(currentMaxSupply, totalSupply())
                : type(uint256).max;
    }

    function maxDeposit(address owner) public view override returns (uint256) {
        return _convertToAssets(maxMint(owner), MathUpgradeable.Rounding.Down);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return
            openTradesPnlFeed.nextEpochValuesRequestCount() == 0
                ? MathUpgradeable.min(
                    withdrawRequests[owner][currentEpoch],
                    totalSupply() - 1
                )
                : 0;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return
            _convertToAssets(maxRedeem(owner), MathUpgradeable.Rounding.Down);
    }

    // Override ERC-4626 interactions (call scaleVariables on every deposit / withdrawal)
    function deposit(uint256 assets, address receiver)
        public
        override
        checks(assets)
        returns (uint256)
    {
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more than max"
        );

        uint256 shares = previewDeposit(assets);
        scaleVariables(shares, assets, true);

        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver)
        public
        override
        checks(shares)
        returns (uint256)
    {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");

        uint256 assets = previewMint(shares);
        scaleVariables(shares, assets, true);

        _deposit(_msgSender(), receiver, assets, shares);
        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override checks(assets) returns (uint256) {
        require(
            assets <= maxWithdraw(owner),
            "ERC4626: withdraw more than max"
        );

        uint256 shares = previewWithdraw(assets);
        withdrawRequests[owner][currentEpoch] -= shares;

        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override checks(shares) returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        withdrawRequests[owner][currentEpoch] -= shares;

        uint256 assets = previewRedeem(shares);
        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    function scaleVariables(
        uint256 shares,
        uint256 assets,
        bool isDeposit
    ) private {
        uint256 supply = totalSupply();

        if (accPnlPerToken < 0) {
            accPnlPerToken =
                (accPnlPerToken * int256(supply)) /
                (isDeposit ? int256(supply + shares) : int256(supply - shares));
        } else if (accPnlPerToken > 0) {
            totalLiability +=
                ((int256(shares) * totalLiability) / int256(supply)) *
                (isDeposit ? int256(1) : int256(-1));
        }

        totalDeposited = isDeposit
            ? totalDeposited + assets
            : totalDeposited - assets;
    }

    // Withdraw requests (need to be done before calling 'withdraw' / 'redeem')
    function makeWithdrawRequest(uint256 shares, address owner) external {
        require(
            openTradesPnlFeed.nextEpochValuesRequestCount() == 0,
            "END_OF_EPOCH"
        );

        address sender = _msgSender();
        uint256 allowance = allowance(owner, sender);
        require(
            sender == owner || (allowance > 0 && allowance >= shares),
            "NOT_ALLOWED"
        );

        require(
            totalSharesBeingWithdrawn(owner) + shares <= balanceOf(owner),
            "MORE_THAN_BALANCE"
        );

        uint256 unlockEpoch = currentEpoch + withdrawEpochsTimelock();
        withdrawRequests[owner][unlockEpoch] += shares;

        emit WithdrawRequested(
            sender,
            owner,
            shares,
            currentEpoch,
            unlockEpoch
        );
    }

    function cancelWithdrawRequest(
        uint256 shares,
        address owner,
        uint256 unlockEpoch
    ) external {
        require(
            shares <= withdrawRequests[owner][unlockEpoch],
            "MORE_THAN_WITHDRAW_AMOUNT"
        );

        address sender = _msgSender();
        uint256 allowance = allowance(owner, sender);
        require(
            sender == owner || (allowance > 0 && allowance >= shares),
            "NOT_ALLOWED"
        );

        withdrawRequests[owner][unlockEpoch] -= shares;

        emit WithdrawCanceled(sender, owner, shares, currentEpoch, unlockEpoch);
    }

    // Locked and discounted deposits
    function depositWithDiscountAndLock(
        uint256 assets,
        uint256 lockDuration,
        address receiver
    ) external checks(assets) validDiscount(lockDuration) returns (uint256) {
        uint256 simulatedAssets = (assets *
            (PRECISION *
                100 +
                lockDiscountP(collateralizationP(), lockDuration))) /
            (PRECISION * 100);

        require(
            simulatedAssets <= maxDeposit(receiver),
            "DEPOSIT_MORE_THAN_MAX"
        );

        return
            _executeDiscountAndLock(
                simulatedAssets,
                assets,
                previewDeposit(simulatedAssets),
                lockDuration,
                receiver
            );
    }

    function mintWithDiscountAndLock(
        uint256 shares,
        uint256 lockDuration,
        address receiver
    ) external checks(shares) validDiscount(lockDuration) returns (uint256) {
        require(shares <= maxMint(receiver), "MINT_MORE_THAN_MAX");
        uint256 assets = previewMint(shares);

        return
            _executeDiscountAndLock(
                assets,
                (assets * (PRECISION * 100)) /
                    (PRECISION *
                        100 +
                        lockDiscountP(collateralizationP(), lockDuration)),
                shares,
                lockDuration,
                receiver
            );
    }

    function _executeDiscountAndLock(
        uint256 assets,
        uint256 assetsDeposited,
        uint256 shares,
        uint256 lockDuration,
        address receiver
    ) private returns (uint256) {
        require(assets > assetsDeposited, "NO_DISCOUNT");

        uint256 depositId = ++lockedDepositsCount;
        uint256 assetsDiscount = assets - assetsDeposited;

        LockedDeposit storage d = lockedDeposits[depositId];
        d.owner = receiver;
        d.shares = shares;
        d.assetsDeposited = assetsDeposited;
        d.assetsDiscount = assetsDiscount;
        d.atTimestamp = block.timestamp;
        d.lockDuration = lockDuration;

        scaleVariables(shares, assetsDeposited, true);
        address sender = _msgSender();
        _deposit(sender, address(this), assetsDeposited, shares);

        totalDiscounts += assetsDiscount;
        totalLockedDiscounts += assetsDiscount;

        lockedDepositNft.mint(receiver, depositId);

        emit DepositLocked(sender, d.owner, depositId, d);
        return depositId;
    }

    function unlockDeposit(uint256 depositId, address receiver) external {
        LockedDeposit storage d = lockedDeposits[depositId];

        address sender = _msgSender();
        address owner = lockedDepositNft.ownerOf(depositId);

        require(
            owner == sender ||
                (address(lockedDepositNft) != address(0) &&
                    (lockedDepositNft.getApproved(depositId) == sender ||
                        lockedDepositNft.isApprovedForAll(owner, sender))),
            "NOT_ALLOWED"
        );
        require(
            block.timestamp >= d.atTimestamp + d.lockDuration,
            "NOT_UNLOCKED"
        );

        int256 accPnlDelta = int256(
            d.assetsDiscount.mulDiv(
                PRECISION,
                totalSupply(),
                MathUpgradeable.Rounding.Up
            )
        );

        accPnlPerToken += accPnlDelta;
        require(
            accPnlPerToken <= int256(maxAccPnlPerToken()),
            "NOT_ENOUGH_ASSETS"
        );

        lockedDepositNft.burn(depositId);

        accPnlPerTokenUsed += accPnlDelta;
        updateShareToAssetsPrice();

        totalLiability += int256(d.assetsDiscount);
        totalLockedDiscounts -= d.assetsDiscount;

        _transfer(address(this), receiver, d.shares);

        emit DepositUnlocked(sender, receiver, owner, depositId, d);
    }

    // Distributes a reward evenly to all stakers of the vault
    function distributeReward(uint256 assets) external {
        address sender = _msgSender();
        SafeERC20Upgradeable.safeTransferFrom(
            _assetIERC20(),
            sender,
            address(this),
            assets
        );

        accRewardsPerToken += (assets * PRECISION) / totalSupply();
        updateShareToAssetsPrice();

        totalRewards += assets;
        emit RewardDistributed(sender, assets);
    }

    // PnL interactions (happens often, so also used to trigger other actions)
    function sendAssets(uint256 assets, address receiver) external {
        address sender = _msgSender();
        require(sender == pnlHandler, "ONLY_TRADING_PNL_HANDLER");

        int256 accPnlDelta = int256(
            assets.mulDiv(PRECISION, totalSupply(), MathUpgradeable.Rounding.Up)
        );

        accPnlPerToken += accPnlDelta;
        require(
            accPnlPerToken <= int256(maxAccPnlPerToken()),
            "NOT_ENOUGH_ASSETS"
        );

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta += accPnlDelta;
        require(
            dailyAccPnlDelta <= int256(maxDailyAccPnlDelta),
            "MAX_DAILY_PNL"
        );

        totalLiability += int256(assets);
        totalClosedPnl += int256(assets);

        tryNewOpenPnlRequestOrEpoch();
        tryUpdateCurrentMaxSupply();

        SafeERC20Upgradeable.safeTransfer(_assetIERC20(), receiver, assets);

        emit AssetsSent(sender, receiver, assets);
    }

    function receiveAssets(uint256 assets, address user) external {
        address sender = _msgSender();
        SafeERC20Upgradeable.safeTransferFrom(
            _assetIERC20(),
            sender,
            address(this),
            assets
        );

        uint256 assetsLessDeplete = assets;

        if (accPnlPerTokenUsed < 0 && accPnlPerToken < 0) {
            uint256 depleteAmount = (assets * lossesBurnP) / PRECISION / 100;
            assetsToDeplete += depleteAmount;
            assetsLessDeplete -= depleteAmount;
        }

        int256 accPnlDelta = int256(
            (assetsLessDeplete * PRECISION) / totalSupply()
        );
        accPnlPerToken -= accPnlDelta;

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta -= accPnlDelta;

        totalLiability -= int256(assetsLessDeplete);
        totalClosedPnl -= int256(assetsLessDeplete);

        tryNewOpenPnlRequestOrEpoch();
        tryUpdateCurrentMaxSupply();

        emit AssetsReceived(sender, user, assets, assetsLessDeplete);
    }

    // MMT mint / burn mechanism
    function deplete(uint256 assets) external {
        require(assets <= assetsToDeplete, "AMOUNT_TOO_BIG");
        assetsToDeplete -= assets;

        uint256 amountMmt = assets.mulDiv(
            MMT_PRECISION,
            mttTokenToAssetsPrice(),
            MathUpgradeable.Rounding.Up
        );

        address sender = _msgSender();
        IMmtToken(mttToken).burn(sender, amountMmt);

        totalDepleted += assets;
        totalDepletedMmt += amountMmt;

        SafeERC20Upgradeable.safeTransfer(_assetIERC20(), sender, assets);

        emit Depleted(sender, assets, amountMmt);
    }

    function refill(uint256 assets) external {
        require(accPnlPerTokenUsed > 0, "NOT_UNDER_COLLATERALIZED");

        uint256 supply = totalSupply();
        require(
            assets <= (uint256(accPnlPerTokenUsed) * supply) / PRECISION,
            "AMOUNT_TOO_BIG"
        );

        if (block.timestamp - lastDailyMintedMmtReset >= 24 hours) {
            dailyMintedMmt = 0;
            lastDailyMintedMmtReset = block.timestamp;
        }

        uint256 amountMmt = (assets * MMT_PRECISION) / mttTokenToAssetsPrice();
        dailyMintedMmt += amountMmt;

        require(
            dailyMintedMmt <=
                (maxMmtSupplyMintDailyP *
                    IERC20Upgradeable(mttToken).totalSupply()) /
                    PRECISION /
                    100,
            "ABOVE_INFLATION_LIMIT"
        );

        address sender = _msgSender();
        SafeERC20Upgradeable.safeTransferFrom(
            _assetIERC20(),
            sender,
            address(this),
            assets
        );

        int256 accPnlDelta = int256((assets * PRECISION) / supply);
        accPnlPerToken -= accPnlDelta;
        accPnlPerTokenUsed -= accPnlDelta;
        updateShareToAssetsPrice();

        totalRefilled += assets;
        totalRefilledMmt += amountMmt;

        IMmtToken(mttToken).mint(sender, amountMmt);

        emit Refilled(sender, assets, amountMmt);
    }

    // Updates shareToAssetsPrice based on the new PnL and starts a new epoch
    function updateAccPnlPerTokenUsed(
        uint256 prevPositiveOpenPnl, // 1e18
        uint256 newPositiveOpenPnl // 1e18
    ) external returns (uint256) {
        address sender = _msgSender();
        require(sender == address(openTradesPnlFeed), "ONLY_PNL_FEED");

        int256 delta = int256(newPositiveOpenPnl) - int256(prevPositiveOpenPnl); // 1e18
        uint256 supply = totalSupply();

        int256 maxDelta = int256(
            MathUpgradeable.min(
                (uint256(int256(maxAccPnlPerToken()) - accPnlPerToken) *
                    supply) / PRECISION,
                (maxAccOpenPnlDelta * supply) / PRECISION
            )
        ); // 1e18

        delta = delta > maxDelta ? maxDelta : delta;

        accPnlPerToken += (delta * int256(PRECISION)) / int256(supply);
        totalLiability += delta;

        accPnlPerTokenUsed = accPnlPerToken;
        updateShareToAssetsPrice();

        currentEpoch++;
        currentEpochStart = block.timestamp;
        currentEpochPositiveOpenPnl = uint256(
            int256(prevPositiveOpenPnl) + delta
        );

        tryUpdateCurrentMaxSupply();

        emit AccPnlPerTokenUsedUpdated(
            sender,
            currentEpoch,
            prevPositiveOpenPnl,
            newPositiveOpenPnl,
            currentEpochPositiveOpenPnl,
            accPnlPerTokenUsed
        );

        return currentEpochPositiveOpenPnl;
    }

    // Getters
    function getLockedDeposit(uint256 depositId)
        external
        view
        returns (LockedDeposit memory)
    {
        return lockedDeposits[depositId];
    }

    function tvl() public view returns (uint256) {
        // 1e18
        return (maxAccPnlPerToken() * totalSupply()) / PRECISION;
    }

    function availableAssets() public view returns (uint256) {
        // 1e18
        return
            (uint256(int256(maxAccPnlPerToken()) - accPnlPerTokenUsed) *
                totalSupply()) / PRECISION;
    }

    // To be compatible with old pairs storage contract v6 (to be used only with gDAI vault)
    function currentBalanceDai() external view returns (uint256) {
        // 1e18
        return availableAssets();
    }
}

