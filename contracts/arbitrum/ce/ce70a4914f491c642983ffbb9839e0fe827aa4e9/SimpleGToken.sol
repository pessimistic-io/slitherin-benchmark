// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20Upgradeable.sol";
import "./ERC4626Upgradeable.sol";
import "./MathUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./ISimpleGToken.sol";
import "./IOpenTradesPnlFeed.sol";
import "./ITreasury.sol";

import "./IStableCoinDecimals.sol";

import "./GambitErrorsV1.sol";

abstract contract SimpleGToken is
    ERC20Upgradeable,
    ERC4626Upgradeable,
    OwnableUpgradeable,
    ISimpleGToken,
    IStableCoinDecimals
{
    using MathUpgradeable for uint;

    bytes32[56] private _gap0; // storage slot gap (6 slots for ERC20Upgradeable, 1 slot for ERC4626Upgradeable, 1 slot for OwnableUpgradeable)

    // Contracts & Addresses (adjustable)
    address public manager; // 3-day timelock contract
    address public gov; // bypasses timelock, access to emergency functions

    address public pnlHandler; // callbacks contract
    IOpenTradesPnlFeed public openTradesPnlFeed; // GTokenOpenPnlFeed contract
    ITreasury public treasury;

    bytes32[59] private _gap1; // storage slot gap (5 slots for above variables)

    // Parameters (constant)
    uint constant PRECISION = 1e10;
    uint constant MAX_OPEN_PNL_DEBT_P = PRECISION * 90; // PRECISION (90%)

    uint[] WITHDRAW_EPOCHS_LOCKS; // epochs withdraw locks at over collat thresholds

    bytes32[63] private _gap2; // storage slot gap (1 slot for above variable)

    // Parameters (adjustable)
    uint public maxDailyAccPnlDelta; // 1e6 (USDC) or 1e18 (DAI) (max daily price delta from closed pnl)
    uint[2] public withdrawLockThresholdsP; // PRECISION (% of over collat, used with WITHDRAW_EPOCHS_LOCKS)

    bytes32[61] private _gap3; // storage slot gap (3 slots for above variables)

    // Treasury state
    uint public treasuryDebt; // 1e6 (USDC) or 1e18 (DAI) (assets that treasury owes to vault)

    bytes32[63] private _gap4; // storage slot gap (1 slot for above variable)

    // Price state
    uint public shareToAssetsPrice; // 1e24 (USDC) or 1e36 (DAI)

    bytes32[63] private _gap5; // storage slot gap (1 slot for above variable)

    // Closed Pnl state
    int public dailyAccPnlDelta; // 1e6 (USDC) or 1e18 (DAI)
    uint public lastDailyAccPnlDeltaReset; // timestamp

    bytes32[62] private _gap6; // storage slot gap (2 slots for above variables)

    // Epochs state (withdrawals)
    uint public currentEpoch; // global id
    uint public currentEpochStart; // timestamp
    uint public currentEpochPositiveOpenPnl; // 1e6 (USDC) or 1e18 (DAI)

    bytes32[61] private _gap7; // storage slot gap (3 slots for above variables)

    // Deposit / Withdraw state
    mapping(address => mapping(uint => uint)) public withdrawRequests; // owner => unlock epoch => shares

    bytes32[63] private _gap8; // storage slot gap (1 slot for above variable)

    // Open PnL state & parameter
    uint public openPnlDebt; // 1e6 (USDC) or 1e18 (DAI)
    uint public maxOpenPnlDebtP; // PRECISION (% of assets)

    bytes32[62] private _gap9; // storage slot gap (2 slots for above variables)

    // Statistics (not used for contract logic)
    uint public totalDeposited; // 1e6 (USDC) or 1e18 (DAI) (assets)
    uint public totalWithdrawn; // 1e6 (USDC) or 1e18 (DAI) (assets)
    int public totalClosedPnl; // 1e6 (USDC) or 1e18 (DAI) (assets)
    uint public totalRewards; // 1e6 (USDC) or 1e18 (DAI) (assets)
    int public totalLiability; // 1e6 (USDC) or 1e18 (DAI) (assets)

    bytes32[59] private _gap10; // storage slot gap (5 slots for above variables)

    // Events
    event AddressParamUpdated(string name, address indexed newValue);
    event NumberParamUpdated(string name, uint newValue);
    event WithdrawLockThresholdsPUpdated(uint[2] newValue);

    event DailyAccPnlDeltaReset();
    event ShareToAssetsPriceUpdated(uint newValue);
    event OpenTradesPnlFeedCallFailed();

    event WithdrawRequested(
        address indexed sender,
        address indexed owner,
        uint shares,
        uint currEpoch,
        uint indexed unlockEpoch
    );
    event WithdrawCanceled(
        address indexed sender,
        address indexed owner,
        uint shares,
        uint currEpoch,
        uint indexed unlockEpoch
    );

    event RewardDistributed(address indexed sender, uint assets);

    event AssetsSent(
        address indexed sender,
        address indexed receiver,
        uint assets
    );
    event AssetsReceived(
        address indexed sender,
        address indexed user,
        uint assets
    );

    event AccPnlPerTokenUsedUpdated(
        address indexed sender,
        uint indexed newEpoch,
        uint prevPositiveOpenPnl, // 1e6 (USDC) or 1e18 (DAI)
        uint newPositiveOpenPnl, // 1e6 (USDC) or 1e18 (DAI)
        uint newEpochPositiveOpenPnl // 1e6 (USDC) or 1e18 (DAI)
    );

    // Prevent stack too deep error
    struct ContractAddresses {
        address asset;
        address owner; // 2-week timelock contract
        address manager; // 3-day timelock contract
        address gov; // bypasses timelock, access to emergency functions
        address pnlHandler; // callbacks contract
        address openTradesPnlFeed; // GTokenOpenPnlFeed contract
        address treasury;
    }

    constructor() {
        _disableInitializers();
    }

    // Initializer function called when this contract is deployed
    function initialize(
        string calldata _name,
        string calldata _symbol,
        ContractAddresses calldata _contractAddresses,
        uint _maxDailyAccPnlDelta,
        uint _maxOpenPnlDebtP,
        uint[2] calldata _withdrawLockThresholdsP
    ) external initializer {
        // init base contracts before use MIN_DAILY_ACC_PNL_DELTA()
        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20MetadataUpgradeable(_contractAddresses.asset));

        if (
            _contractAddresses.asset == address(0) ||
            _contractAddresses.owner == address(0) ||
            _contractAddresses.manager == address(0) ||
            _contractAddresses.gov == address(0) ||
            _contractAddresses.owner == _contractAddresses.manager ||
            _contractAddresses.manager == _contractAddresses.gov ||
            _contractAddresses.pnlHandler == address(0) ||
            _contractAddresses.openTradesPnlFeed == address(0) ||
            _contractAddresses.treasury == address(0) ||
            _maxDailyAccPnlDelta < MIN_DAILY_ACC_PNL_DELTA() ||
            _maxOpenPnlDebtP >= MAX_OPEN_PNL_DEBT_P ||
            _withdrawLockThresholdsP[1] <= _withdrawLockThresholdsP[0]
        ) revert GambitErrorsV1.WrongParams();

        if (
            IERC20MetadataUpgradeable(_contractAddresses.asset).decimals() !=
            usdcDecimals()
        ) revert GambitErrorsV1.StablecoinDecimalsMismatch();

        _transferOwnership(_contractAddresses.owner);

        manager = _contractAddresses.manager;
        gov = _contractAddresses.gov;
        pnlHandler = _contractAddresses.pnlHandler;
        openTradesPnlFeed = IOpenTradesPnlFeed(
            _contractAddresses.openTradesPnlFeed
        );
        treasury = ITreasury(_contractAddresses.treasury);

        maxDailyAccPnlDelta = _maxDailyAccPnlDelta;
        maxOpenPnlDebtP = _maxOpenPnlDebtP;
        withdrawLockThresholdsP = _withdrawLockThresholdsP;

        shareToAssetsPrice = 10 ** shareToAssetsPriceDecimals(); // 1e24 (USDC) or 1e36 (DAI)
        currentEpoch = 1;
        currentEpochStart = block.timestamp;
        WITHDRAW_EPOCHS_LOCKS = [3, 2, 1];
    }

    // Modifiers
    modifier onlyManager() {
        if (_msgSender() != manager) revert GambitErrorsV1.NotManager();
        _;
    }

    modifier checks(uint assetsOrShares) {
        if (shareToAssetsPrice == 0) revert GambitErrorsV1.ZeroPrice();
        if (assetsOrShares == 0) revert GambitErrorsV1.ZeroValue();
        _;
    }

    // Manage addresses
    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == address(0)) revert GambitErrorsV1.ZeroAddress();
        if (newOwner == manager || newOwner == gov)
            revert GambitErrorsV1.WrongParams();
        _transferOwnership(newOwner);
    }

    function updateManager(address newValue) external onlyOwner {
        if (newValue == address(0)) revert GambitErrorsV1.ZeroAdress();
        if (newValue == owner() || newValue == gov)
            revert GambitErrorsV1.WrongParams();
        manager = newValue;
        emit AddressParamUpdated("manager", newValue);
    }

    function updateAdmin(address newValue) external onlyManager {
        if (newValue == address(0)) revert GambitErrorsV1.ZeroAdress();
        if (newValue == owner() || newValue == manager)
            revert GambitErrorsV1.WrongParams();
        gov = newValue;
        emit AddressParamUpdated("gov", newValue);
    }

    function updatePnlHandler(address newValue) external onlyOwner {
        if (newValue == address(0)) revert GambitErrorsV1.ZeroAdress();
        pnlHandler = newValue;
        emit AddressParamUpdated("pnlHandler", newValue);
    }

    function updateOpenTradesPnlFeed(address newValue) external onlyOwner {
        if (newValue == address(0)) revert GambitErrorsV1.ZeroAdress();
        openTradesPnlFeed = IOpenTradesPnlFeed(newValue);
        emit AddressParamUpdated("openTradesPnlFeed", newValue);
    }

    // Manage parameters
    function updateMaxDailyAccPnlDelta(
        uint newValue // 1e6 (USDC) or 1e18 (DAI)
    ) external onlyManager {
        if (newValue < MIN_DAILY_ACC_PNL_DELTA())
            revert GambitErrorsV1.TooLow();
        maxDailyAccPnlDelta = newValue;
        emit NumberParamUpdated("maxDailyAccPnlDelta", newValue);
    }

    function updateMaxOpenPnlDebtP(uint newValue) external onlyManager {
        if (newValue >= MAX_OPEN_PNL_DEBT_P) revert GambitErrorsV1.TooHigh();
        maxOpenPnlDebtP = newValue;
        emit NumberParamUpdated("maxOpenPnlDebtP", newValue);
    }

    function updateWithdrawLockThresholdsP(
        uint[2] calldata newValue
    ) external onlyOwner {
        if (newValue[1] <= newValue[0]) revert GambitErrorsV1.WrongOrder();
        withdrawLockThresholdsP = newValue;
        emit WithdrawLockThresholdsPUpdated(newValue);
    }

    // View helper functions

    function collateralizationP() public view returns (uint) {
        uint vb = totalAssets(); // vault balance
        uint tb = currentTreasuryBalanceUsdc(); // treasury balance
        uint td = treasuryDebt; // treasury debt
        uint od = openPnlDebt; // open pnl debt

        // numerator = vault balance + treasury balance - treasury debt - open pnl debt
        uint n = (vb + tb) > (td + od) ? vb + tb - (td + od) : 0;
        // denominator = vault balance
        uint d = vb;

        if (n == 0 || d == 0) return 0;

        // PRECISION (%)
        return (100 * PRECISION).mulDiv(n, d);
    }

    function withdrawEpochsTimelock() public view returns (uint) {
        uint collatP = collateralizationP();
        uint overCollatP = (collatP -
            MathUpgradeable.min(collatP, 100 * PRECISION));

        return
            overCollatP > withdrawLockThresholdsP[1]
                ? WITHDRAW_EPOCHS_LOCKS[2]
                : overCollatP > withdrawLockThresholdsP[0]
                ? WITHDRAW_EPOCHS_LOCKS[1]
                : WITHDRAW_EPOCHS_LOCKS[0];
    }

    function totalSharesBeingWithdrawn(
        address owner
    ) public view returns (uint shares) {
        for (
            uint i = currentEpoch;
            i <= currentEpoch + WITHDRAW_EPOCHS_LOCKS[0];
            i++
        ) {
            shares += withdrawRequests[owner][i];
        }
    }

    // Public helper functions
    function tryResetDailyAccPnlDelta() public {
        if (block.timestamp - lastDailyAccPnlDeltaReset >= 24 hours) {
            dailyAccPnlDelta = 0;
            lastDailyAccPnlDeltaReset = block.timestamp;

            emit DailyAccPnlDeltaReset();
        }
    }

    function tryNewOpenPnlRequest() public {
        // Fault tolerance so that activity can continue anyway
        (bool success, ) = address(openTradesPnlFeed).call(
            abi.encodeWithSignature("newOpenPnlRequest()")
        );
        if (!success) {
            emit OpenTradesPnlFeedCallFailed();
        }
    }

    function updateShareToAssetsPrice(
        int assets, // 1e6 (USDC) or 1e18 (DAI)
        uint supply // 1e6 (USDC) or 1e18 (DAI)
    ) private {
        // 1e24 (USDC) or 1e36 (DAI)
        uint priceDeltaAbs = uint(10 ** shareToAssetsPriceDecimals()).mulDiv(
            assets > 0 ? uint(assets) : uint(-assets),
            supply
        );

        if (assets > 0) shareToAssetsPrice += priceDeltaAbs;
        else shareToAssetsPrice -= priceDeltaAbs;

        emit ShareToAssetsPriceUpdated(shareToAssetsPrice);
    }

    // Private helper functions

    function _assetIERC20() private view returns (IERC20Upgradeable) {
        return IERC20Upgradeable(asset());
    }

    // Override ERC-20 functions (prevent sending to address that is withdrawing)
    function transfer(
        address to,
        uint amount
    ) public override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        address sender = _msgSender();
        if (totalSharesBeingWithdrawn(sender) > balanceOf(sender) - amount)
            revert GambitErrorsV1.PendingWithdrawal();
        _transfer(sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint amount
    ) public override(ERC20Upgradeable, IERC20Upgradeable) returns (bool) {
        if (totalSharesBeingWithdrawn(from) > balanceOf(from) - amount)
            revert GambitErrorsV1.PendingWithdrawal();

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

    function _convertToShares(
        uint assets,
        MathUpgradeable.Rounding rounding
    )
        internal
        view
        override
        returns (
            uint shares // 1e6 (USDC) or 1e18 (DAI)
        )
    {
        return
            assets.mulDiv(
                (10 ** shareToAssetsPriceDecimals()),
                shareToAssetsPrice,
                rounding
            );
    }

    function _convertToAssets(
        uint shares,
        MathUpgradeable.Rounding rounding
    ) internal view override returns (uint assets) {
        // Prevent overflow when called from maxDeposit with maxMint = uint.max
        if (
            shares == type(uint).max &&
            shareToAssetsPrice >= (10 ** shareToAssetsPriceDecimals())
        ) {
            return shares;
        }
        return
            shares.mulDiv(
                shareToAssetsPrice,
                (10 ** shareToAssetsPriceDecimals()),
                rounding
            );
    }

    function maxRedeem(address owner) public view override returns (uint) {
        return
            !openTradesPnlFeed.isCalculating()
                ? MathUpgradeable.min(
                    withdrawRequests[owner][currentEpoch],
                    totalSupply() - 1
                )
                : 0;
    }

    function maxWithdraw(address owner) public view override returns (uint) {
        return
            _convertToAssets(maxRedeem(owner), MathUpgradeable.Rounding.Down);
    }

    // Override ERC-4626 interactions
    function deposit(
        uint assets,
        address receiver
    ) public override checks(assets) returns (uint) {
        uint shares = super.deposit(assets, receiver);
        if (shares == 0) revert GambitErrorsV1.ZeroValue();
        return shares;
    }

    function mint(
        uint256 shares,
        address receiver
    ) public override checks(shares) returns (uint) {
        uint assets = super.mint(shares, receiver);
        if (assets == 0) revert GambitErrorsV1.ZeroValue();
        return assets;
    }

    function withdraw(
        uint assets,
        address receiver,
        address owner
    ) public override checks(assets) returns (uint) {
        if (assets > maxWithdraw(owner)) revert GambitErrorsV1.TooHigh();

        uint shares = previewWithdraw(assets);
        withdrawRequests[owner][currentEpoch] -= shares;

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    function redeem(
        uint shares,
        address receiver,
        address owner
    ) public override checks(shares) returns (uint) {
        if (shares > maxRedeem(owner)) revert GambitErrorsV1.TooHigh();

        withdrawRequests[owner][currentEpoch] -= shares;

        uint assets = previewRedeem(shares);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    // Withdraw requests (need to be done before calling 'withdraw' / 'redeem')
    function makeWithdrawRequest(uint shares, address owner) external {
        if (openTradesPnlFeed.isCalculating())
            revert GambitErrorsV1.EndOfEpoch();

        address sender = _msgSender();
        uint allowance = allowance(owner, sender);
        if (sender != owner && (allowance == 0 || allowance < shares))
            revert GambitErrorsV1.NotAllowed();

        if (totalSharesBeingWithdrawn(owner) + shares > balanceOf(owner))
            revert GambitErrorsV1.TooHigh();

        uint unlockEpoch = currentEpoch + withdrawEpochsTimelock();
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
        uint shares,
        address owner,
        uint unlockEpoch
    ) external {
        if (shares > withdrawRequests[owner][unlockEpoch])
            revert GambitErrorsV1.TooHigh();

        address sender = _msgSender();
        uint allowance = allowance(owner, sender);
        if (sender != owner && (allowance == 0 || allowance < shares))
            revert GambitErrorsV1.NotAllowed();

        withdrawRequests[owner][unlockEpoch] -= shares;

        emit WithdrawCanceled(sender, owner, shares, currentEpoch, unlockEpoch);
    }

    // Distributes a reward evenly to all stakers of the vault
    function distributeReward(uint assets) external {
        address sender = _msgSender();

        updateShareToAssetsPrice(int(assets), totalSupply());

        totalRewards += assets;

        SafeERC20Upgradeable.safeTransferFrom(
            _assetIERC20(),
            sender,
            address(this),
            assets
        );
        emit RewardDistributed(sender, assets);
    }

    // PnL interactions (happens often, so also used to trigger other actions)
    function sendAssets(uint assets, address receiver) external {
        address sender = _msgSender();
        if (sender != pnlHandler) revert GambitErrorsV1.NotTradingPnlHandler();

        // Send USDC from Treasury. If Treasury does not have enough USDC,
        // send USDC from Vault and fill Vault with USDC that Treasury will receive later.
        uint treasuryBalance = currentTreasuryBalanceUsdc();
        uint assetsFromVault = assets > treasuryBalance
            ? assets - treasuryBalance
            : 0;
        uint assetsFromTreasury = assets - assetsFromVault;

        uint supply = totalSupply();
        int accPnlDelta = int(
            assets.mulDiv(
                (10 ** usdcDecimals()),
                supply,
                MathUpgradeable.Rounding.Up
            )
        );

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta += accPnlDelta;
        if (dailyAccPnlDelta > int(maxDailyAccPnlDelta))
            revert GambitErrorsV1.MaxDailyPnl();

        totalLiability += int(assets);
        totalClosedPnl += int(assets);

        tryNewOpenPnlRequest();

        if (assetsFromVault > 0) {
            treasuryDebt += assetsFromVault;
            updateShareToAssetsPrice(-int(assetsFromVault), supply);

            SafeERC20Upgradeable.safeTransfer(
                _assetIERC20(),
                receiver,
                assetsFromVault
            );
        }
        if (assetsFromTreasury > 0) {
            treasury.transfer(
                address(_assetIERC20()),
                receiver,
                assetsFromTreasury
            );
        }

        emit AssetsSent(sender, receiver, assets);
    }

    function receiveAssets(uint assets, address user) external {
        address sender = _msgSender();

        // Send USDC from Treasury if Treasury does not have any debt.
        uint assetsToVault = treasuryDebt > 0
            ? MathUpgradeable.min(treasuryDebt, assets)
            : 0;
        uint assetsToTreasury = assets - assetsToVault;

        uint supply = totalSupply();
        int accPnlDelta = int(assets.mulDiv((10 ** usdcDecimals()), supply));

        if (assetsToVault > 0) {
            treasuryDebt -= assetsToVault;
            updateShareToAssetsPrice(int(assetsToVault), supply);
            SafeERC20Upgradeable.safeTransferFrom(
                _assetIERC20(),
                sender,
                address(this),
                assetsToVault
            );
        }
        if (assetsToTreasury > 0) {
            SafeERC20Upgradeable.safeTransferFrom(
                _assetIERC20(),
                sender,
                address(treasury),
                assetsToTreasury
            );
        }

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta -= accPnlDelta;

        totalLiability -= int(assets);
        totalClosedPnl -= int(assets);

        tryNewOpenPnlRequest();

        emit AssetsReceived(sender, user, assets);
    }

    // Updates shareToAssetsPrice based on the new PnL and starts a new epoch
    function updateAccPnlPerTokenUsed(
        uint prevPositiveOpenPnl, // 1e6 (USDC) or 1e18 (DAI)
        uint newPositiveOpenPnl // 1e6 (USDC) or 1e18 (DAI)
    ) external returns (uint) {
        address sender = _msgSender();
        if (sender != address(openTradesPnlFeed))
            revert GambitErrorsV1.NotPnlFeed();

        uint supply = totalSupply();

        uint ta = currentTreasuryAvailable();

        uint newOpenPnlDebt = newPositiveOpenPnl < ta
            ? 0 // treasury can pay all positive openp nl for vault
            : newPositiveOpenPnl - ta; // vault should pay remainings

        // newOpenPnlDebt is bounded up to 50% of vault balance
        newOpenPnlDebt = MathUpgradeable.min(
            newOpenPnlDebt,
            getMaxOpenPnlDebt()
        );

        int delta = int(newOpenPnlDebt) - int(openPnlDebt); // 1e6 (USDC) or 1e18 (DAI)

        updateShareToAssetsPrice(-delta, supply);

        openPnlDebt = newOpenPnlDebt;
        totalLiability += delta;

        currentEpoch += 1;
        currentEpochStart = block.timestamp;
        currentEpochPositiveOpenPnl = uint(int(prevPositiveOpenPnl) + delta);

        emit AccPnlPerTokenUsedUpdated(
            sender,
            currentEpoch,
            prevPositiveOpenPnl,
            newPositiveOpenPnl,
            currentEpochPositiveOpenPnl
        );

        return currentEpochPositiveOpenPnl;
    }

    function getMaxOpenPnlDebt() public view returns (uint256) {
        return ((totalAssets() * maxOpenPnlDebtP) / PRECISION) / 100; // 50% of assets
    }

    // Getters
    function currentTreasuryAvailable() public view returns (uint ta) {
        uint td = treasuryDebt;
        uint tb = currentTreasuryBalanceUsdc();
        ta = tb > td ? tb - td : 0;
    }

    function currentTreasuryBalanceUsdc() public view returns (uint) {
        return _assetIERC20().balanceOf(address(treasury));
    }

    function currentBalanceUsdc() external view returns (uint) {
        // 1e6 (USDC) or 1e18 (DAI)
        return currentTreasuryBalanceUsdc() + totalAssets();
    }

    function usdcDecimals()
        public
        pure
        virtual
        returns (
            uint8 // 6 (USDC) or 18 (DAI)
        );

    function shareToAssetsPriceDecimals()
        public
        pure
        returns (
            uint8 // 24 (USDC) or 36 (DAI)
        )
    {
        return usdcDecimals() + 18;
    }

    function MIN_DAILY_ACC_PNL_DELTA()
        public
        pure
        returns (
            uint // 1e6 (USDC) or 1e18 (DAI)
        )
    {
        return ((10 ** usdcDecimals()) / 10) * 1; // 0.1 USDC or 0.1 DAI (price delta)
    }
}

/**
 * @dev SimpleGToken with stablecoin decimals set to 6.
 */
contract SimpleGToken____6 is SimpleGToken {
    function usdcDecimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @dev SimpleGToken with stablecoin decimals set to 18.
 */
contract SimpleGToken____18 is SimpleGToken {
    function usdcDecimals() public pure override returns (uint8) {
        return 18;
    }
}

