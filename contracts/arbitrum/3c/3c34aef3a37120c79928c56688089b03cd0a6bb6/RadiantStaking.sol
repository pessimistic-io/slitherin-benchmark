// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import "./SafeMath.sol";

import "./IRadiantStaking.sol";
import "./IWETH.sol";
import "./IMDLP.sol";
import "./IMasterRadpie.sol";
import "./IBaseRewardPool.sol";
import "./IMintableERC20.sol";
import "./IRadiantAssetLoopHelper.sol";
import "./ILockZap.sol";
import "./IAToken.sol";
import "./ILeverager.sol";
import "./ILendingPool.sol";
import "./IFeeDistribution.sol";
import "./IMultiFeeDistribution.sol";
import "./ERC20FactoryLib.sol";
import "./ICreditDelegationToken.sol";

/// @title RadpieStaking
/// @notice RadpieStaking is the main contract that enables user zap into DLP position on behalf on user to get boosted yield and vote.
///         RadpieStaking is the main contract interacting with Radiant Finance side
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
        address asset;   // asset on Radiant
        address rToken;
        address vdToken;
        address delegate;
        address rewarder;
        address helper;
        address receiptToken;
        uint256 underlyingDeposited;
        bool isNative;
        bool isActive;
    }

    struct Fees {
        uint256 value; // allocation denominated by DENOMINATOR
        address to;
        bool isAddress;
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

    // Lp Fees
    uint256 constant DENOMINATOR = 10000;

    uint256 public totalRDNTFee; // total fee percentage for RDNT token reward
    uint256 public totalRTokenFee; // total fee percentage for revenue share reward (such as rWBTC, rWETH, rUSDC etc)
    Fees[] public radiantFeeInfos; // info of RDNT fee and destination
    Fees[] public rTokenFeeInfos; // info of rTokens fee and destination

    // zapDlp Fees
    // uint256 public zapHarvestCallerFee;
    // uint256 public protocolFee; // fee charged by penpie team for operation
    // address public feeCollector; // penpie team fee destination
    // address public bribeManagerEOA; // An EOA address to later user vePendle harvested reward

    /* ============ Events ============ */

    // Admin
    event PoolAdded(address _asset, address _rewarder, address _receiptToken);
    event PoolRemoved(uint256 _pid, address _lpToken);
    event PoolHelperUpdated(address _lpToken);
    event DustReturned(address indexed _to, address _token, uint256 _amount);

    // Fee
    event AddFee(address _to, uint256 _value, bool _isForRDNT, bool _isAddress);
    // event SetRadiantFee(address _to, uint256 _value);
    // event RemoveRadiantFee(uint256 value, address to, bool _isMDLP, bool _isAddress);
    event RewardPaidTo(address _asset, address _to, address _rewardToken, uint256 _feeAmount);
    event RewardFeeDustTo(address _reward, address _to, uint256 _amount);

    event NewAssetDeposit(
        address indexed _user,
        address indexed _asset,
        uint256 _lpAmount,
        address indexed _receptToken,
        uint256 _receptAmount
    );

    event NewAssetWithdraw(
        address indexed _user,
        address indexed _asset,
        uint256 _lpAmount,
        address indexed _receptToken,
        uint256 _receptAmount
    );

    /* ============ Errors ============ */

    error OnlyPoolHelper();
    error OnlyActivePool();
    error PoolOccupied();
    error InvalidFee();
    error LengthMismatch();
    error TimeGapTooMuch();
    error InvalidFeeDestination();
    error ZeroAmount();
    error InvalidAddress();

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
        harvestTimeGap = 1 hours;
    }

    receive() external payable {
        // Deposit ETH to WETH
        IWETH(wETH).deposit{ value: msg.value }();
    }

    /* ============ Modifiers ============ */

    modifier _onlyPoolHelper(address _asset) {
        Pool storage poolInfo = pools[_asset];

        if (msg.sender != poolInfo.helper) revert OnlyPoolHelper();
        _;
    }

    modifier _onlyActivePool(address _asset) {
        Pool storage poolInfo = pools[_asset];

        if (!poolInfo.isActive) revert OnlyActivePool();
        _;
    }

    modifier _onlyActivePoolHelper(address _asset) {
        Pool storage poolInfo = pools[_asset];

        if (msg.sender != poolInfo.helper) revert OnlyPoolHelper();
        if (!poolInfo.isActive) revert OnlyActivePool();
        _;
    }

    /* ============ Radiant Related External View Functions ============ */

    function getTotalLocked() external view returns (uint256) {
        (uint256 totalLocked, , , , ) = IMultiFeeDistribution(multiFeeDistributor).lockedBalances(
            address(this)
        );
        return totalLocked;
    }

    function claimableDlpRewards() external view returns (address[] memory _rewardTokens, uint256[] memory _amounts) {
        IFeeDistribution.RewardData[] memory rewards
            = IMultiFeeDistribution(multiFeeDistributor).claimableRewards(address(this));

        _rewardTokens = new address[](rewards.length);
        _amounts = new uint256[](rewards.length);

        for (uint256 i = 0; i < rewards.length; i++) {
            _rewardTokens[i] = rewards[i].token;
            _amounts[i] = rewards[i].amount;
        }
    }

    /* ============ Radiant Related External Functions ============ */

    // function loopAsset(
    //     address _asset,
    //     address _for,
    //     address _from,
    //     uint256 _amount,
    //     bool _isNative
    // ) external payable override nonReentrant whenNotPaused _onlyPoolHelper(_asset) {
    //     Pool storage poolInfo = pools[_asset];
    //     _harvestAssetRewards(poolInfo.asset, false);
    //     uint256 _borrowRatio = ILeverager(leverager).ltv(poolInfo.asset);
    //     ICreditDelegationToken(poolInfo.vdToken).approveDelegation(poolInfo.delegate, _amount);
    //     if (_isNative) {
    //         ILeverager(leverager).loopETH{ value: _amount }(2, _borrowRatio, 1);
    //     } else {
    //         IERC20(poolInfo.asset).safeTransferFrom(_from, address(this), _amount);
    //         IERC20(poolInfo.asset).approve(address(leverager), _amount);
    //         ILeverager(leverager).loop(poolInfo.asset, _amount, 2, _borrowRatio, 1, false);
    //     }
    //     poolInfo.underlyingDeposited = _amount;
    //     // mint the receipt to the user driectly
    //     IMintableERC20(poolInfo.receiptToken).mint(_for, _amount);

    //     emit NewAssetDeposit(_for, _asset, _amount, poolInfo.receiptToken, _amount);
    // }

    // function withdrawAsset(
    //     address _asset,
    //     address _for,
    //     uint256 _amount
    // ) external override nonReentrant whenNotPaused _onlyPoolHelper(_asset) {
    //     Pool storage poolInfo = pools[_asset];

    //     _harvestAssetRewards(poolInfo.asset, false);

    //     uint256 beforeWithdraw = IERC20(poolInfo.asset).balanceOf(address(this));
    //     ILendingPool(lendingPool).withdraw(poolInfo.rToken, _amount, address(this));
    //     IERC20(poolInfo.asset).safeTransfer(
    //         _for,
    //         IERC20(poolInfo.asset).balanceOf(address(this)) - beforeWithdraw
    //     );

    //     IMintableERC20(poolInfo.receiptToken).burn(_for, _amount);
    //     // emit New withdraw
    //     emit NewAssetWithdraw(_for, _asset, _amount, poolInfo.receiptToken, _amount);
    // }

    // /**
    //  * @notice Locks native tokens into the Radiant Protocol by providing liquidity
    //  * @dev This function allows users to lock native tokens into the Radiant Protocol by providing liquidity.
    //  * @param _for Refund address
    //  * @return _liquidity The amount of liquidity provided.
    //  */
    function zapNative(address _for) external payable whenNotPaused returns (uint256 _liquidity) {
        // if (msg.value == 0) revert ZeroAmount();

        // _harvestDlpRewards(false); // need to update rewards for mdLP to make sure reward distribution fairness

        // (uint256 rdntBal, uint256 wethBal) = _currentRdntWethBal();

        // _liquidity = ILockZap(lockZap).zap{ value: msg.value }(false, 0, 0, 3);

        // _refundRdntOrWeth(_for, rdntBal, wethBal);

        // return _liquidity;
    }

    /**
     * @notice Locks rdnt tokens into the Radiant Protocol by providing liquidity
     * @dev This function allows users to lock rdnt tokens into the Radiant Protocol by providing liquidity.
     * @param _amount The amount of rdnt Tokens
     */
    function zapRdnt(address _for, uint256 _amount) external payable whenNotPaused returns (uint256 _liquidity) {
        // (uint256 rdntBal, uint256 wethBal) = _currentRdntWethBal();

        // IERC20(rdnt).safeTransferFrom(msg.sender, address(this), _amount);
        // IERC20(rdnt).safeApprove(address(lockZap), _amount);

        // _harvestDlpRewards(false); // need to update rewards for mdLP to make sure reward distribution fairness

        // _liquidity = ILockZap(lockZap).zap{ value: msg.value }(false, 0, _amount, 3);

        // _refundRdntOrWeth(_for, rdntBal, wethBal);

        // return _liquidity;
    }

    // /// @notice harvest a Rewards from radiant Liquidity Pool
    // /// @param _asset Radiant Pool lp as helper identifier

    function batchHarvestDlpRewards() external whenNotPaused {
        _harvestDlpRewards(true);
    }

    /* ============ Admin Functions ============ */

    // function relockZap() external onlyOwner {
    //     IMultiFeeDistribution(multiFeeDistributor).setRelock(true);
    // }

    // open for now just to avoid more modification
    function registerPool(
        address _asset,
        address _rToken,
        address _vdToken,
        address _delegate,
        uint256 _allocPoints,
        bool _isNative,
        string memory name,
        string memory symbol
    ) external onlyOwner {
        if (pools[_asset].isActive != false) {
            revert PoolOccupied();
        }

        IERC20 newToken = IERC20(
            ERC20FactoryLib.createReceipt(_asset, masterRadpie, name, symbol)
        );

        address rewarder = IMasterRadpie(masterRadpie).createRewarder(
            address(newToken),
            address(_asset)
        );

        //IRadiantAssetLoopHelper(assetLoopHelper).setPoolInfo(_asset, rewarder, _isNative, true);

        IMasterRadpie(masterRadpie).add(
            _allocPoints,
            address(_asset),
            address(newToken),
            address(rewarder)
        );

        pools[_asset] = Pool({
            isActive: true,
            asset: _asset,
            rToken: _rToken,
            vdToken: _vdToken,
            delegate: _delegate,
            receiptToken: address(newToken),
            rewarder: address(rewarder),
            helper: assetLoopHelper,
            underlyingDeposited: 0,
            isNative: _isNative
        });
        poolTokenList.push(_asset);
        poolRTokenList.push(_rToken);

        emit PoolAdded(_asset, address(rewarder), address(newToken));
    }

    function setMasterRadpie(address _masterRadpie) external onlyOwner {
        if (_masterRadpie == address(0)) revert InvalidAddress();
        masterRadpie = _masterRadpie;
    }

    function setMDLP(address _mDlp) external onlyOwner {
        if (_mDlp == address(0)) revert InvalidAddress();
        mDLP = _mDlp;
    }

    function setAssetLoopHelper(address _assetLoopHelper) external onlyOwner {
        if (_assetLoopHelper == address(0)) revert InvalidAddress();
        assetLoopHelper = _assetLoopHelper;
    }

    /**
     * @notice pause Radiant staking, restricting certain operations
     */
    function pause() external nonReentrant onlyOwner {
        _pause();
    }

    /**
     * @notice unpause radiant staking, enabling certain operations
     */
    function unpause() external nonReentrant onlyOwner {
        _unpause();
    }

    // /// @notice This function adds a fee to the magpie protocol
    // /// @param _value the initial value for that fee
    // /// @param _to the address or contract that receives the fee
    // /// @param _isAddress true if the receiver is an address, otherwise it's a BaseRewarder
    function addFee(
        uint256 _value,
        address _to,
        bool _isForRDNT,
        bool _isAddress
    ) external onlyOwner {
        if (_value > DENOMINATOR) revert InvalidFee();

        if (_isForRDNT) {
            radiantFeeInfos.push(
                Fees({ value: _value, to: _to, isAddress: _isAddress, isActive: true })
            );
            totalRDNTFee += _value;
        } else {
            rTokenFeeInfos.push(
                Fees({ value: _value, to: _to, isAddress: _isAddress, isActive: true })
            );
            totalRTokenFee += _value;
        }

        emit AddFee(_to, _value, _isForRDNT, _isAddress);
    }

    function setHarvestTimeGap(uint256 _period) external onlyOwner {
        if (_period > 4 hours) revert TimeGapTooMuch();

        harvestTimeGap = _period;
    }

    /**
     * @notice Locks native tokens into the Radiant Protocol by providing liquidity
     * @dev This function allows users to lock LP tokens into the Radiant Protocol by providing liquidity.
     * @param _amount The amount of lp staking
     */
    function stakeLp(uint256 _amount) external whenNotPaused onlyOwner {
        if (_amount > 0) {
            _harvestDlpRewards(false); // need to update rewards for mdLP to make sure reward distribution fairness

            IERC20(rdntWethLp).safeApprove(address(multiFeeDistributor), _amount);
            IMultiFeeDistribution(multiFeeDistributor).stake(_amount, address(this), 3);
        }
    }    

    // /// @notice change the value of some fee
    // /// @dev the value must be between the min and the max specified when registering the fee
    // /// @dev the value must match the max fee requirements
    // /// @param _index the index of the fee in the fee list
    // /// @param _value the new value of the fee
    // function setRadiantFee(
    //     uint256 _index,
    //     uint256 _value,
    //     address _to,
    //     bool _isMDLP,
    //     bool _isAddress,
    //     bool _isActive
    // ) external onlyOwner {
    //     if (_value > DENOMINATOR) revert InvalidFee();

    //     Fees storage fee = radiantFeeInfos[_index];
    //     fee.to = _to;
    //     fee.isMDLP = _isMDLP;
    //     fee.isAddress = _isAddress;
    //     fee.isActive = _isActive;

    //     totalRadiantFee = totalRadiantFee - fee.value + _value;
    //     fee.value = _value;

    //     emit SetRadiantFee(fee.to, _value);
    // }

    // /// @notice remove some fee
    // /// @param _index the index of the fee in the fee list
    // function removeRadiantFee(uint256 _index) external onlyOwner {
    //     Fees memory feeToRemove = radiantFeeInfos[_index];

    //     for (uint i = _index; i < radiantFeeInfos.length - 1; i++) {
    //         radiantFeeInfos[i] = radiantFeeInfos[i + 1];
    //     }
    //     radiantFeeInfos.pop();
    //     totalRadiantFee -= feeToRemove.value;

    //     emit RemoveRadiantFee(
    //         feeToRemove.value,
    //         feeToRemove.to,
    //         feeToRemove.isMDLP,
    //         feeToRemove.isAddress
    //     );
    // }

    // /* ============ Internal Functions ============ */

    function _harvestDlpRewards(bool _force) internal nonReentrant {
        if (!_force && lastHarvestTime + harvestTimeGap > block.timestamp ) return;
        (address[] memory rewardTokens, uint256[] memory amounts) = this.claimableDlpRewards();
        if (rewardTokens.length == 0 || amounts.length == 0) return;

        lastHarvestTime = block.timestamp;

        IMultiFeeDistribution(multiFeeDistributor).getReward(rewardTokens);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (amounts[i] == 0 || rewardTokens[i] == rdnt) continue; // skipping RDNT for now since it's not rToken

            address asset = IAToken(rewardTokens[i]).UNDERLYING_ASSET_ADDRESS();
            ILendingPool(lendingPool).withdraw(asset, amounts[i], address(this));

            _sendRewards(address(mDLP), asset, amounts[i]);
        }
    }

    // /// @notice Send rewards to the rewarders
    // /// @param _asset the radiant asset
    // /// @param _rewardToken the address of the reward token to send
    // /// @param _amount the reward amount to send
    function _sendRewards(address _asset, address _rewardToken, uint256 _amount) internal {
        if (_amount == 0) return;
        Fees[] storage feeInfos;

        if (_rewardToken == address(rdnt)) feeInfos = radiantFeeInfos;
        else feeInfos = rTokenFeeInfos;

        for (uint256 i = 0; i < feeInfos.length; i++) {
            Fees storage feeInfo = feeInfos[i];
            if (!feeInfo.isActive) continue;

            _enqueueRewards(
                _asset,
                _rewardToken,
                _amount,
                feeInfo.value,
                feeInfo.to,
                feeInfo.isAddress
            );
        }

        // if there is somehow reward left, sent it to owner
        uint256 rewardLeft = IERC20(_rewardToken).balanceOf(address(this));
        if (rewardLeft > _amount) {
            IERC20(_asset).safeTransfer(owner(), rewardLeft - _amount);
            emit RewardFeeDustTo(_rewardToken, owner(), rewardLeft - _amount);
        }

    }

    // to enqure the reward to a baseRewarder to an address
    function _enqueueRewards(
        address _asset,
        address _rewardToken,
        uint256 _originalRewardAmount,
        uint256 _value,
        address _to,
        bool _toIsAddress
    ) internal {
        address rewardToken = _rewardToken;
        uint256 feeAmount = (_originalRewardAmount * _value) / DENOMINATOR;
        uint256 feeTosend = feeAmount;

        if (!_toIsAddress) {
            IERC20(rewardToken).safeApprove(_to, feeTosend);
            IBaseRewardPool(_to).queueNewRewards(feeTosend, rewardToken);
        } else {
            IERC20(rewardToken).safeTransfer(_to, feeTosend);
        }

        emit RewardPaidTo(_asset, _to, rewardToken, feeTosend);
    }

    function _refundRdntOrWeth(address _dustTo, uint256 _rdntBeforeBal, uint256 _wethBeforeBal) internal {
        (uint256 rdntBal, uint256 wethBal) = _currentRdntWethBal();

        uint256 returnedRdnt = rdntBal - _rdntBeforeBal;
        if (returnedRdnt > 0) {
            IERC20(rdnt).safeTransfer(_dustTo, returnedRdnt);
            emit DustReturned(_dustTo, rdnt, returnedRdnt);
        }

        uint256 returnedWeth = wethBal - _wethBeforeBal;
        if (returnedWeth > 0) {
            IERC20(wETH).safeTransfer(_dustTo, returnedWeth);
            emit DustReturned(_dustTo, wETH, returnedWeth);
        }
    }

    function _currentRdntWethBal() internal view returns(uint256 rdntBal, uint256 wethBal) {
        return (IERC20(rdnt).balanceOf(address(this)), IERC20(wETH).balanceOf(address(this)));
    }
}

