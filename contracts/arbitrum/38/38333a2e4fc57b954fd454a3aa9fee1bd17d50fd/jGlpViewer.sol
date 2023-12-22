// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Math} from "./Math.sol";
import {JonesGlpVault} from "./JonesGlpVault.sol";
import {JonesGlpVaultRouter} from "./JonesGlpVaultRouter.sol";
import {JonesGlpLeverageStrategy} from "./JonesGlpLeverageStrategy.sol";
import {GlpJonesRewards} from "./GlpJonesRewards.sol";
import {JonesGlpRewardTracker} from "./JonesGlpRewardTracker.sol";
import {JonesGlpStableVault} from "./JonesGlpStableVault.sol";
import {JonesGlpCompoundRewards} from "./JonesGlpCompoundRewards.sol";
import {WhitelistController} from "./WhitelistController.sol";
import {IWhitelistController} from "./IWhitelistController.sol";
import {IGlpManager, IGMXVault} from "./IGlpManager.sol";
import {IERC4626} from "./IERC4626.sol";
import {IERC20, IERC20Metadata} from "./IERC20Metadata.sol";
import {Ownable} from "./Ownable.sol";
import {GlpAdapter} from "./GlpAdapter.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";

contract jGlpViewer is Ownable {
    using Math for uint256;

    IAggregatorV3 public oracle =
        IAggregatorV3(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);

    address public constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    uint256 public constant PRECISION = 1e30;
    uint256 public constant GMX_BASIS = 1e4;
    uint256 public constant GLP_DECIMALS = 1e18;
    uint256 public constant BASIS_POINTS = 1e12;

    IGlpManager public constant manager =
        IGlpManager(0x3963FfC9dff443c2A94f21b129D429891E32ec18);
    IERC20 public constant glp =
        IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);

    struct Contracts {
        JonesGlpVault glpVault;
        JonesGlpVaultRouter router;
        GlpJonesRewards jonesRewards;
        JonesGlpRewardTracker glpTracker;
        JonesGlpRewardTracker stableTracker;
        JonesGlpLeverageStrategy strategy;
        JonesGlpStableVault stableVault;
        JonesGlpCompoundRewards glpCompounder;
        JonesGlpCompoundRewards stableCompounder;
        IGMXVault gmxVault;
        WhitelistController controller;
        GlpAdapter adapter;
    }

    Contracts public contracts;

    constructor(
        address _glpVaultRouter,
        address _strategy,
        address _jonesRewards,
        address _glpVault,
        address _stableVault,
        address _glpTracker,
        address _stableTracker,
        address _compounderGlp,
        address _compounderStable,
        address _controller,
        address _adapter
    ) {
        contracts = Contracts(
            JonesGlpVault(_glpVault),
            JonesGlpVaultRouter(_glpVaultRouter),
            GlpJonesRewards(_jonesRewards),
            JonesGlpRewardTracker(_glpTracker),
            JonesGlpRewardTracker(_stableTracker),
            JonesGlpLeverageStrategy(_strategy),
            JonesGlpStableVault(_stableVault),
            JonesGlpCompoundRewards(_compounderGlp),
            JonesGlpCompoundRewards(_compounderStable),
            IGMXVault(manager.vault()),
            WhitelistController(_controller),
            GlpAdapter(_adapter)
        );
    }

    // Glp Functions
    // GLP Vault: User deposit GLP are minted GVRT
    // GLP Reward Tracker: Are staked GVRT
    // GLP Compounder: Manage GVRT on behalf of the user are minted jGLP
    function getGlpTvl() public view returns (uint256) {
        (, int256 lastPrice, , , ) = oracle.latestRoundData(); //8 decimals
        uint256 totalAssets = getTotalGlp(); // total glp
        uint256 USDC = contracts.strategy.getStableGlpValue(totalAssets); // GMX GLP Redeem for USDC
        return USDC.mulDiv(uint256(lastPrice), 1e8);
    }

    function getTotalGlp() public view returns (uint256) {
        return contracts.glpVault.totalAssets(); //total glp
    }

    function getGlpMaxCap() public view returns (uint256) {
        return contracts.router.getMaxCapGlp();
    }

    function getGlpClaimableRewards(address _user)
        public
        view
        returns (uint256)
    {
        return contracts.glpTracker.claimable(_user);
    }

    function getGlpPriceUsd() public view returns (uint256) {
        return contracts.strategy.getStableGlpValue(GLP_DECIMALS); // USDC Price of sell 1 glp (1e18)
    }

    function getStakedGVRT(address _user) public view returns (uint256) {
        return contracts.glpTracker.stakedAmount(_user); // GVRT
    }

    function sharesToGlp(uint256 _shares) public view returns (uint256) {
        return contracts.glpVault.previewRedeem(_shares); // GVRT -> GLP
    }

    function getGVRT(uint256 _shares) public view returns (uint256) {
        return contracts.glpCompounder.previewRedeem(_shares); // jGLP -> GVRT
    }

    function getjGlp(address _user) public view returns (uint256) {
        return contracts.glpCompounder.balanceOf(_user); // jGLP
    }

    function getGlp(address _user, bool _compound)
        public
        view
        returns (uint256)
    {
        uint256 GVRT;
        if (_compound) {
            uint256 jGLP = getjGlp(_user); //jGLP
            GVRT = getGVRT(jGLP); // jGLP -> GVRT
        } else {
            GVRT = getStakedGVRT(_user); // GVRT
        }
        return sharesToGlp(GVRT); // GVRT -> GLP
    }

    function getGlpRatio(uint256 _jGLP) public view returns (uint256) {
        uint256 GVRT = getGVRT(_jGLP); // jGLP -> GVRT
        return sharesToGlp(GVRT); // GVRT -> GLPC
    }

    function getGlpRatioWithoutFees(uint256 _jGLP)
        public
        view
        returns (uint256)
    {
        uint256 GVRT = getGVRT(_jGLP); // jGLP -> GVRT
        uint256 glpPrice = ((manager.getAum(false) + manager.getAum(true)) / 2)
            .mulDiv(GLP_DECIMALS, glp.totalSupply(), Math.Rounding.Down); // 30 decimals
        uint256 glpDebt = contracts.strategy.stableDebt().mulDiv(
            PRECISION * BASIS_POINTS,
            glpPrice,
            Math.Rounding.Down
        ); // 18 decimals
        uint256 strategyGlpBalance = glp.balanceOf(address(contracts.strategy)); // 18 decimals
        if (glpDebt > strategyGlpBalance) {
            return 0;
        }
        uint256 underlyingGlp = strategyGlpBalance - glpDebt; // 18 decimals
        return
            GVRT.mulDiv(
                underlyingGlp,
                contracts.glpVault.totalSupply(),
                Math.Rounding.Down
            ); // GVRT -> GLP
    }

    // USDC Functions
    // USDC Vault: User deposit USDC are minted UVRT
    // USDC Reward Tracker: Are staked UVRT
    // USDC Compounder: Manage UVRT on behalf of the user are minted jUSDC
    function getUSDCTvl() public view returns (uint256) {
        return contracts.stableVault.tvl(); // USDC Price * total USDC
    }

    function getTotalUSDC() public view returns (uint256) {
        return contracts.stableVault.totalAssets(); //total USDC
    }

    function getStakedUVRT(address _user) public view returns (uint256) {
        return contracts.stableTracker.stakedAmount(_user); // UVRT
    }

    function getUSDCClaimableRewards(address _user)
        public
        view
        returns (uint256)
    {
        return contracts.stableTracker.claimable(_user);
    }

    function sharesToUSDC(uint256 _shares) public view returns (uint256) {
        return contracts.stableVault.previewRedeem(_shares); // UVRT -> USDC
    }

    function getUVRT(uint256 _shares) public view returns (uint256) {
        return contracts.stableCompounder.previewRedeem(_shares); // jUSDC -> UVRT
    }

    function getjUSDC(address _user) public view returns (uint256) {
        return contracts.stableCompounder.balanceOf(_user); // jUSDC
    }

    function getUSDC(address _user, bool _compound)
        public
        view
        returns (uint256)
    {
        uint256 UVRT;
        if (_compound) {
            uint256 jUSDC = getjUSDC(_user); // jUSDC
            UVRT = getUVRT(jUSDC); // jUSDC -> UVRT
        } else {
            UVRT = getStakedUVRT(_user); // UVRT
        }
        return sharesToUSDC(UVRT); // UVRT -> USDC
    }

    function getUSDCRatio(uint256 _jUSDC) public view returns (uint256) {
        uint256 UVRT = getUVRT(_jUSDC); // jUSDC -> UVRT
        return sharesToUSDC(UVRT); // UVRT -> USDC
    }

    //Incentive due leverage, happen on every glp deposit
    function getGlpDepositIncentive(uint256 _glpAmount)
        public
        view
        returns (uint256)
    {
        return contracts.strategy.glpMintIncentive(_glpAmount);
    }

    function getGlpRedeemRetention(uint256 _glpAmount)
        public
        view
        returns (uint256)
    {
        return contracts.strategy.glpRedeemRetention(_glpAmount); //18 decimals
    }

    // Jones emissiones available rewards

    function getJonesRewards(address _user) public view returns (uint256) {
        return contracts.jonesRewards.rewards(_user);
    }

    // User Role Info

    function getUserRoleInfo(address _user)
        public
        view
        returns (
            bool,
            bool,
            uint256,
            uint256
        )
    {
        bytes32 userRole = contracts.controller.getUserRole(_user);
        IWhitelistController.RoleInfo memory info = contracts
            .controller
            .getRoleInfo(userRole);

        return (
            info.jGLP_BYPASS_CAP,
            info.jUSDC_BYPASS_TIME,
            info.jGLP_RETENTION,
            info.jUSDC_RETENTION
        );
    }

    // User Withdraw Signal
    function getUserSignal(address _user, uint256 _epoch)
        public
        view
        returns (
            uint256 targetEpoch,
            uint256 commitedShares,
            bool redeemed,
            bool compound
        )
    {
        (targetEpoch, commitedShares, redeemed, compound) = contracts
            .router
            .withdrawSignal(_user, _epoch);
    }

    // Pause Functions
    function isRouterPaused() public view returns (bool) {
        return contracts.router.paused();
    }

    function isStableVaultPaused() public view returns (bool) {
        return contracts.stableVault.paused();
    }

    function isGlpVaultPaused() public view returns (bool) {
        return contracts.glpVault.paused();
    }

    //Strategy functions

    function getTargetLeverage() public view returns (uint256) {
        return contracts.strategy.getTargetLeverage();
    }

    function getUnderlyingGlp() public view returns (uint256) {
        return contracts.strategy.getUnderlyingGlp();
    }

    function getStrategyTvl() public view returns (uint256) {
        (, int256 lastPrice, , , ) = oracle.latestRoundData(); // 8 decimals
        uint256 totalGlp = glp.balanceOf(address(contracts.strategy)); // 18 decimals
        uint256 USDC = contracts.strategy.getStableGlpValue(totalGlp); // GMX GLP Redeem for USDC 6 decimals
        return USDC.mulDiv(uint256(lastPrice), 1e8);
    }

    function getStableDebt() public view returns (uint256) {
        (, int256 lastPrice, , , ) = oracle.latestRoundData(); // 8 decimals
        return contracts.strategy.stableDebt().mulDiv(uint256(lastPrice), 1e8);
    }

    // Current Epoch
    function currentEpoch() public view returns (uint256) {
        return contracts.router.currentEpoch();
    }

    //Owner functions

    function updateGlpVault(address _newGlpVault) external onlyOwner {
        contracts.glpVault = JonesGlpVault(_newGlpVault);
    }

    function updateGlpVaultRouter(address _newGlpVaultRouter)
        external
        onlyOwner
    {
        contracts.router = JonesGlpVaultRouter(_newGlpVaultRouter);
    }

    function updateGlpRewardTracker(address _newGlpTracker) external onlyOwner {
        contracts.glpTracker = JonesGlpRewardTracker(_newGlpTracker);
    }

    function updateStableRewardTracker(address _newStableTracker)
        external
        onlyOwner
    {
        contracts.stableTracker = JonesGlpRewardTracker(_newStableTracker);
    }

    function updateJonesGlpLeverageStrategy(
        address _newJonesGlpLeverageStrategy
    ) external onlyOwner {
        contracts.strategy = JonesGlpLeverageStrategy(
            _newJonesGlpLeverageStrategy
        );
    }

    function updateJonesGlpStableVault(address _newJonesGlpStableVault)
        external
        onlyOwner
    {
        contracts.stableVault = JonesGlpStableVault(_newJonesGlpStableVault);
    }

    function updatejGlpJonesGlpCompoundRewards(
        address _newJonesGlpCompoundRewards
    ) external onlyOwner {
        contracts.glpCompounder = JonesGlpCompoundRewards(
            _newJonesGlpCompoundRewards
        );
    }

    function updateAdapter(address _newAdapter) external onlyOwner {
        contracts.adapter = GlpAdapter(_newAdapter);
    }

    function updatejUSDCJonesGlpCompoundRewards(
        address _newJonesUSDCCompoundRewards
    ) external onlyOwner {
        contracts.stableCompounder = JonesGlpCompoundRewards(
            _newJonesUSDCCompoundRewards
        );
    }

    function updateDeployment(
        address _glpVaultRouter,
        address _strategy,
        address _jonesRewards,
        address _glpVault,
        address _stableVault,
        address _glpTracker,
        address _stableTracker,
        address _compounderGlp,
        address _compounderStable,
        address _controller,
        address _adapter
    ) external onlyOwner {
        contracts = Contracts(
            JonesGlpVault(_glpVault),
            JonesGlpVaultRouter(_glpVaultRouter),
            GlpJonesRewards(_jonesRewards),
            JonesGlpRewardTracker(_glpTracker),
            JonesGlpRewardTracker(_stableTracker),
            JonesGlpLeverageStrategy(_strategy),
            JonesGlpStableVault(_stableVault),
            JonesGlpCompoundRewards(_compounderGlp),
            JonesGlpCompoundRewards(_compounderStable),
            IGMXVault(manager.vault()),
            WhitelistController(_controller),
            GlpAdapter(_adapter)
        );
    }

    // This amount do not include the withdraw glp retention
    // you have to discount the glp withdraw retentions before using this function
    function previewRedeemGlp(address _token, uint256 _glpAmount)
        public
        view
        returns (uint256, uint256)
    {
        IGMXVault vault = contracts.gmxVault;

        IERC20Metadata token = IERC20Metadata(_token);

        uint256 usdgAmount = _glpAmount.mulDiv(
            manager.getAumInUsdg(false),
            glp.totalSupply()
        ); // 18 decimals

        uint256 redemptionAmount = usdgAmount.mulDiv(
            PRECISION,
            vault.getMaxPrice(_token)
        ); // 18 decimals

        redemptionAmount = redemptionAmount.mulDiv(
            10**token.decimals(),
            GLP_DECIMALS
        );

        uint256 retentionBasisPoints = _getGMXBasisRetention(
            _token,
            usdgAmount,
            vault.mintBurnFeeBasisPoints(),
            vault.taxBasisPoints(),
            false
        );

        return (
            redemptionAmount.mulDiv(
                GMX_BASIS - retentionBasisPoints,
                GMX_BASIS
            ),
            retentionBasisPoints
        );
    }

    function previewMintGlp(address _token, uint256 _assetAmount)
        public
        view
        returns (uint256, uint256)
    {
        IGMXVault vault = contracts.gmxVault;

        IERC20Metadata token = IERC20Metadata(_token);

        uint256 aumInUsdg = manager.getAumInUsdg(true);

        uint256 assetPrice = vault.getMinPrice(_token); // 30 decimals

        uint256 usdgAmount = _assetAmount.mulDiv(assetPrice, PRECISION); // 6 decimals

        usdgAmount = usdgAmount.mulDiv(GLP_DECIMALS, 10**token.decimals()); // 18 decimals

        uint256 retentionBasisPoints = vault.getFeeBasisPoints(
            _token,
            usdgAmount,
            vault.mintBurnFeeBasisPoints(),
            vault.taxBasisPoints(),
            true
        );

        uint256 amountAfterRetentions = _assetAmount.mulDiv(
            GMX_BASIS - retentionBasisPoints,
            GMX_BASIS
        ); // 6 decimals

        uint256 mintAmount = amountAfterRetentions.mulDiv(
            assetPrice,
            PRECISION
        ); // 6 decimals

        mintAmount = mintAmount.mulDiv(GLP_DECIMALS, 10**token.decimals()); // 18 decimals

        return (
            aumInUsdg == 0
                ? mintAmount
                : mintAmount.mulDiv(glp.totalSupply(), aumInUsdg),
            retentionBasisPoints
        ); // 18 decimals
    }

    function getMintGlpIncentive(address _token, uint256 _assetAmount)
        public
        view
        returns (uint256)
    {
        IGMXVault vault = contracts.gmxVault;

        IERC20Metadata token = IERC20Metadata(_token);

        uint256 assetPrice = vault.getMinPrice(_token); // 30 decimals

        uint256 usdgAmount = _assetAmount.mulDiv(assetPrice, PRECISION); // 6 decimals

        usdgAmount = usdgAmount.mulDiv(GLP_DECIMALS, 10**token.decimals()); // 18 decimals

        return
            vault.getFeeBasisPoints(
                _token,
                usdgAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                true
            );
    }

    function getRedeemGlpRetention(address _token, uint256 _glpAmount)
        public
        view
        returns (uint256)
    {
        IGMXVault vault = contracts.gmxVault;

        IERC20Metadata token = IERC20Metadata(_token);

        uint256 usdgAmount = _glpAmount.mulDiv(
            manager.getAumInUsdg(false),
            glp.totalSupply()
        );

        uint256 redemptionAmount = usdgAmount.mulDiv(
            PRECISION,
            vault.getMaxPrice(_token)
        );

        redemptionAmount = redemptionAmount.mulDiv(
            10**token.decimals(),
            GLP_DECIMALS
        );

        return
            _getGMXBasisRetention(
                _token,
                usdgAmount,
                vault.mintBurnFeeBasisPoints(),
                vault.taxBasisPoints(),
                false
            );
    }

    function _getGMXBasisRetention(
        address _token,
        uint256 _usdgDelta,
        uint256 _retentionBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) private view returns (uint256) {
        IGMXVault vault = contracts.gmxVault;

        if (!vault.hasDynamicFees()) return _retentionBasisPoints;

        uint256 initialAmount = _increment
            ? vault.usdgAmounts(_token)
            : vault.usdgAmounts(_token) - _usdgDelta;

        uint256 nextAmount = initialAmount + _usdgDelta;
        if (!_increment) {
            nextAmount = _usdgDelta > initialAmount
                ? 0
                : initialAmount - _usdgDelta;
        }

        uint256 targetAmount = vault.getTargetUsdgAmount(_token);
        if (targetAmount == 0) return _retentionBasisPoints;

        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount - targetAmount
            : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount
            ? nextAmount - targetAmount
            : targetAmount - nextAmount;

        // action improves relative asset balance
        if (nextDiff < initialDiff) {
            uint256 rebateBps = _taxBasisPoints.mulDiv(
                initialDiff,
                targetAmount
            );
            return
                rebateBps > _retentionBasisPoints
                    ? 0
                    : _retentionBasisPoints - rebateBps;
        }

        uint256 averageDiff = (initialDiff + nextDiff) / 2;
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = _taxBasisPoints.mulDiv(averageDiff, targetAmount);
        return _retentionBasisPoints + taxBps;
    }

    //Use when flexible cap status is TRUE
    //Returns 18 decimals
    function getUsdcCap() public view returns (uint256) {
        return contracts.adapter.getUsdcCap();
    }

    function usingFlexibleCap() public view returns (bool) {
        return contracts.adapter.usingFlexibleCap();
    }

    function usingHatlist() public view returns (bool) {
        return contracts.adapter.usingHatlist();
    }
}

