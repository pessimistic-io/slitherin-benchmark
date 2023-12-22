// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./ERC4626.sol";
import "./Pausable.sol";
import "./Math.sol";
import "./IMainPool.sol";
import "./IWorkPool.sol";
import "./IOpenPnlFeed.sol";
import "./ITradingStorage.sol";
import "./ChainUtils.sol";


contract WorkPool is ERC20, ERC4626, Pausable, IWorkPool {
    using Math for uint256;

    uint256 constant PRECISION = 1e18; // 18 decimals (acc values & price)
    uint256 constant PRECISION_2 = 1e40; // 40 decimals (acc block weighted market cap)
    uint256 constant MIN_DAILY_ACC_PNL_DELTA = PRECISION / 10; // 0.1 (price delta)
    uint256[] WITHDRAW_EPOCHS_LOCKS; // epochs withdraw locks at over collat thresholds

    address public mainPool;
    address public pnlHandler;
    IOpenPnlFeed public openTradesPnlFeed;
    address public storageT;

    uint256 public maxAccOpenPnlDelta; // PRECISION (max price delta on new epochs from open pnl)
    uint256 public maxDailyAccPnlDelta; // PRECISION (max daily price delta from closed pnl)
    uint256[2] public withdrawLockThresholdsP; // PRECISION (% of over collat, used with WITHDRAW_EPOCHS_LOCKS)

    uint256 public shareToAssetsPrice; // PRECISION
    int256 public accPnlPerTokenUsed; // PRECISION (snapshot of accPnlPerToken)
    int256 public accPnlPerToken; // PRECISION (updated in real-time)
    uint256 public accRewardsPerToken; // PRECISION

    int256 public dailyAccPnlDelta; // PRECISION
    uint256 public lastDailyAccPnlDeltaReset; // timestamp

    uint256 public currentEpoch; // global id
    uint256 public currentEpochStart; // timestamp
    uint256 public currentEpochPositiveOpenPnl; 

    uint256 public totalDeposited; 
    int256 public totalClosedPnl; 
    uint256 public totalRewards; 
    int256 public totalLiability; 
    uint256 public totalDepleted; 
    uint256 public totalRefilled; 

    uint256 public accBlockWeightedMarketCap; // 1e40, acc sum of (blocks elapsed / market cap)
    uint256 public accBlockWeightedMarketCapLastStored; // block

   
    event AddressParamUpdated(string name, address newValue);
    event NumberParamUpdated(string name, uint256 newValue);
    event WithdrawLockThresholdsPUpdated(uint256[2] newValue);

    event DailyAccPnlDeltaReset();
    event ShareToAssetsPriceUpdated(uint256 newValue);
    event OpenTradesPnlFeedCallFailed();

    event RewardDistributed(address indexed sender, uint256 assets);

    event AssetsSent(address indexed sender, address indexed receiver, uint256 assets);
    event AssetsReceived(address indexed sender, address indexed user, uint256 assets);

    event Depleted(address indexed sender, uint256 assets);
    event Refilled(address indexed sender, uint256 assets);

    event AccPnlPerTokenUsedUpdated(
        address indexed sender,
        uint256 indexed newEpoch,
        uint256 prevPositiveOpenPnl,
        uint256 newPositiveOpenPnl,
        uint256 newEpochPositiveOpenPnl,
        int256 newAccPnlPerTokenUsed
    );

    event AccBlockWeightedMarketCapStored(uint256 newAccValue);

    error WorkPoolWrongParameters();
    error WorkPoolInvalidMainPoolOwnerAddress(address account);
    error WorkPoolInvalidGovAddress(address account);
    error WorkPoolInvalidMainPoolContract(address account);
    error WorkPoolInvalidPnlHandler(address account);
    error WorkPoolInvalidPnlFeed(address account);
    error WorkPoolInvalidPrice();
    error WorkPoolInvalidAssetOrShareAmount();
    error WorkPoolInvalidAddress(address account);
    error WorkPoolDepositMoreThanMax(uint256 amount);
    error WorkPoolMintMoreThanMax(uint256 amount);
    error WorkPoolWithdrawMoreThanMax(uint256 amount);
    error WorkPoolRedeemMoreThanMax(uint256 amount);
    error WorkPoolInvalidAssetAmount();
    error WorkPoolInvalidPnlDelta();
    error WorkPoolInsufficientUnderCollateralized();

    modifier onlyMainPoolOwner() {
        if (_msgSender() != mainPoolOwner()) {
            revert WorkPoolInvalidMainPoolOwnerAddress(_msgSender());
        }
        _;
    }

    modifier onlyGov() {
        if (_msgSender() != govAddress()) {
            revert WorkPoolInvalidGovAddress(_msgSender());
        }
        _;
    }

    modifier checks(uint256 assetsOrShares) {
        if (shareToAssetsPrice == 0) {
            revert WorkPoolInvalidPrice();
        }        
        if (assetsOrShares == 0) {
            revert WorkPoolInvalidAssetOrShareAmount();
        }
        _;
    }


    constructor(
        string memory _name,
        string memory _symbol,
        address _asset,
        address _storageT,
        uint256 _maxAccOpenPnlDelta,
        uint256 _maxDailyAccPnlDelta,
        uint256[2] memory _withdrawLockThresholdsP
    ) 
        ERC20(_name, _symbol)
        ERC4626(IERC20Metadata(_asset))
    {
        if (_asset == address(0) ||
            _storageT == address(0) ||
            _maxDailyAccPnlDelta < MIN_DAILY_ACC_PNL_DELTA ||
            _withdrawLockThresholdsP[1] <= _withdrawLockThresholdsP[0]) {
            revert WorkPoolWrongParameters();
        }

        storageT =_storageT;
        maxAccOpenPnlDelta = _maxAccOpenPnlDelta;
        maxDailyAccPnlDelta = _maxDailyAccPnlDelta;
        withdrawLockThresholdsP = _withdrawLockThresholdsP;

        shareToAssetsPrice = PRECISION;
        currentEpoch = 1;
        currentEpochStart = block.timestamp;
        WITHDRAW_EPOCHS_LOCKS = [3, 2, 1];

        storeAccBlockWeightedMarketCap();
        totalDeposited += totalRewards;
    }

    function updateMainPool(address newValue) external onlyGov {
        if (newValue == address(0)) {
            revert WorkPoolInvalidAddress(address(0));
        }
        mainPool = newValue;
        emit AddressParamUpdated("mainPool", newValue);
    }

    function updatePnlHandler(address newValue) external onlyMainPoolOwner {
        if (newValue == address(0)) {
            revert WorkPoolInvalidAddress(address(0));
        }
        pnlHandler = newValue;
        emit AddressParamUpdated("pnlHandler", newValue);
    }

    function updateOpenTradesPnlFeed(address newValue) external onlyMainPoolOwner {
        if (newValue == address(0)) {
            revert WorkPoolInvalidAddress(address(0));
        }
        openTradesPnlFeed = IOpenPnlFeed(newValue);
        emit AddressParamUpdated("openTradesPnlFeed", newValue);
    }

    function updateMaxAccOpenPnlDelta(uint256 newValue) external onlyMainPoolOwner {
        maxAccOpenPnlDelta = newValue;
        emit NumberParamUpdated("maxAccOpenPnlDelta", newValue);
    }

    function updateMaxDailyAccPnlDelta(uint256 newValue) external onlyMainPoolOwner {
        if (newValue < MIN_DAILY_ACC_PNL_DELTA) {
            revert WorkPoolWrongParameters();
        }
        maxDailyAccPnlDelta = newValue;
        emit NumberParamUpdated("maxDailyAccPnlDelta", newValue);
    }

    function updateWithdrawLockThresholdsP(uint256[2] memory newValue) external onlyMainPoolOwner {
        if (newValue[1] <= newValue[0]) {
            revert WorkPoolWrongParameters();
        }
        withdrawLockThresholdsP = newValue;
        emit WithdrawLockThresholdsPUpdated(newValue);
    }

    function pause() external onlyMainPoolOwner returns (bool) {
        _pause();
        return true;
    }

    function unpause() external onlyMainPoolOwner returns (bool) {
        _unpause();
        return true;
    }


    function distributeReward(uint256 assets) external whenNotPaused {
        address sender = _msgSender();
        SafeERC20.safeTransferFrom(_assetIERC20(), sender, address(this), assets);

        accRewardsPerToken += (assets * PRECISION) / totalSupply();
        updateShareToAssetsPrice();

        totalRewards += assets;
        totalDeposited += assets;

        emit RewardDistributed(sender, assets);
    }

    function sendAssets(uint256 assets, address receiver) external whenNotPaused {
        address sender = _msgSender();
        if (sender != pnlHandler) {
            revert WorkPoolInvalidPnlHandler(sender);
        }

        int256 accPnlDelta = int256(assets.mulDiv(PRECISION, totalSupply(), Math.Rounding.Up));

        accPnlPerToken += accPnlDelta;
        if (accPnlPerToken > int256(maxAccPnlPerToken())) {
            revert WorkPoolInvalidAssetAmount();
        }

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta += accPnlDelta;
        if (dailyAccPnlDelta > int256(maxDailyAccPnlDelta)) {
            revert WorkPoolInvalidPnlDelta();
        }

        totalLiability += int256(assets);
        totalClosedPnl += int256(assets);

        tryNewOpenPnlRequestOrEpoch();

        SafeERC20.safeTransfer(_assetIERC20(), receiver, assets);

        emit AssetsSent(sender, receiver, assets);
    }

    function receiveAssets(uint256 assets, address user) external whenNotPaused {
        address sender = _msgSender();
        SafeERC20.safeTransferFrom(_assetIERC20(), sender, address(this), assets);

        int256 accPnlDelta = int256((assets * PRECISION) / totalSupply());
        accPnlPerToken -= accPnlDelta;

        tryResetDailyAccPnlDelta();
        dailyAccPnlDelta -= accPnlDelta;

        totalLiability -= int256(assets);
        totalClosedPnl -= int256(assets);

        tryNewOpenPnlRequestOrEpoch();

        emit AssetsReceived(sender, user, assets);
    }

    function deplete(uint256 assets) external whenNotPaused {
        if (_msgSender() != mainPool) {
            revert WorkPoolInvalidMainPoolContract(_msgSender());
        }
        
        address sender = _msgSender();
        uint256 supply = totalSupply();

        int256 accPnlDelta = int256((assets * PRECISION) / supply);
        accPnlPerToken += accPnlDelta;
        accPnlPerTokenUsed += accPnlDelta;
        updateShareToAssetsPrice();
    
        totalDepleted += assets;

        SafeERC20.safeTransfer(_assetIERC20(), msg.sender, assets);

        emit Depleted(sender, assets);
    }

    function refill(uint256 assets) external whenNotPaused {
        if (_msgSender() != mainPool) {
            revert WorkPoolInvalidMainPoolContract(_msgSender());
        }
        if (accPnlPerTokenUsed <= 0) {
            revert WorkPoolInsufficientUnderCollateralized();
        }

        uint256 supply = totalSupply();
        address sender = _msgSender();
        SafeERC20.safeTransferFrom(_assetIERC20(), sender, address(this), assets);

        int256 accPnlDelta = int256((assets * PRECISION) / supply);
        accPnlPerToken -= accPnlDelta;
        accPnlPerTokenUsed -= accPnlDelta;
        updateShareToAssetsPrice();

        totalRefilled += assets;

        emit Refilled(sender, assets);
    }

    function updateAccPnlPerTokenUsed(
        uint256 prevPositiveOpenPnl, 
        uint256 newPositiveOpenPnl 
    ) external returns (uint256) {
        address sender = _msgSender();
        if (sender != address(openTradesPnlFeed)) {
            revert WorkPoolInvalidPnlFeed(sender);
        }

        int256 delta = int256(newPositiveOpenPnl) - int256(prevPositiveOpenPnl); 
        uint256 supply = totalSupply();

        int256 maxDelta = int256(
            Math.min(
                (uint256(int256(maxAccPnlPerToken()) - accPnlPerToken) * supply) / PRECISION,
                (maxAccOpenPnlDelta * supply) / PRECISION
            )
        ); 

        delta = delta > maxDelta ? maxDelta : delta;

        accPnlPerToken += (delta * int256(PRECISION)) / int256(supply);
        totalLiability += delta;

        accPnlPerTokenUsed = accPnlPerToken;
        updateShareToAssetsPrice();

        currentEpoch++;
        currentEpochStart = block.timestamp;
        currentEpochPositiveOpenPnl = uint256(int256(prevPositiveOpenPnl) + delta);

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

    function currentBalanceStable() external view returns (uint256) {
        return availableAssets(); 
    }

    // Override ERC-4626 interactions (call scaleVariables on every deposit / withdrawal)
    function deposit(uint256 assets, address receiver) public whenNotPaused override(ERC4626, IWorkPool) checks(assets) returns (uint256) {
        if (_msgSender() != mainPool) {
            revert WorkPoolInvalidMainPoolContract(_msgSender());
        }
        if (assets > maxDeposit(receiver)) {
            revert WorkPoolDepositMoreThanMax(assets);
        }

        uint256 shares = previewDeposit(assets);
        scaleVariables(shares, assets, true);

        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) public whenNotPaused override checks(shares) returns (uint256) {
        if (_msgSender() != mainPool) {
            revert WorkPoolInvalidMainPoolContract(_msgSender());
        }
        if (shares > maxMint(receiver)) {
            revert WorkPoolMintMoreThanMax(shares);
        }

        uint256 assets = previewMint(shares);
        scaleVariables(shares, assets, true);

        _deposit(_msgSender(), receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public override checks(assets) returns (uint256) {
        if (_msgSender() != mainPool) {
            revert WorkPoolInvalidMainPoolContract(_msgSender());
        }
        if (assets > maxWithdraw(owner)) {
            revert WorkPoolWithdrawMoreThanMax(assets);
        }

        uint256 shares = previewWithdraw(assets);

        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public override(ERC4626, IWorkPool) checks(shares) returns (uint256) {
        if (_msgSender() != mainPool) {
            revert WorkPoolInvalidMainPoolContract(_msgSender());
        }
        if (shares > maxRedeem(owner)) {
            revert WorkPoolRedeemMoreThanMax(shares);
        }

        uint256 assets = previewRedeem(shares);
        scaleVariables(shares, assets, false);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
        return assets;
    }

    function tryResetDailyAccPnlDelta() public {
        if (block.timestamp - lastDailyAccPnlDeltaReset >= 24 hours) {
            dailyAccPnlDelta = 0;
            lastDailyAccPnlDeltaReset = block.timestamp;

            emit DailyAccPnlDeltaReset();
        }
    }

    function tryNewOpenPnlRequestOrEpoch() public {
        (bool success, ) = address(openTradesPnlFeed).call(abi.encodeWithSignature("newOpenPnlRequestOrEpoch()"));
        if (!success) {
            emit OpenTradesPnlFeedCallFailed();
        }
    }

    function storeAccBlockWeightedMarketCap() public {
        uint256 currentBlock = ChainUtils.getBlockNumber();
        accBlockWeightedMarketCap = getPendingAccBlockWeightedMarketCap(currentBlock);
        accBlockWeightedMarketCapLastStored = currentBlock;

        emit AccBlockWeightedMarketCapStored(accBlockWeightedMarketCap);
    }

    function maxAccPnlPerToken() public view returns (uint256) {
        // PRECISION
        return PRECISION + accRewardsPerToken;
    }

    function collateralizationP() public view returns (uint256) {
        uint _maxAccPnlPerToken = maxAccPnlPerToken();
        return
            ((
                accPnlPerTokenUsed > 0
                    ? (_maxAccPnlPerToken - uint256(accPnlPerTokenUsed))
                    : (_maxAccPnlPerToken + uint256(accPnlPerTokenUsed * (-1)))
            ) *
                100 *
                PRECISION) / _maxAccPnlPerToken;
    }

    function withdrawEpochsTimelock() public view returns (uint256) {
        uint256 collatP = collateralizationP();
        uint256 overCollatP = (collatP - Math.min(collatP, 100 * PRECISION));

        return
            overCollatP > withdrawLockThresholdsP[1]
                ? WITHDRAW_EPOCHS_LOCKS[2]
                : (overCollatP > withdrawLockThresholdsP[0] ? WITHDRAW_EPOCHS_LOCKS[1] : WITHDRAW_EPOCHS_LOCKS[0]);
    }

    function getPendingAccBlockWeightedMarketCap(uint256 currentBlock) public view returns (uint256) {
        return
            accBlockWeightedMarketCap +
            ((currentBlock - accBlockWeightedMarketCapLastStored) * PRECISION_2) /
            Math.max(marketCap(), 1);
    }

    function maxDeposit(address owner) public view override returns (uint256) {
        return _convertToAssets(maxMint(owner), Math.Rounding.Down);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return _convertToAssets(maxRedeem(owner), Math.Rounding.Down);
    }

    function tvl() public view returns (uint256) {
        return (maxAccPnlPerToken() * totalSupply()) / PRECISION; 
    }

    function availableAssets() public view returns (uint256) {
        return (uint256(int256(maxAccPnlPerToken()) - accPnlPerTokenUsed) * totalSupply()) / PRECISION; 
    }

    function marketCap() public view returns (uint256) {
        return (totalSupply() * shareToAssetsPrice) / PRECISION; 
    }

    function govAddress() public view returns (address) {
        return ITradingStorage(storageT).gov();
    }

    function mainPoolOwner() public view returns (address) {
        return IMainPool(mainPool).mainPoolOwner();
    }

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view override returns (uint256 shares) {
        return assets.mulDiv(PRECISION, shareToAssetsPrice, rounding);
    }

    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view override returns (uint256 assets) {
        // Prevent overflow when called from maxDeposit with maxMint = uint.max
        if (shares == type(uint256).max && shareToAssetsPrice >= PRECISION) {
            return shares;
        }
        return shares.mulDiv(shareToAssetsPrice, PRECISION, rounding);
    }

    function updateShareToAssetsPrice() private {
        storeAccBlockWeightedMarketCap();

        shareToAssetsPrice = maxAccPnlPerToken() - (accPnlPerTokenUsed > 0 ? uint256(accPnlPerTokenUsed) : uint256(0)); // PRECISION
        emit ShareToAssetsPriceUpdated(shareToAssetsPrice);
    }

    function scaleVariables(uint256 shares, uint256 assets, bool isDeposit) private {
        uint256 supply = totalSupply();

        if (accPnlPerToken < 0) {
            accPnlPerToken = (accPnlPerToken * int256(supply)) / (isDeposit ? int256(supply + shares) : int256(supply - shares + 1));
        } else if (accPnlPerToken > 0) {
            if (supply > 0 ) totalLiability += ((int256(shares) * totalLiability) / int256(supply)) * (isDeposit ? int256(1) : int256(-1));
        }

        totalDeposited = isDeposit ? totalDeposited + assets : totalDeposited - assets;

        storeAccBlockWeightedMarketCap();
    }

    function _assetIERC20() private view returns (IERC20) {
        return IERC20(asset());
    }
}

