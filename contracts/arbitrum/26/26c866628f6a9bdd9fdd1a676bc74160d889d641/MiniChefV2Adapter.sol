// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import {ICompoundStrategy} from "./ICompoundStrategy.sol";
import {ILP} from "./ILP.sol";
import {IFarm} from "./IFarm.sol";
import {ISwap} from "./ISwap.sol";

import {IRouter} from "./IRouter.sol";
import {OperableKeepable, Governable} from "./OperableKeepable.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IAggregatorV3} from "./interfaces_IAggregatorV3.sol";
import {IMasterChefV2, MasterChefStructs, IRewarder} from "./IMasterChefV2.sol";
import {AssetsPricing} from "./AssetsPricing.sol";
import {ILpsRegistry} from "./LpsRegistry.sol";

contract MiniChefV2Adapter is IFarm, OperableKeepable {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    // @notice Info needed to perform a swap
    struct SwapData {
        // @param Swapper used
        ISwap swapper;
        // @param Encoded data we are passing to the swap
        bytes data;
    }

    // @notice Stack too deep
    struct ClaimStakeData {
        IERC20 extraToken;
        IERC20 sushi;
        address here;
        uint256 _pid;
        ISwap defaultSwapper_;
        address swapper;
        uint256 sushiBalance;
        uint256 extraTokenBalance;
        ISwap.SwapData rewardTokenToWeth;
        ISwap.SwapData sushiToWeth;
        uint256 wethAmount;
        address incentiveReceiver;
        uint256 compoundRetention;
        uint256 retention;
        ISwap.SwapData data;
        ISwap.SwapInfo swapInfo;
        uint256 lpBalance;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    // @notice Internal representation of 100%
    uint256 private constant BASIS = 1e12;

    // @notice MiniChefV2 ABI
    IMasterChefV2 public constant farm = IMasterChefV2(0xF4d73326C13a4Fc5FD7A064217e12780e9Bd62c3);

    // @notice SUSHI token (emited in MiniChefV2 farms)
    IERC20 public constant SUSHI = IERC20(0xd4d42F0b6DEF4CE0383636770eF773390d85c61A);

    // @notice Wrapped ETH, base asset of LPs
    IERC20 public constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // @notice Default swapper set in constructor = sushi
    ISwap public defaultSwapper;

    // @notice Default slippage used in swaps
    uint256 public defaultSlippage;

    ILpsRegistry private lpsRegistry;

    // @notice Pool identification for the systems LP token farm
    uint256 public pid;

    // @notice Underlying Metavault LP token
    IERC20 public lp;

    // @notice Pair adapter responsible mostly for build/break LP logic
    ILP public lpAdapter;

    // @notice Extra token emitted by some MinichefV2 farms.
    // If current farm doesnt have it, itll be set as address 0.
    IERC20 public rewardToken;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initializeFarm(
        uint256 _pid,
        address _lp,
        address _lpAdapter,
        address _rewardToken,
        address _lpsRegistry,
        address _defaultSwapper,
        uint256 _defaultSlippage
    ) external initializer {
        if (_lp == address(0) || _defaultSwapper == address(0)) {
            revert ZeroAddress();
        }

        pid = _pid;
        lp = IERC20(_lp);
        lpAdapter = ILP(_lpAdapter);
        rewardToken = IERC20(_rewardToken);
        defaultSwapper = ISwap(_defaultSwapper);
        lpsRegistry = ILpsRegistry(_lpsRegistry);

        defaultSlippage = _defaultSlippage;

        __Governable_init(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                                ONLY OPERATOR                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Stake LP token from strategy.
     * @param _amount Value to stake.
     */
    function stake(uint256 _amount) external onlyOperator {
        address thisAddress = address(this);

        // Transfer the LP from the strategy to address(this)
        lp.safeTransferFrom(msg.sender, thisAddress, _amount);
        // Approve farm can we save this??
        lp.approve(address(farm), _amount);

        // Deposit for itself
        farm.deposit(pid, _amount, thisAddress);

        emit Stake(msg.sender, pid, _amount);
    }

    /**
     * @notice Unstake LP token and send to receiver.
     * @param _amount Value to stake.
     * @param _receiver Who will receive the LP.
     */
    function unstake(uint256 _amount, address _receiver) external onlyOperator {
        // Withdraw the LP tokens from Farm ands send to receiver
        farm.withdraw(pid, _amount, _receiver);
        emit UnStake(_receiver, pid, _amount);
    }

    /**
     * @notice Claim farm Rewards.
     * @param _receiver Who will receive the Rewards.
     */
    function claim(address _receiver) external onlyOperator {
        // Get the farm rewards
        farm.harvest(pid, _receiver);
        emit Harvest(_receiver, pid);
    }

    /**
     * @notice Claim yield, transform into LP and stake
     * @return Amount of LP tokens staked
     */
    function claimAndStake(IRouter router) external onlyOperator returns (uint256) {
        ClaimStakeData memory data;

        data.extraToken = rewardToken;
        data.sushi = SUSHI;
        data.here = address(this);
        data._pid = pid;

        // Review rewards
        try farm.pendingSushi(data._pid, data.here) returns (uint256 pendingSushi) {
            if (pendingSushi > 0) {
                // Get the farm rewards
                farm.harvest(data._pid, data.here);
                emit Harvest(data.here, data._pid);
            } else {
                return 0;
            }
        } catch {
            return 0;
        }

        data.defaultSwapper_ = defaultSwapper;

        // Approvals
        data.swapper = address(data.defaultSwapper_);

        // Get balances after harvesting
        data.sushiBalance = data.sushi.balanceOf(data.here);

        if (data.sushiBalance > 1e18) {
            // Not all farms emit a token besides sushi as reward
            if (address(data.extraToken) != address(0) && data.extraToken.balanceOf(address(this)) > 0) {
                data.extraTokenBalance = data.extraToken.balanceOf(data.here);
                data.extraToken.approve(data.swapper, data.extraTokenBalance);

                // Reward Token -> WETH. Amount out is calculated in the swapper
                data.rewardTokenToWeth =
                    ISwap.SwapData(address(data.extraToken), address(WETH), data.extraTokenBalance, defaultSlippage, "");

                data.extraToken.approve(data.swapper, data.extraTokenBalance);

                data.defaultSwapper_.swap(data.rewardTokenToWeth);
            }

            // Build transactions struct to pass in the batch swap
            // SUSHI -> WETH. Amount out is calculated in the swapper
            data.sushiToWeth =
                ISwap.SwapData(address(data.sushi), address(WETH), data.sushiBalance, defaultSlippage, "");

            // Swap sushi to WETH
            data.sushi.approve(data.swapper, data.sushiBalance);

            data.defaultSwapper_.swap(data.sushiToWeth);

            // Received WETH after swapping
            data.wethAmount = WETH.balanceOf(address(this));

            (data.incentiveReceiver,, data.compoundRetention) = router.incentives();

            data.retention = data.wethAmount.mulDivDown(data.compoundRetention, BASIS);

            // Send retention to receiver
            WETH.safeTransfer(data.incentiveReceiver, data.retention);

            data.wethAmount = data.wethAmount - data.retention;

            // Send to pair adapter to build the lp tokens
            WETH.safeTransfer(address(lpAdapter), data.wethAmount);

            // Struct to add LP and swap the WETH to underlying tokens of the LP token
            data.data;

            data.swapInfo = ISwap.SwapInfo({swapper: data.defaultSwapper_, data: data.data});

            // After building, execute the LP build and receive
            data.lpBalance = lpAdapter.buildLP(data.wethAmount, data.swapInfo);

            // After receiving the LP, stake into the farm
            lp.approve(address(farm), data.lpBalance);

            farm.deposit(data._pid, data.lpBalance, data.here);

            emit Stake(data.here, data._pid, data.lpBalance);

            return data.lpBalance;
        } else {
            return 0;
        }
    }

    /**
     * @notice Gets yield, convert to WETH and build LP
     * @dev Supposed to be used only if updating farm
     */
    function exit() external onlyOperator {
        // Load extra token
        IERC20 extraToken = rewardToken;
        IERC20 sushi = SUSHI;

        address here = address(this);
        // Get the farm rewards
        farm.harvest(pid, here);

        // Sushi balance after harvest
        uint256 sushiBalance = sushi.balanceOf(address(here));

        emit Harvest(here, pid);

        ISwap defaultSwapper_ = defaultSwapper;

        // Approvals
        address swapper = address(defaultSwapper_);

        sushi.approve(swapper, sushiBalance);

        // Build transactions struct to pass in the batch swap
        ISwap.SwapData memory sushiToWeth =
            ISwap.SwapData(address(sushi), address(WETH), sushiBalance, defaultSlippage, "");

        // Swap sushi & other token to WETH
        defaultSwapper_.swap(sushiToWeth);

        // Not all farms emit a token besides sushi as reward
        if (address(extraToken) != address(0) && extraToken.balanceOf(address(this)) > 0) {
            uint256 extraTokenBalance = extraToken.balanceOf(here);
            extraToken.approve(swapper, extraTokenBalance);

            // Reward Token -> WETH. Amount out is calculated in the swapper
            ISwap.SwapData memory rewardTokenToWeth =
                ISwap.SwapData(address(extraToken), address(WETH), extraTokenBalance, defaultSlippage, "");

            extraToken.approve(swapper, extraTokenBalance);

            defaultSwapper.swap(rewardTokenToWeth);
        }

        uint256 wethAmount = WETH.balanceOf(address(this));

        WETH.safeTransfer(address(lpAdapter), wethAmount);

        ISwap.SwapData memory data;

        ISwap.SwapInfo memory swapInfo = ISwap.SwapInfo({swapper: defaultSwapper_, data: data});

        uint256 lpOutput = lpAdapter.buildLP(wethAmount, swapInfo);

        lp.safeTransfer(msg.sender, lpOutput);

        emit Exit(msg.sender, lpOutput);
    }

    /* -------------------------------------------------------------------------- */
    /*                                     VIEW                                   */
    /* -------------------------------------------------------------------------- */

    function pendingRewards() external view returns (address[] memory, uint256[] memory) {
        return _pendingRewards();
    }

    /**
     * @notice Gets pending rewards tokens and convert it to LP
     * @return Amount of LP we would receive by exchanging tokens to LP
     */
    function pendingRewardsToLP() external view returns (uint256) {
        (address[] memory assets, uint256[] memory amounts) = _pendingRewards();

        uint256 wethAmount;
        uint256 length = assets.length;
        address weth = address(WETH);

        for (uint256 i; i < length;) {
            // asset to ETH
            wethAmount = assets[i] != weth && amounts[i] > 0
                ? wethAmount + _assetToETH(assets[i], amounts[i])
                : wethAmount + amounts[i];

            unchecked {
                ++i;
            }
        }

        // If the yield position is worth > 0 WETH, simulate how much LP its worth
        return wethAmount > 0 ? lpAdapter.ETHtoLP(wethAmount) : 0;
    }

    /**
     * @notice Sushi rewards our pool can receive
     */
    function earned() external view returns (uint256) {
        return uint256(farm.userInfo(pid, address(this)).rewardDebt);
    }

    /**
     * @notice Amount of LP tokens deposited in the LP farm
     */
    function balance() external view returns (uint256) {
        return uint256(farm.userInfo(pid, address(this)).amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    // Rescue lost tokens
    function rescue(IERC20 _token, uint256 _amount, address _to) external onlyGovernor {
        _token.safeTransfer(_to, _amount);
    }

    function addNewStrategy(uint256 _pid, address _lp, address _rewardToken) external onlyGovernor {
        // Some checks
        if (_lp == address(0)) {
            revert ZeroAddress();
        }

        pid = _pid;
        lp = IERC20(_lp);
        rewardToken = IERC20(_rewardToken);
    }

    function updateDefaultSwapper(address _swapper) external onlyGovernor {
        // Some checks
        if (_swapper == address(0)) {
            revert ZeroAddress();
        }

        defaultSwapper = ISwap(_swapper);
        WETH.approve(_swapper, type(uint256).max);
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative) external onlyGovernor {
        uint256 assetsLength = _assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                asset.safeTransfer(_to, assetBalance);
            }

            unchecked {
                ++i;
            }
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert FailSendETH();
            }
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    function updateLPAdapter(address _lp) external onlyGovernor {
        if (_lp == address(0)) {
            revert ZeroAddress();
        }

        lpAdapter = ILP(_lp);
    }

    /* -------------------------------------------------------------------------- */
    /*                                     PRIVATE                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets pending yield tokens and amounts
     */
    function _pendingRewards() private view returns (address[] memory, uint256[] memory) {
        uint256 _pid = pid;
        uint256 pendingSushi = farm.pendingSushi(_pid, address(this));

        // Sushi rewards distributor for the given PID
        IRewarder rewarder = farm.rewarder(_pid);

        if (address(rewarder) != address(0)) {
            (IERC20[] memory tokens, uint256[] memory rewards) =
                rewarder.pendingTokens(_pid, address(this), pendingSushi);

            uint256 length = rewards.length;

            address[] memory tokenAddresses = new address[](length + 1);
            uint256[] memory rewardAmounts = new uint256[](length + 1);

            for (uint256 i = 0; i < length;) {
                tokenAddresses[i] = address(tokens[i]);
                rewardAmounts[i] = rewards[i];
                unchecked {
                    ++i;
                }
            }

            tokenAddresses[length] = address(SUSHI);
            rewardAmounts[length] = pendingSushi;

            return (tokenAddresses, rewardAmounts);
        } else {
            address[] memory tokenAddresses = new address[](1);
            uint256[] memory rewardAmounts = new uint256[](1);

            tokenAddresses[0] = address(SUSHI);
            rewardAmounts[0] = pendingSushi;

            return (tokenAddresses, rewardAmounts);
        }
    }

    /**
     * @notice Gets how much WETH we would get by dumping it on LP
     * @param _asset The asset we are exchanging for WETH
     * @param _amount Amount of _asset
     * @return Amount in WETH
     */
    function _assetToETH(address _asset, uint256 _amount) public view returns (uint256) {
        address pair = lpsRegistry.getLpAddress(_asset, address(WETH));

        uint256 ethAmount = AssetsPricing.getAmountOut(pair, _amount, _asset, address(WETH));

        (bool success,) = _tryGetAssetDecimals(_asset);

        if (!success) {
            revert FailToGetAssetDecimals();
        }

        return ethAmount;
    }

    function _tryGetAssetDecimals(address asset_) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) =
            asset_.staticcall(abi.encodeWithSelector(IERC20Metadata.decimals.selector));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event Stake(address from, uint256 pid, uint256 amount);
    event UnStake(address to, uint256 pid, uint256 amount);
    event Harvest(address to, uint256 pid);
    event Exit(address to, uint256 amount);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error ZeroAddress();
    error FailSendETH();
    error FailToGetAssetDecimals();
}

