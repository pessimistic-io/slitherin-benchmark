// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20, ERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import "./IERC20Metadata.sol";
import "./SafeMath.sol";

import "./IRadiantStaking.sol";
import "./IWETH.sol";
import "./IMDLP.sol";
import "./IMasterRadpie.sol";
import "./IBaseRewardPool.sol";
import "./IMintableERC20.sol";
import "./IRadpiePoolHelper.sol";
import "./ILockZap.sol";
import "./IAToken.sol";
import "./ILeverager.sol";
import "./ILendingPool.sol";
import "./ICreditDelegationToken.sol";
import "./IWETHGateway.sol";
import "./IChefIncentivesController.sol";
import "./IRDNTRewardManager.sol";
import "./IEligibilityDataProvider.sol";
import "./IRadpieReceiptToken.sol";
import "./IRewardDistributor.sol";

import "./RadiantUtilLib.sol";
import "./RadpieFactoryLib.sol";

/// @title RadiantStaking
/// @dev RadiantStaking is the main contract that enables user zap into DLP position on behalf on user to get boosted yield and vote.
///         RadiantStaking is the main contract interacting with Radiant Finance side
/// @author Magpie Team

contract RadiantStaking is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IRadiantStaking
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ============ Structs ============ */

    struct Pool {
        address asset; // asset on Radiant
        address rToken;
        address vdToken;
        address rewarder;
        address receiptToken;
        uint256 maxCap; // max receipt token amount
        uint256 lastActionHandled; // timestamp of ActionHandled trigged on Radiant ChefIncentive
        bool isNative;
        bool isActive;
    }

    /* ============ State Variables ============ */

    // Addresses
    address public wETH; // WETH = ARB / WBNB = BNB
    address public rdnt;
    address public rdntWethLp;
    address public mDLP;
    address public masterRadpie;
    address public assetLoopHelper;

    address public aaveOracle;
    ILockZap public lockZap;
    ILeverager public leverager;
    ILendingPool public lendingPool;
    IMultiFeeDistribution public multiFeeDistributor;

    uint256 public harvestTimeGap;
    uint256 public lastHarvestTime;

    mapping(address => Pool) public pools;
    address[] public poolTokenList;
    address[] public poolRTokenList;

    uint256 constant DENOMINATOR = 10000;

    /* ========= 1st upgrade ========= */

    IChefIncentivesController public chefIncentivesController;
    IEligibilityDataProvider public eligibilityDataProvider;
    IWETHGateway public wethGateway;

    address public rdntRewardManager;
    address public rdntVestManager;
    address public rewardDistributor;
    mapping(address => bool) public isAssetRegistered;

    uint256 public lastActionHandledCooldown;
    uint256 public lastSeenClaimableRDNT;
    uint256 public lastSeenClaimableTime;
    uint256 public constant WAD = 10 ** 18;
    uint256 public minHealthFactor;
    uint256 public totalEarnedRDNT;

    /* ============ Events ============ */

    // Admin
    event PoolAdded(address _asset, address _rewarder, address _receiptToken);
    event PoolRemoved(uint256 _pid, address _lpToken);
    event PoolHelperUpdated(address _lpToken);
    event FullyDeleverage(uint256 _poolLength, address _caller);

    event NewAssetDeposit(
        address indexed _user,
        address indexed _asset,
        uint256 _assetAmount,
        address indexed _receptToken,
        uint256 _receiptAmount
    );

    event NewAssetWithdraw(
        address indexed _user,
        address indexed _asset,
        uint256 _assetAmount,
        address indexed _receptToken,
        uint256 _receptAmount
    );

    event StreamingFeeRecipientUpdated(address _newFeeRecipient);
    event StreamingFeeActualized(address indexed receipttoken, uint256 _managerRecievedFee);    

    /* ============ Errors ============ */

    error OnlyPoolHelper();
    error OnlyActivePool();
    error TimeGapTooMuch();
    error InvalidAddress();
    error OnlyRDNTManager();
    error ExceedsMaxCap();
    error StillGoodState();
    error ETHTransferFailed();
    error AlreadyRegistered();
    error onlyStreamingFeeManager();

    /* ============ Constructor ============ */

    function __RadiantStaking_init(
        address _wETH,
        address _rdnt,
        address _rdntWethLp,
        address _aaveOracle,
        address _lockZap,
        address _leverager,
        address _lendingPool,
        address _multiFeeDistributor,
        address _masterRadpie
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        wETH = _wETH;
        rdnt = _rdnt;
        rdntWethLp = _rdntWethLp;
        masterRadpie = _masterRadpie;
        aaveOracle = _aaveOracle;
        lockZap = ILockZap(_lockZap);
        leverager = ILeverager(_leverager);
        lendingPool = ILendingPool(_lendingPool);
        multiFeeDistributor = IMultiFeeDistribution(_multiFeeDistributor);
        lastHarvestTime = block.timestamp;
        minHealthFactor = WAD;
    }

    receive() external payable {}

    /* ============ Modifiers ============ */

    modifier _onlyPoolHelper(address _asset) {
        if (msg.sender != assetLoopHelper) revert OnlyPoolHelper();
        _;
    }

    modifier _onlyActivePool(address _asset) {
        Pool storage poolInfo = pools[_asset];

        if (!poolInfo.isActive) revert OnlyActivePool();
        _;
    }

    modifier _onlyActivePoolHelper(address _asset) {
        Pool storage poolInfo = pools[_asset];

        if (msg.sender != assetLoopHelper) revert OnlyPoolHelper();
        if (!poolInfo.isActive) revert OnlyActivePool();
        _;
    }

    modifier _onlyRDNTManager() {
        if (rdntRewardManager == address(0)) revert InvalidAddress();
        if (msg.sender != rdntRewardManager) revert OnlyRDNTManager();
        _;
    }

    /* ============ Radiant Related External View Functions ============ */

    function poolLength() external view returns (uint256) {
        return poolTokenList.length;
    }

    function systemHealthFactor() external view returns (uint256 healthFactor) {
        (, , , , , healthFactor) = lendingPool.getUserAccountData(address(this));
    }

    /* ============ Radiant Related External Functions ============ */

    /// @dev Deposit and lopp the asset based on current health factor of the asset.
    /// (i.e) health factor of the asset should remain the same before and after the deposit (and loop).
    function depositAssetFor(
        address _asset,
        address _for,
        uint256 _assetAmount
    ) external payable whenNotPaused nonReentrant _onlyActivePoolHelper(_asset) {
        Pool storage poolInfo = pools[_asset];

        // we need to calculate share before changing r, vd Token balance
        uint256 shares = (_assetAmount * WAD) /
            IRadpieReceiptToken(poolInfo.receiptToken).assetPerShare();
        // only direct deposit should be considered for max cap
        if (
            poolInfo.maxCap != 0 &&
            IERC20(poolInfo.receiptToken).totalSupply() + shares > poolInfo.maxCap
        ) revert ExceedsMaxCap();

        uint256 rTokenPrevBal = IERC20(poolInfo.rToken).balanceOf(address(this));
        RadiantUtilLib._depositHelper(
            wethGateway,
            lendingPool,
            _asset,
            poolInfo.vdToken,
            _assetAmount,
            poolInfo.isNative,
            false
        );
        uint256 vdTokenBal = IERC20(poolInfo.vdToken).balanceOf(address(this));

        if (rTokenPrevBal != 0) {
            // calculate target vd balance to start looping, target vd is calculated based on health factor for this asset should be consistent before and after looping
            uint256 targetVD = ((vdTokenBal * _assetAmount) / (rTokenPrevBal - vdTokenBal));
            targetVD += vdTokenBal;
            (address[] memory _assetToLoop, uint256[] memory _targetVDs) = RadiantUtilLib.loopData(
                _asset,
                targetVD
            );

            _loop(_assetToLoop, _targetVDs);
        }

        _checkSystemGoodState(true, true);

        IMintableERC20(poolInfo.receiptToken).mint(_for, shares);

        emit NewAssetDeposit(_for, _asset, _assetAmount, poolInfo.receiptToken, shares);
    }

    /// @dev Withdraw and partial repay asset. partial return to the user.
    /// (i.e) health factor of the asset should remain the same before and after the withdraw.
    /// Collateral will reduce more than what user's withdraw request to repay debts.
    /// _shares is the amount of receipt token.
    function withdrawAssetFor(
        address _asset,
        address _for,
        uint256 _shares
    ) external whenNotPaused nonReentrant _onlyPoolHelper(_asset) {
        Pool storage poolInfo = pools[_asset];

        uint256 assetToReturn = (_shares *
            IRadpieReceiptToken(poolInfo.receiptToken).assetPerShare()) / WAD;
        uint256 targetVD = RadiantUtilLib.calWithdraw(
            poolInfo.rToken,
            poolInfo.vdToken,
            address(this),
            assetToReturn
        );

        (address[] memory _assetToWithdraws, uint256[] memory _targetVDs) = RadiantUtilLib.loopData(
            _asset,
            targetVD
        );
        _deleverage(_assetToWithdraws, _targetVDs);

        uint256 assetRecAmount = RadiantUtilLib._safeWithdrawAsset(
            wethGateway,
            lendingPool,
            _asset,
            poolInfo.rToken,
            assetToReturn,
            poolInfo.isNative
        );

        _checkSystemGoodState(true, false);

        IMintableERC20(poolInfo.receiptToken).burn(_for, _shares);

        if (poolInfo.isNative) {
            (bool success, ) = payable(_for).call{ value: assetRecAmount }("");
            if (!success) revert ETHTransferFailed();
        } else IERC20(_asset).safeTransfer(_for, assetRecAmount);

        emit NewAssetWithdraw(_for, _asset, assetRecAmount, poolInfo.receiptToken, _shares);
    }

    /* ============ Radiant Rewards Related Functions ============ */

    /// @dev harvest a rTokens except for RDNT token
    function batchHarvestDlpRewards() external whenNotPaused {
        _harvestDlpRewards(true);
    }

    /// @dev to update RDNT reward from chefIncentivesController for all rToken and vdToken of Radpie
    /// Radpie vest Clamable RDNT from Radiant every other 10 days, so shares of RDNT distributed to user
    /// should be cacculated based on diff of chefIncentivesController.userBaseClaimable before and after summing pending reward into
    /// userBaseClaimable on Radiant side.
    /// To make sure accurate reward distribution and prevent yield sandwitch attack, RDNT reward no matter from
    /// What rToken, vdToken are always redistributed based on the weight cacculted by looping effect and RDNT emission
    /// for that token.
    function batchHarvestEntitledRDNT(bool _force) external whenNotPaused {
        for (uint256 i = 0; i < poolTokenList.length; i++) {
            Pool storage poolInfo = pools[poolTokenList[i]];

            if (!poolInfo.isActive) continue;

            // To make pending reward goes to userBaseClaimable storage on chefIncentivesController on Radiant
            if (
                _force || block.timestamp > poolInfo.lastActionHandled + lastActionHandledCooldown
            ) {
                // trigger handleActionAfter for rToken on Radiant ChefIncentivesController
                IERC20(poolInfo.rToken).transfer(address(this), 0);

                // trigger handleActionAfter for vdToken on Radiant ChefIncentivesController
                if (IERC20(poolInfo.vdToken).balanceOf(address(this)) > 0)
                    lendingPool.borrow(poolTokenList[i], 1, 2, 0, address(this));

                poolInfo.lastActionHandled = block.timestamp;
            }
        }

        uint256 updatedClamable = chefIncentivesController.userBaseClaimable(address(this));
        totalEarnedRDNT += (updatedClamable - lastSeenClaimableRDNT);

        IRewardDistributor(rewardDistributor).enqueueRDNT(
            poolTokenList,
            lastSeenClaimableRDNT,
            updatedClamable
        );

        lastSeenClaimableTime = block.timestamp;
        lastSeenClaimableRDNT = updatedClamable;
    }

    /// @dev to start vesting for all current claimable RDNT.
    function vestAllClaimableRDNT() external _onlyRDNTManager {
        this.batchHarvestEntitledRDNT(true); // need to make sure pending RDNT reward were all updated into baseClaimmable on Radiant.
        IChefIncentivesController(chefIncentivesController).claimAll(address(this));
        lastSeenClaimableRDNT = 0; // reset lastseen because base claimable on Radiant is claimed
    }

    /// @dev to claim vested RDNT and send to RDNTVestManager for users to claim
    function claimVestedRDNT() external _onlyRDNTManager {
        uint256 rdntBal = IERC20(rdnt).balanceOf(address(this));
        (, uint256 totalAmount, ) = multiFeeDistributor.earnedBalances(address(this));
        multiFeeDistributor.withdraw(totalAmount);
        IERC20(rdnt).safeTransfer(
            address(rdntVestManager),
            IERC20(rdnt).balanceOf(address(this)) - rdntBal
        );
    }

    /* ============ Admin Functions ============ */

    /// @dev to loop given assets of Radpie on Radiant. target vdToken balance basically determines looping and health factor,
    /// which should be calculated off chain.
    /// This function should be called by admin for leverage position management.
    function loop(
        address[] memory _assets,
        uint256[] memory _targetVdBal
    ) external nonReentrant onlyOwner {
        _loop(_assets, _targetVdBal);
        _checkSystemGoodState(true, true);
    }

    /// @dev to deleverage given assets of Radpie on Radiant. target vdToken balance basically determines health factor,
    /// which should be calculated off chain.
    /// This function should be called by admin for leverage position management.
    function deleverage(
        address[] memory _assets,
        uint256[] memory _targetVdBal
    ) external nonReentrant onlyOwner {
        _deleverage(_assets, _targetVdBal);
        _checkSystemGoodState(true, false);
    }

    /// @dev when Radpie lost RDNT eligibility or health factor dropped too low, anyone and trigger this function
    ///      to fully deleverage all Radpie position on Radiant (i.e. no debt)
    function fullyDeleverage() external nonReentrant {
        if (_checkSystemGoodState(false, true)) revert StillGoodState();

        uint256[] memory allZeroTargetVd = new uint256[](poolTokenList.length);
        _deleverage(poolTokenList, allZeroTargetVd);

        emit FullyDeleverage(poolTokenList.length, msg.sender);
    }

    function registerPool(
        address _asset,
        address _rToken,
        address _vdToken,
        uint256 _allocPoints,
        uint256 _maxCap,
        bool _isNative,
        string memory name,
        string memory symbol
    ) external onlyOwner {
        if (isAssetRegistered[_asset]) revert AlreadyRegistered();

        IERC20 newToken = IERC20(
            RadpieFactoryLib.createReceipt(
                IERC20Metadata(_asset).decimals(),
                _asset,
                address(this),
                masterRadpie,
                name,
                symbol
            )
        );

        address rewarder = RadpieFactoryLib.createRewarder(
            address(newToken),
            address(_asset),
            address(masterRadpie),
            rewardDistributor
        );

        IRDNTRewardManager(rdntRewardManager).addRegisteredReceipt(address(newToken));

        IMasterRadpie(masterRadpie).add(
            _allocPoints,
            address(_asset),
            address(newToken),
            address(rewarder)
        );

        pools[_asset] = Pool({
            asset: _asset,
            rToken: _rToken,
            vdToken: _vdToken,
            receiptToken: address(newToken),
            rewarder: address(rewarder),
            maxCap: _maxCap,
            lastActionHandled: 0,
            isNative: _isNative,
            isActive: true
        });

        isAssetRegistered[_asset] = true;

        poolTokenList.push(_asset);
        poolRTokenList.push(_rToken);

        emit PoolAdded(_asset, address(rewarder), address(newToken));
    }

    function accrueStreamingFee(address _receiptToken) external nonReentrant onlyOwner {
        uint256 feeQuantity; 

        if (IRewardDistributor(rewardDistributor).streamingFeePercentage(_receiptToken) > 0) {
            uint256 inflationFeePercentage = IRewardDistributor(rewardDistributor).getCalculatedStreamingFeePercentage(_receiptToken);
            feeQuantity = IRewardDistributor(rewardDistributor).calculateStreamingFeeInflation(_receiptToken, inflationFeePercentage);
            IMintableERC20(_receiptToken).mint(owner(), feeQuantity);
        }

        IRewardDistributor(rewardDistributor).updatelastStreamingLastFeeTimestamp(_receiptToken, block.timestamp);

        emit StreamingFeeActualized(_receiptToken, feeQuantity);
    }        

    function updatePool(address _asset, uint256 _maxCap, bool _isActive) external onlyOwner {
        Pool storage poolInfo = pools[_asset];
        poolInfo.maxCap = _maxCap;
        poolInfo.isActive = _isActive;
    }

    function config(
        address _wethGateway,
        address _chefIncentivesController,
        address _eligibilityDataProvider,
        address _mDLP,
        address _assetLoopHelper,
        address _rdntRewardManager,
        address _rdntVestManager,
        address _rewardDistributor
    ) external onlyOwner {
        wethGateway = IWETHGateway(_wethGateway);
        chefIncentivesController = IChefIncentivesController(_chefIncentivesController);
        eligibilityDataProvider = IEligibilityDataProvider(_eligibilityDataProvider);
        assetLoopHelper = _assetLoopHelper;
        mDLP = _mDLP;
        rdntRewardManager = _rdntRewardManager;
        rdntVestManager = _rdntVestManager;
        rewardDistributor = _rewardDistributor;
    }

    function setMinHealthFactor(uint256 _minHealthFactor) external onlyOwner {
        minHealthFactor = _minHealthFactor;
    }

    /**
     * @dev pause Radiant staking, restricting certain operations
     */
    function pause() external nonReentrant onlyOwner {
        _pause();
    }

    /**
     * @dev unpause radiant staking, enabling certain operations
     */
    function unpause() external nonReentrant onlyOwner {
        _unpause();
    }

    function setHarvestTimeGap(uint256 _period) external onlyOwner {
        if (_period > 4 hours) revert TimeGapTooMuch();

        harvestTimeGap = _period;
    }

    /**
     * @dev lock dlp on Radiant.
     * @dev This function allows users to lock LP tokens into the Radiant Protocol by providing liquidity.
     * @param _amount The amount of lp staking
     */
    function stakeLp(uint256 _amount) external whenNotPaused onlyOwner {
        if (_amount > 0) {
            _harvestDlpRewards(false); // need to update rewards for mdLP to make sure reward distribution fairness

            IERC20(rdntWethLp).safeApprove(address(multiFeeDistributor), _amount);
            multiFeeDistributor.stake(_amount, address(this), 3);
        }
    }

    /* ============ Internal Functions ============ */

    /// @dev to collect rTokens distributed to Radpie's locked dlp position on Radiant Capital.
    function _harvestDlpRewards(bool _force) internal nonReentrant {
        if (!_force && lastHarvestTime + harvestTimeGap > block.timestamp) return;
        (address[] memory rewardTokens, uint256[] memory amounts) = IRewardDistributor(
            rewardDistributor
        ).claimableDlpRewards();
        if (rewardTokens.length == 0 || amounts.length == 0) return;

        lastHarvestTime = block.timestamp;

        multiFeeDistributor.getReward(rewardTokens);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (amounts[i] == 0) continue;

            address rewardToken = rewardTokens[i];

            if (rewardTokens[i] != rdnt) {
                address asset = IAToken(rewardToken).UNDERLYING_ASSET_ADDRESS();
                ILendingPool(lendingPool).withdraw(asset, amounts[i], address(this));
                rewardToken = asset;
            }

            IERC20(rewardToken).safeApprove(rewardDistributor, amounts[i]);
            IRewardDistributor(rewardDistributor).sendRewards(
                address(mDLP),
                rewardToken,
                amounts[i]
            );
        }
    }

    /// @dev start loopig asset to target vdToken amount.
    /// Always borrow max before reaching target vdToken amount during looping.
    /// Need to harvest entitled RDNT since deposit triggers updating userBaseClaimable of Radpie on Radiant. User debt also needs
    /// to be updated for _user
    function _loop(address[] memory _assets, uint256[] memory _targetVdBal) internal {
        uint256 length = _assets.length;

        for (uint256 i = 0; i < length; i++) {
            if (_targetVdBal[i] != 0) {
                Pool storage poolInfo = pools[_assets[i]];
                RadiantUtilLib._loop(
                    lendingPool,
                    wethGateway,
                    poolInfo.asset,
                    poolInfo.rToken,
                    poolInfo.vdToken,
                    address(this),
                    _targetVdBal[i],
                    poolInfo.isNative
                );

                poolInfo.lastActionHandled = block.timestamp; // RDNT claimmable updated on Radiant ChefIncetiveContoller;
            }
        }
    }

    /// @notice deleverage looping to target vdToken amount.
    /// Always withdraw max and repay before reaching target vdToken amount during deleveraging
    /// Need to harvest entitled RDNT since withdraw triggers updating userBaseClaimable of Radpie on Radiant. User debt also needs
    /// to be updated for _user
    function _deleverage(address[] memory _assets, uint256[] memory _targetVdBal) internal {
        uint256 length = _assets.length;

        for (uint256 i = 0; i < length; i++) {
            Pool storage poolInfo = pools[_assets[i]];
            RadiantUtilLib._deleverage(
                lendingPool,
                wethGateway,
                poolInfo.asset,
                poolInfo.rToken,
                poolInfo.vdToken,
                address(this),
                _targetVdBal[i],
                poolInfo.isNative
            );

            poolInfo.lastActionHandled = block.timestamp; // RDNT claimmable updated on Radiant ChefIncetiveContoller;
        }
    }

    function _checkSystemGoodState(
        bool _doRevert,
        bool _eligibiltyCheck
    ) internal view returns (bool) {
        return
            RadiantUtilLib.checkGoodState(
                eligibilityDataProvider,
                lendingPool,
                address(this),
                minHealthFactor,
                _doRevert,
                _eligibiltyCheck
            );
    }
}

