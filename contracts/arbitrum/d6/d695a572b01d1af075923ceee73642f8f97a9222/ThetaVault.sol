// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";

import "./SafeERC20.sol";
import "./IERC20.sol";

import "./IThetaVault.sol";
import "./IThetaVaultManagement.sol";
import "./IVolatilityTokenManagement.sol";
import "./IUniswapHelper.sol";

contract ThetaVault is Initializable, IThetaVault, IThetaVaultManagement, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 internal constant PRECISION_DECIMALS = 18;
    uint16 internal constant MAX_PERCENTAGE = 10000;
    uint24 private constant POOL_FEE = 3000;

    address public depositor;

    IERC20 internal token;
    IPlatform public override platform;
    IVolatilityToken public override volToken;
    ISwapRouter public swapRouter;
    IUniswapV3LiquidityManager public override liquidityManager;

    address public manager;
    address public rebaser;

    uint256 public initialTokenToThetaTokenRate;

    uint16 public minPoolSkewPercentage;
    uint32 public override extraLiquidityPercentage;

    uint16 public depositHoldingsPercentage;
    uint16 public override minDexPercentageAllowed;

    uint256 public totalHoldingsAmount;

    uint256 public minRebalanceDiff;

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _initialTokenToThetaTokenRate, IPlatform _platform, IVolatilityToken _volToken,
            IERC20 _token, string memory _lpTokenName, string memory _lpTokenSymbolName, ISwapRouter _swapRouter,
            IUniswapV3LiquidityManager _liquidityManager) public initializer {
        require(address(_platform) != address(0));
        require(address(_volToken) != address(0));
        require(address(_token) != address(0));
        require(address(_swapRouter) != address(0));
        require(address(_liquidityManager) != address(0));
        require(_initialTokenToThetaTokenRate > 0);

        initialTokenToThetaTokenRate = _initialTokenToThetaTokenRate;
        minPoolSkewPercentage = 300;
        extraLiquidityPercentage = 1500;
        minRebalanceDiff = 100000;
        depositHoldingsPercentage = 1500;
        minDexPercentageAllowed = 3000;

        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init();
        ERC20Upgradeable.__ERC20_init(_lpTokenName, _lpTokenSymbolName);

        platform = _platform;
        token = _token;
        volToken = _volToken;

        setSwapRouter(_swapRouter);
        setLiquidityManager(_liquidityManager);

        token.safeApprove(address(platform), type(uint256).max);
        token.safeApprove(address(volToken), type(uint256).max);
        IERC20(address(volToken)).safeApprove(address(volToken), type(uint256).max);
    }

    struct DepositLocals {
        uint256 mintVolTokenUSDCAmount;
        uint256 addedLiquidityUSDCAmount;
        uint256 mintedVolTokenAmount;
        uint256 platformLiquidityAmount;
        uint256 holdingsAmount;
    }

    function deposit(uint168 _tokenAmount, uint32 _balanceCVIValue) external returns (uint256 thetaTokensMinted) {
        require(msg.sender == depositor);
        require(_tokenAmount > 0);

        token.safeTransferFrom(msg.sender, address(this), _tokenAmount);

        // Note: reverts if pool is skewed after arbitrage, as intended
        (uint256 balance, uint256 volTokenPositionBalance) = _rebalance(_tokenAmount, _balanceCVIValue);

        // Mint theta lp tokens
        if (totalSupply() > 0 && balance > 0) {
            thetaTokensMinted = (_tokenAmount * totalSupply()) / balance;
        } else {
            thetaTokensMinted = _tokenAmount * initialTokenToThetaTokenRate;
        }

        require(thetaTokensMinted > 0); // 'Too few tokens'
        _mint(msg.sender, thetaTokensMinted);

        DepositLocals memory locals = _deposit(_tokenAmount, volTokenPositionBalance, true);

        emit Deposit(msg.sender, _tokenAmount, locals.platformLiquidityAmount, locals.mintVolTokenUSDCAmount, locals.mintedVolTokenAmount, 
            locals.addedLiquidityUSDCAmount, thetaTokensMinted);
    }

    struct WithdrawLocals {
        uint256 withdrawnLiquidity;
        uint256 platformLPTokensToRemove;
        uint256 removedVolTokensAmount;
        uint256 dexRemovedUSDC;
        uint256 burnedVolTokensUSDCAmount;
    }

    function withdraw(uint168 _thetaTokenAmount, uint32 _burnCVIValue, uint32 _withdrawCVIValue) external override returns (uint256 tokenWithdrawnAmount) {
        require(msg.sender == depositor);
        require(_thetaTokenAmount > 0);

        require(balanceOf(msg.sender) >= _thetaTokenAmount, 'Not enough tokens');
        IERC20(address(this)).safeTransferFrom(msg.sender, address(this), _thetaTokenAmount);

        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();
        _rebalance(0, cviValue);

        WithdrawLocals memory locals;

        locals.platformLPTokensToRemove = (_thetaTokenAmount * IERC20(address(platform)).balanceOf(address(this))) / totalSupply();
        (locals.removedVolTokensAmount, locals.dexRemovedUSDC) = liquidityManager.removeDEXLiquidity(_thetaTokenAmount, totalSupply());

        locals.burnedVolTokensUSDCAmount = burnVolTokens(locals.removedVolTokensAmount, _burnCVIValue);

        (, locals.withdrawnLiquidity) = platform.withdrawLPTokens(locals.platformLPTokensToRemove, _withdrawCVIValue);

        uint256 withdrawHoldings = totalHoldingsAmount * _thetaTokenAmount / totalSupply();
        tokenWithdrawnAmount = withdrawHoldings + locals.withdrawnLiquidity + locals.dexRemovedUSDC + locals.burnedVolTokensUSDCAmount;
        totalHoldingsAmount -= withdrawHoldings;

        _burn(address(this), _thetaTokenAmount);

        token.safeTransfer(msg.sender, tokenWithdrawnAmount);

        emit Withdraw(msg.sender, tokenWithdrawnAmount, locals.withdrawnLiquidity, locals.removedVolTokensAmount, locals.burnedVolTokensUSDCAmount, locals.dexRemovedUSDC, _thetaTokenAmount);
    }

    function rebalance(uint32 _cviValue) external override onlyOwner {
        _rebalance(0, _cviValue);
    }

    function oracle() external view override returns (ICVIOracle) {
        return platform.cviOracle();
    }

    function platformPositionUnits() external view override returns (uint256) {
        return platform.totalPositionUnitsAmount();
    }

    function vaultPositionUnits() public view override returns (uint256) {
        (uint256 dexVolTokensAmount,, uint256 dexUSDCAmount) = liquidityManager.getReserves();
        if (IERC20(address(volToken)).totalSupply() == 0 || (dexVolTokensAmount == 0 && dexUSDCAmount == 0)) {
            return 0;
        }

        (uint256 totalPositionUnits,,,,,) = platform.positions(address(volToken));
        return totalPositionUnits * liquidityManager.getVaultDEXVolTokens() / IERC20(address(volToken)).totalSupply();
    }

    function setSwapRouter(ISwapRouter _newSwapRouter) public override onlyOwner {
        if (address(swapRouter) != address(0)) {
            token.safeApprove(address(swapRouter), 0);
            IERC20(address(volToken)).safeApprove(address(swapRouter), 0);
        }

        swapRouter = _newSwapRouter;

        token.safeApprove(address(swapRouter), type(uint256).max);
        IERC20(address(volToken)).safeApprove(address(swapRouter), type(uint256).max);

        emit SwapRouterSet(address(_newSwapRouter));
    }

    function setLiquidityManager(IUniswapV3LiquidityManager _newLiquidityManager) public override onlyOwner {
        if (address(liquidityManager) != address(0)) {
            token.safeApprove(address(liquidityManager), 0);
            IERC20(address(volToken)).safeApprove(address(liquidityManager), 0);
        }

        liquidityManager = _newLiquidityManager;

        token.safeApprove(address(liquidityManager), type(uint256).max);
        IERC20(address(volToken)).safeApprove(address(liquidityManager), type(uint256).max);

        emit LiquidityManagerSet(address(_newLiquidityManager));
    }

    function setRange(uint160 _minPriceSqrtX96, uint160 _maxPriceSqrtX96) public override {
        require(msg.sender == manager);
        _setRange(_minPriceSqrtX96, _maxPriceSqrtX96, false);

        emit RangeSet(_minPriceSqrtX96, _maxPriceSqrtX96);
    }

    function setInitialPrices(uint160 _minPriceSqrtX96, uint160 _maxPriceSqrtX96) public onlyOwner {
        _setRange(_minPriceSqrtX96, _maxPriceSqrtX96, false);
    }

    function rebaseCVI() external override {
        require(msg.sender == rebaser);
        _setRange(0, 0, true);
    }

    function setManager(address _newManager) external override onlyOwner {
        manager = _newManager;

        emit ManagerSet(_newManager);
    }

    function setRebaser(address _newRebaser) external override onlyOwner {
        rebaser = _newRebaser;

        emit RebaserSet(_newRebaser);
    }

    function setDepositor(address _newDepositor) external override onlyOwner {
        depositor = _newDepositor;

        emit DepositorSet(_newDepositor);
    }

    function setDepositHoldings(uint16 _newDepositHoldingsPercentage) external override onlyOwner {
        depositHoldingsPercentage = _newDepositHoldingsPercentage;


        emit DepositHoldingsSet(_newDepositHoldingsPercentage);
    }

    function setMinPoolSkew(uint16 _newMinPoolSkewPercentage) external override onlyOwner {
        minPoolSkewPercentage = _newMinPoolSkewPercentage;

        emit MinPoolSkewSet(_newMinPoolSkewPercentage);
    }

    function setLiquidityPercentages(uint32 _newExtraLiquidityPercentage, uint16 _minDexPercentageAllowed) external override onlyOwner {
        extraLiquidityPercentage = _newExtraLiquidityPercentage;
        minDexPercentageAllowed = _minDexPercentageAllowed;

        emit LiquidityPercentagesSet(_newExtraLiquidityPercentage, _minDexPercentageAllowed);
    }

    function setMinRebalanceDiff(uint256 _newMinRebalanceDiff) external override onlyOwner {
        minRebalanceDiff = _newMinRebalanceDiff;

        emit MinRebalanceDiffSet(_newMinRebalanceDiff);
    }

    function totalBalance(uint32 cviValue) public view override returns (uint256 balance, uint256 usdcPlatformLiquidity, uint256 intrinsicDEXVolTokenBalance, uint256 volTokenPositionBalance, uint256 dexUSDCAmount, uint256 dexVolTokensAmount) {
        (intrinsicDEXVolTokenBalance, volTokenPositionBalance,, dexUSDCAmount, dexVolTokensAmount,) = calculatePoolValue();
        (balance, usdcPlatformLiquidity) = _totalBalance(intrinsicDEXVolTokenBalance, dexUSDCAmount, cviValue);
    }

    function calculateOIBalance() external view override returns (uint256 oiBalance) {
        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();
        (, uint256 totalPositionsBalance) = platform.totalBalance(true, cviValue);
        oiBalance = totalPositionsBalance - vaultPositionBalance();
    }

    function calculateMaxOIBalance() external view override returns (uint256 maxOIBalance) {
        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();
        (, uint256 oiBalance) = platform.totalBalance(true, cviValue);

        uint256 freeLiquidity = platform.totalLeveragedTokensAmount() - platform.totalPositionUnitsAmount();

        // FreeLiquidity = (MaxCVI - CurrCVI) / CurrCVI * MaxOI
        // MaxOI = FreeLiquidity * CurrCVI / (MaxCVI - CurrCVI)
        maxOIBalance = freeLiquidity * cviValue / (platform.maxCVIValue() - cviValue) + (oiBalance - vaultPositionBalance());
    }

    function _rebalance(uint256 _arbitrageAmount, uint32 _balanceCVIValue) internal returns (uint256 balance, uint256 volTokenPositionBalance) {
        preRebalance();

        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();

        // Note: reverts if pool is skewed, as intended
        uint256 intrinsicDEXVolTokenBalance;
        uint256 usdcPlatformLiquidity;
        uint256 dexUSDCAmount;

        (balance, usdcPlatformLiquidity, intrinsicDEXVolTokenBalance, volTokenPositionBalance, dexUSDCAmount) = totalBalanceWithArbitrage(_arbitrageAmount, cviValue);

        uint256 adjustedPositionUnits = platform.totalPositionUnitsAmount() * (MAX_PERCENTAGE + extraLiquidityPercentage) / MAX_PERCENTAGE;
        uint256 totalLeveragedTokensAmount = platform.totalLeveragedTokensAmount();

        // No need to rebalance if no position units for vault (i.e. dex not initialized yet)
        if (dexUSDCAmount > 0) {
            if (totalLeveragedTokensAmount > adjustedPositionUnits + minRebalanceDiff) {
                uint256 extraLiquidityAmount = totalLeveragedTokensAmount - adjustedPositionUnits;

                (, uint256 withdrawnAmount) = platform.withdraw(extraLiquidityAmount, type(uint256).max, cviValue);

                _deposit(withdrawnAmount, volTokenPositionBalance, false);
            } else if (totalLeveragedTokensAmount + minRebalanceDiff < adjustedPositionUnits) {
                uint256 liquidityMissing = adjustedPositionUnits - totalLeveragedTokensAmount;

                if (intrinsicDEXVolTokenBalance + dexUSDCAmount > liquidityMissing && 
                    (intrinsicDEXVolTokenBalance + dexUSDCAmount - liquidityMissing) * MAX_PERCENTAGE / balance >= minDexPercentageAllowed) {

                    (uint256 removedVolTokensAmount, uint256 dexRemovedUSDC) = liquidityManager.removeDEXLiquidity(liquidityMissing, intrinsicDEXVolTokenBalance + dexUSDCAmount);
                    uint256 totalUSDC = burnVolTokens(removedVolTokensAmount, cviValue) + dexRemovedUSDC;

                    platform.deposit(totalUSDC, 0, cviValue);
                }
            }

            (balance,, intrinsicDEXVolTokenBalance, volTokenPositionBalance, dexUSDCAmount,) = totalBalance(_balanceCVIValue);
        }
    }

    function totalBalanceWithArbitrage(uint256 _usdcArbitrageAmount, uint32 _balanceCVIValue) private returns (uint256 balance, uint256 usdcPlatformLiquidity, uint256 intrinsicDEXVolTokenBalance, uint256 volTokenPositionBalance, uint256 dexUSDCAmount) {
        (intrinsicDEXVolTokenBalance, volTokenPositionBalance,, dexUSDCAmount) = 
            calculatePoolValueWithArbitrage(_usdcArbitrageAmount);
        (balance, usdcPlatformLiquidity) = _totalBalance(intrinsicDEXVolTokenBalance, dexUSDCAmount, _balanceCVIValue);
    }

    function _totalBalance(uint256 _intrinsicDEXVolTokenBalance, uint256 _dexUSDCAmount, uint32 _cviValue) private view returns (uint256 balance, uint256 usdcPlatformLiquidity)
    {
        (uint256 vaultIntrinsicDEXVolTokenBalance, uint256 vaultDEXUSDCAmount) = liquidityManager.getVaultDEXBalance(_intrinsicDEXVolTokenBalance, _dexUSDCAmount);

        usdcPlatformLiquidity = getUSDCPlatformLiquidity(_cviValue);
        balance = totalHoldingsAmount + usdcPlatformLiquidity + vaultIntrinsicDEXVolTokenBalance + vaultDEXUSDCAmount;
    }

    function _deposit(uint256 _tokenAmount, uint256 _volTokenPositionBalance, bool _takeHoldings) internal returns (DepositLocals memory locals)
    {
        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();

        uint256 intrinsicVolTokenPrice;
        
        if (IERC20(address(volToken)).totalSupply() > 0) {
            intrinsicVolTokenPrice =
                _volTokenPositionBalance * (10 ** PRECISION_DECIMALS) /
                    IERC20(address(volToken)).totalSupply();
        } else {
            intrinsicVolTokenPrice = liquidityManager.getDexPrice() * (10 ** PRECISION_DECIMALS) / 
                (10 ** ERC20Upgradeable(address(volToken)).decimals());
        }

        (locals.mintVolTokenUSDCAmount, locals.platformLiquidityAmount, locals.holdingsAmount) = calculateDepositAmounts(
            _tokenAmount,
            intrinsicVolTokenPrice,
            _takeHoldings
        );

        if (_takeHoldings) {
            totalHoldingsAmount += locals.holdingsAmount;
        }

        platform.deposit(locals.platformLiquidityAmount, 0, cviValue);

        uint256 mintedVolTokenAmount = mintVolTokens(locals.mintVolTokenUSDCAmount);
        uint256 addDexUSDCAmount = liquidityManager.calculateDEXLiquidityUSDCAmount(mintedVolTokenAmount);

        (locals.addedLiquidityUSDCAmount, locals.mintedVolTokenAmount) = addDEXLiquidity(mintedVolTokenAmount, addDexUSDCAmount);
    }

    function calculatePoolValue() internal view returns (uint256 intrinsicDEXVolTokenBalance, uint256 volTokenBalance, uint256 dexUSDCAmountByVolToken, uint256 dexUSDCAmount, uint256 dexVolTokensAmount, bool isPoolSkewed) {
        (dexVolTokensAmount, dexUSDCAmountByVolToken, dexUSDCAmount) = liquidityManager.getReserves();

        bool isPositive = true;
        (uint256 currPositionUnits,,,,,) = platform.positions(address(volToken));
        if (currPositionUnits != 0) {
            (volTokenBalance, isPositive,,,,) = platform.calculatePositionBalance(address(volToken));
        }
        require(isPositive); // 'Negative balance'

        // No need to check skew if pool is still empty
        if (dexVolTokensAmount > 0 && dexUSDCAmountByVolToken > 0) {
            // Multiply by vol token decimals to get intrinsic worth in USDC
            intrinsicDEXVolTokenBalance =
                (dexVolTokensAmount * volTokenBalance) /
                IERC20(address(volToken)).totalSupply();
            uint256 delta = intrinsicDEXVolTokenBalance > dexUSDCAmountByVolToken ? intrinsicDEXVolTokenBalance - dexUSDCAmountByVolToken : dexUSDCAmountByVolToken - intrinsicDEXVolTokenBalance;

            if (delta > (intrinsicDEXVolTokenBalance * minPoolSkewPercentage) / MAX_PERCENTAGE) {
                isPoolSkewed = true;
            }
        }
    }

    function calculatePoolValueWithArbitrage(uint256 _usdcArbitrageAmount) private returns (uint256 intrinsicDEXVolTokenBalance, uint256 volTokenBalance, uint256 dexUSDCAmountByVolToken, uint256 dexUSDCAmount) {
        bool isPoolSkewed;
        (intrinsicDEXVolTokenBalance, volTokenBalance, dexUSDCAmountByVolToken, dexUSDCAmount,, isPoolSkewed) = calculatePoolValue();

        if (isPoolSkewed) {
            attemptArbitrage(_usdcArbitrageAmount + totalHoldingsAmount, intrinsicDEXVolTokenBalance, dexUSDCAmountByVolToken, volTokenBalance);
            (intrinsicDEXVolTokenBalance, volTokenBalance, dexUSDCAmountByVolToken, dexUSDCAmount,, isPoolSkewed) = calculatePoolValue();
            require(!isPoolSkewed, 'Too skewed');
        }
    }

    function attemptArbitrage(uint256 _usdcAmount, uint256 _intrinsicDEXVolTokenBalance, uint256 _dexUSDCAmount, uint256 _volTokenBalance) private {
        uint256 usdcAmountNeeded = liquidityManager.calculateArbitrageAmount(_volTokenBalance);
        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();

        uint256 withdrawnLiquidity = 0;
        if (_usdcAmount < usdcAmountNeeded) {
            uint256 leftAmount = usdcAmountNeeded - _usdcAmount;

            // Get rest of amount needed from platform liquidity (will revert if not enough collateral)
            // Revert is ok here, befcause in that case, there is no way to arbitrage and resolve the skew,
            // and no requests will fulfill anyway
            (uint256 platformBalance,) = platform.totalBalance(true, cviValue);
            (, withdrawnLiquidity) = platform.withdrawLPTokens(
                (leftAmount * IERC20(address(platform)).totalSupply()) / platformBalance, cviValue);

            usdcAmountNeeded = withdrawnLiquidity + _usdcAmount;
        }

        uint256 updatedUSDCAmount;
        uint256 beforeBalance = IERC20(address(volToken)).balanceOf(address(this));
        if (_dexUSDCAmount > _intrinsicDEXVolTokenBalance) {
            // Price is higher than intrinsic value, mint at lower price, then buy on dex
            uint256 mintedVolTokenAmount = mintVolTokens(usdcAmountNeeded);
            updatedUSDCAmount = sellVolTokens(mintedVolTokenAmount);
        } else {
            // Price is lower than intrinsic value, buy on dex, then burn at higher price
            uint256 volTokens = buyVolTokens(usdcAmountNeeded);
            updatedUSDCAmount = burnVolTokens(volTokens, cviValue);
        }

        // Make sure no vol tokens where left accidently by arbitrage (for example, if corssing range in buy/sell)
        require(IERC20(address(volToken)).balanceOf(address(this)) == beforeBalance);

        // Make sure we didn't lose by doing arbitrage (for example, mint/burn fees exceeds arbitrage gain)
        require(updatedUSDCAmount > usdcAmountNeeded); // 'Arbitrage failed'

        // Deposit arbitrage gains back to vault as platform liquidity as well
        platform.deposit(updatedUSDCAmount - usdcAmountNeeded + withdrawnLiquidity, 0, cviValue);
    }

    function vaultPositionBalance() private view returns (uint256 balance) {
        (uint256 volTokenBalance, bool isPositive,,,,) = platform.calculatePositionBalance(address(volToken));
        
        require(isPositive); // 'Negative balance'

        balance = volTokenBalance * liquidityManager.getVaultDEXVolTokens() / IERC20(address(volToken)).totalSupply();
    }

    function calculateDepositAmounts(uint256 _totalAmount, uint256 _intrinsicVolTokenPrice, bool _takeHoldings) private view returns (uint256 mintVolTokenUSDCAmount, uint256 platformLiquidityAmount, uint256 holdingsAmount) {
        holdingsAmount = _takeHoldings ? _totalAmount * depositHoldingsPercentage / MAX_PERCENTAGE : 0;

        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();
        mintVolTokenUSDCAmount = 
            liquidityManager.calculateDepositMintVolTokensUSDCAmount(IUniswapV3LiquidityManager.CalculateDepositParams(
                _totalAmount - holdingsAmount, cviValue, _intrinsicVolTokenPrice, platform.maxCVIValue(), extraLiquidityPercentage));

        // Simulate mint calculation for first (proportionally by balance) or non-first mint (by dex price)
        uint256 expectedMintedVolTokensAmount;
        if (IERC20(address(volToken)).totalSupply() > 0) {
            (uint256 currentBalance,,,,,) = platform.calculatePositionBalance(address(volToken));
            expectedMintedVolTokensAmount = (mintVolTokenUSDCAmount *
                IERC20(address(volToken)).totalSupply()) / currentBalance;
        } else {
            expectedMintedVolTokensAmount = 
                mintVolTokenUSDCAmount * (10 ** ERC20Upgradeable(address(volToken)).decimals()) / liquidityManager.getDexPrice();
        }

        uint256 usdcDEXAmount = liquidityManager.calculateDEXLiquidityUSDCAmount(expectedMintedVolTokensAmount);
        platformLiquidityAmount = _totalAmount - holdingsAmount - mintVolTokenUSDCAmount - usdcDEXAmount;
    }

    function burnVolTokens(uint256 _tokensToBurn, uint32 _cviValue) internal returns (uint256 burnedVolTokensUSDCAmount) {
        uint168 __tokensToBurn = uint168(_tokensToBurn);
        require(__tokensToBurn == _tokensToBurn); // Sanity, should very rarely fail

        burnedVolTokensUSDCAmount = volToken.burnTokens(__tokensToBurn, _cviValue);
    }

    function mintVolTokens(uint256 _usdcAmount) private returns (uint256 mintedVolTokenAmount) {
        uint168 __usdcAmount = uint168(_usdcAmount);
        require(__usdcAmount == _usdcAmount); // Sanity, should very rarely fail

        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();
        mintedVolTokenAmount = volToken.mintTokens(__usdcAmount, cviValue, cviValue);
    }

    function _setRange(uint160 _minPriceSqrtX96, uint160 _maxPriceSqrtX96, bool shouldRebase) private {
        // Sanity check there is no vol token stuck in contract before rebasing (precaution)
        require(IERC20(address(volToken)).balanceOf(address(this)) == 0);

        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();
        uint256 usdcBeforeBalance = IERC20(address(token)).balanceOf(address(this));
        (,,, uint256 volTokenPositionBalance,,) = totalBalance(cviValue);

        bool hasPosition = liquidityManager.hasPosition();
        if (hasPosition) {
            liquidityManager.collectFees();
            liquidityManager.removeDEXLiquidity(1, 1);
            liquidityManager.burnPosition();

            if (shouldRebase) {
                IVolatilityTokenManagement(address(volToken)).rebaseCVI();
            }
            liquidityManager.updatePoolPrice(volTokenPositionBalance);

            burnVolTokens(IERC20(address(volToken)).balanceOf(address(this)), cviValue);
        }

        if (!shouldRebase) {
            liquidityManager.setRange(_minPriceSqrtX96, _maxPriceSqrtX96);
        }

        if (hasPosition) {
            uint256 usdcAfterBalance = IERC20(address(token)).balanceOf(address(this));
            require(usdcAfterBalance > usdcBeforeBalance);

            // Deposit all cash creating new position
             (,,, volTokenPositionBalance,,) = totalBalance(cviValue);
            _deposit(usdcAfterBalance - usdcBeforeBalance, volTokenPositionBalance, false);
        }

        _rebalance(0, cviValue);
    }

    function depositLeftOvers(uint256 volTokenAmount, uint256 usdcAmount) private {
        (uint32 cviValue,,) = platform.cviOracle().getCVILatestRoundData();
        uint256 totalUSDC = usdcAmount;
        if (volTokenAmount > 0) {
            uint256 tokensToBurn = IERC20(address(volToken)).balanceOf(address(this));
            if (tokensToBurn > volTokenAmount) {
                tokensToBurn = volTokenAmount;
            }
            totalUSDC += burnVolTokens(tokensToBurn, cviValue);
        }

        if (totalUSDC > 0) {
            platform.deposit(totalUSDC, 0, cviValue);
        }
    }

    function getUSDCPlatformLiquidity(uint32 _cviValue) private view returns (uint256 usdcPlatformLiquidity) {
        uint256 platformLPTokensAmount = IERC20(address(platform)).balanceOf(address(this));

        if (platformLPTokensAmount > 0) {
            (uint256 platformBalance,) = platform.totalBalance(true, _cviValue);
            usdcPlatformLiquidity = (platformLPTokensAmount * platformBalance) / IERC20(address(platform)).totalSupply();
        }
    }

    function preRebalance() private {
        // Collect fees and add to platform liquidity
        if (liquidityManager.hasPosition()) {
            (uint256 volTokenAmount, uint256 usdcAmount) = liquidityManager.collectFees();
            depositLeftOvers(volTokenAmount, usdcAmount);
        }
    }

    function addDEXLiquidity(uint256 _mintedVolTokenAmount, uint256 _usdcAmount) private returns (uint256 addedUDSCAmount, uint256 addedVolTokenAmount) {
        (addedUDSCAmount, addedVolTokenAmount) = liquidityManager.addDEXLiquidity(_mintedVolTokenAmount, _usdcAmount);
        depositLeftOvers(_mintedVolTokenAmount - addedVolTokenAmount, _usdcAmount - addedUDSCAmount);
    }

    function sellVolTokens(uint256 volTokenAmount) private returns (uint256 usdcAmount) {
        return swapRouter.exactInput(ISwapRouter.ExactInputParams(abi.encodePacked(volToken, POOL_FEE, token), address(this), block.timestamp, volTokenAmount, 0));
    }

    function buyVolTokens(uint256 usdcAmount) private returns (uint256 volTokenAmount) {
        return swapRouter.exactInput(ISwapRouter.ExactInputParams(abi.encodePacked(token, POOL_FEE, volToken), address(this), block.timestamp, usdcAmount, 0));
    }
}

