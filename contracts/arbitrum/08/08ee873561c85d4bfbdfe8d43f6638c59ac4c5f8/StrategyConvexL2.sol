// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeERC20.sol";

import "./IUniswapRouterETH.sol";
import "./IWrappedNative.sol";
import "./IConvex.sol";
import "./ICurveSwap.sol";
import "./IGaugeFactory.sol";
import "./StratFeeManager.sol";
import "./Path.sol";
import "./UniV3Actions.sol";

contract StrategyConvexL2 is StratFeeManager {
    using Path for bytes;
    using SafeERC20 for IERC20;

    IConvexBoosterL2 public constant booster =
        IConvexBoosterL2(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant unirouterV3 =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public native;
    /**
     * @notice Curve lpToken
     */
    address public want;
    /**
     * @notice Curve swap pool
     */
    address public pool;
    /**
     * @notice Curve zap to deposit in metapools, or 0
     */
    address public zap;
    /**
     * @notice Token sent to pool or zap to receive want
     */
    address public depositToken;
    /**
     * @notice Convex base reward pool
     */
    address public rewardPool;
    /**
     * @notice Convex booster poolId
     */
    uint public pid;
    /**
     * @notice Pool or zap size
     */
    uint public poolSize;
    /**
     * @notice Index of depositToken in pool or zap
     */
    uint public depositIndex;
    /**
     * @notice Pass additional true to add_liquidity e.g. aave tokens
     */
    bool public useUnderlying;
    /**
     * @notice If depositToken should be sent as unwrapped native
     */
    bool public depositNative;

    /**
     * @notice v3 path or v2 route swapped via StratFeeManager.unirouter
     */
    bytes public nativeToDepositPath;
    address[] public nativeToDepositRoute;

    struct RewardV3 {
        address token;
        /**
         * @notice Uniswap path
         */
        bytes toNativePath;
        /**
         * @notice Minimum amount to be swapped to native
         */
        uint minAmount;
    }
    /**
     * @notice // rewards swapped via unirouterV3
     */
    RewardV3[] public rewardsV3;

    struct RewardV2 {
        address token;
        /**
         * @notice Uniswap v2 router
         */
        address router;
        /**
         * @notice Uniswap route
         */
        address[] toNativeRoute;
        /**
         * @notice Minimum amount to be swapped to native
         */
        uint minAmount;
    }
    RewardV2[] public rewards;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(
        address indexed harvester,
        uint256 wantHarvested,
        uint256 tvl
    );
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(
        uint256 callFees,
        uint256 beefyFees,
        uint256 strategistFees
    );

    /**
     * @dev Initializes strategy.
     * @param _want want address
     * @param _pool pool address
     * @param _zap zap address
     * @param _pid pool id number
     * @param _params [poolSize, depositIndex, useUnderlying, useDepositNative]
     * @param _crvToNativePath CRV to native path
     * @param _cvxToNativePath CVX to native path
     * @param _nativeToDepositRoute native to Deposit route
     * @param _nativeToDepositPath native to Deposit path
     * @param _commonAddresses vault, unirouter, keeper, strategist, beefyFeeRecipient, beefyFeeConfig
     */
    constructor(
        address _want,
        address _pool,
        address _zap,
        uint _pid,
        uint[] memory _params,
        bytes memory _crvToNativePath,
        bytes memory _cvxToNativePath,
        bytes memory _nativeToDepositPath,
        address[] memory _nativeToDepositRoute,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        pool = _pool;
        zap = _zap;
        pid = _pid;
        poolSize = _params[0];
        depositIndex = _params[1];
        useUnderlying = _params[2] > 0;
        depositNative = _params[3] > 0;
        (, , rewardPool, , ) = booster.poolInfo(_pid);

        if (_nativeToDepositPath.length > 0) {
            address[] memory nativeRoute = pathToRoute(_nativeToDepositPath);
            native = nativeRoute[0];
            depositToken = nativeRoute[nativeRoute.length - 1];
            nativeToDepositPath = _nativeToDepositPath;
        } else {
            native = _nativeToDepositRoute[0];
            depositToken = _nativeToDepositRoute[
                _nativeToDepositRoute.length - 1
            ];
            nativeToDepositRoute = _nativeToDepositRoute;
        }
        if (_crvToNativePath.length > 0) addRewardV3(_crvToNativePath, 1e9);
        if (_cvxToNativePath.length > 0) addRewardV3(_cvxToNativePath, 1e9);

        withdrawalFee = 0;
        harvestOnDeposit = true;
        _giveAllowances();
    }

    /**
     *@notice Puts the funds to work
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            booster.deposit(pid, wantBal);
            emit Deposit(balanceOf());
        }
    }

    /**
     *@notice Withdraw for amount
     *@param _amount Withdraw amount
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IConvexRewardPool(rewardPool).withdraw(_amount - wantBal, false);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) /
                WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    /**
     *@notice Harvest on deposit check
     */
    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    /**
     *@notice harvests the rewards
     */
    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    /**
     *@notice  harvests the rewards
     *@param callFeeRecipient fee recipient address
     */
    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient, false);
    }

    /**
     *@notice Compounds earnings and charges performance fee
     *@param callFeeRecipient Caller address
     *@param onDeposit true/false
     */
    function _harvest(
        address callFeeRecipient,
        bool onDeposit
    ) internal whenNotPaused {
        IConvexRewardPool(rewardPool).getReward(address(this));
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            if (!onDeposit) {
                deposit();
            }
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    /**
     *@notice Swap rewards to Native
     */
    function swapRewardsToNative() internal {
        for (uint i; i < rewardsV3.length; ++i) {
            uint bal = IERC20(rewardsV3[i].token).balanceOf(address(this));
            if (bal >= rewardsV3[i].minAmount) {
                UniV3Actions.swapV3WithDeadline(
                    unirouterV3,
                    rewardsV3[i].toNativePath,
                    bal
                );
            }
        }
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                IUniswapRouterETH(rewards[i].router).swapExactTokensForTokens(
                    bal,
                    0,
                    rewards[i].toNativeRoute,
                    address(this),
                    block.timestamp
                );
            }
        }
    }

    /**
     *@notice Performance fees
     */
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = (IERC20(native).balanceOf(address(this)) *
            fees.total) / DIVISOR;

        uint256 callFeeAmount = (nativeBal * fees.call) / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = (nativeBal * fees.beefy) / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = (nativeBal * fees.strategist) / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    /**
     *@notice Adds liquidity to AMM and gets more LP tokens.
     */
    function addLiquidity() internal {
        uint256 depositBal;
        uint256 depositNativeAmount;
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (depositToken != native) {
            if (nativeToDepositPath.length > 0) {
                UniV3Actions.swapV3WithDeadline(
                    unirouter,
                    nativeToDepositPath,
                    nativeBal
                );
            } else {
                IUniswapRouterETH(unirouter).swapExactTokensForTokens(
                    nativeBal,
                    0,
                    nativeToDepositRoute,
                    address(this),
                    block.timestamp
                );
            }
            depositBal = IERC20(depositToken).balanceOf(address(this));
        } else {
            depositBal = nativeBal;
            if (depositNative) {
                depositNativeAmount = nativeBal;
                IWrappedNative(native).withdraw(depositNativeAmount);
            }
        }

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else
                ICurveSwap(pool).add_liquidity{value: depositNativeAmount}(
                    amounts,
                    0
                );
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else if (zap != address(0))
                ICurveSwap(zap).add_liquidity{value: depositNativeAmount}(
                    pool,
                    amounts,
                    0
                );
            else
                ICurveSwap(pool).add_liquidity{value: depositNativeAmount}(
                    amounts,
                    0
                );
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[depositIndex] = depositBal;
            if (zap != address(0))
                ICurveSwap(zap).add_liquidity(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[depositIndex] = depositBal;
            if (zap != address(0))
                ICurveSwap(zap).add_liquidity(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        }
    }

    /**
     *@notice Add reward
     *@param _router router address
     *@param _rewardToNativeRoute Reward to Native route
     *@param _minAmount Min. amount
     */
    function addRewardV2(
        address _router,
        address[] calldata _rewardToNativeRoute,
        uint _minAmount
    ) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != rewardPool, "!convex");

        rewards.push(
            RewardV2(token, _router, _rewardToNativeRoute, _minAmount)
        );
        IERC20(token).approve(_router, 0);
        IERC20(token).approve(_router, type(uint).max);
    }

    /**
     *@notice Add reward
     *@param _rewardToNativePath Reward to Native path
     *@param _minAmount Min. amount
     */
    function addRewardV3(
        bytes memory _rewardToNativePath,
        uint _minAmount
    ) public onlyOwner {
        address[] memory _rewardToNativeRoute = pathToRoute(
            _rewardToNativePath
        );
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != rewardPool, "!convex");

        rewardsV3.push(RewardV3(token, _rewardToNativePath, _minAmount));
        IERC20(token).approve(unirouterV3, 0);
        IERC20(token).approve(unirouterV3, type(uint).max);
    }

    /**
     *@notice Reset rewards
     */
    function resetRewardsV2() external onlyManager {
        delete rewards;
    }

    /**
     *@notice Reset rewardsV3
     */
    function resetRewardsV3() external onlyManager {
        delete rewardsV3;
    }

    /**
     *@notice Calculate the total underlaying 'want' held by the strat.
     *@return uint256 Balance
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    /**
     *@notice It calculates how much 'want' this contract holds.
     *@return uint256 Want balance
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     *@notice It calculates how much 'want' the strategy has working in the farm.
     *@return uint256 Pool balance
     */
    function balanceOfPool() public view returns (uint256) {
        return IConvexRewardPool(rewardPool).balanceOf(address(this));
    }

    /**
     *@notice gets the path ro toue
     *@param _path Path
     *@return address Routes
     */
    function pathToRoute(
        bytes memory _path
    ) public pure returns (address[] memory) {
        uint numPools = _path.numPools();
        address[] memory route = new address[](numPools + 1);
        for (uint i; i < numPools; i++) {
            (address tokenA, address tokenB, ) = _path.decodeFirstPool();
            route[i] = tokenA;
            route[i + 1] = tokenB;
            _path = _path.skipToken();
        }
        return route;
    }

    /**
     *@notice Get Native to Deposit route addreses
     *@return address native to Deposit Route
     */
    function nativeToDeposit() external view returns (address[] memory) {
        if (nativeToDepositPath.length > 0) {
            return pathToRoute(nativeToDepositPath);
        } else return nativeToDepositRoute;
    }

    /**
     *@notice Get rewardV3 to native route addreses
     *@return address native to Deposit Route
     */
    function rewardV3ToNative() external view returns (address[] memory) {
        return pathToRoute(rewardsV3[0].toNativePath);
    }

    /**
     *@notice Get rewardV3 to native route addreses
     *@param i array index
     *@return address Reward to nativeV3 route
     */
    function rewardV3ToNative(uint i) external view returns (address[] memory) {
        return pathToRoute(rewardsV3[i].toNativePath);
    }

    /**
     *@notice Get rewardV3 array length
     *@return uint Length
     */
    function rewardsV3Length() external view returns (uint) {
        return rewardsV3.length;
    }

    /**
     *@notice Get reward to native route addreses
     *@return address Reward to native route
     */
    function rewardToNative() external view returns (address[] memory) {
        return rewards[0].toNativeRoute;
    }

    /**
     *@notice Get reward to native route addreses
     *@param i array index
     *@return address Reward to native route
     */
    function rewardToNative(uint i) external view returns (address[] memory) {
        return rewards[i].toNativeRoute;
    }

    /**
     *@notice Get reward array length
     *@return uint Length
     */
    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    /**
     *@notice Set deposit native true/false
     *@param _depositNative true/false
     */
    function setDepositNative(bool _depositNative) external onlyOwner {
        depositNative = _depositNative;
    }

    /**
     *@notice Set harvest on deposit true/false
     *@param _harvestOnDeposit true/false
     */
    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(1);
        }
    }

    /**
     *@notice Returns rewards unharvested
     *@return uint256 Rewards amount
     */
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
    }

    /**
     *@notice Native reward amount for calling harvest
     *@return uint256 Native rewards amount
     */
    function callReward() public pure returns (uint256) {
        return 0;
    }

    /**
     *@notice Called as part of strat migration. Sends all the available funds back to the vault.
     */
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IConvexRewardPool(rewardPool).withdrawAll(false);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    /**
     *@notice Pauses deposits and withdraws all funds from third party systems.
     */
    function panic() public onlyManager {
        pause();
        IConvexRewardPool(rewardPool).withdrawAll(false);
    }

    /**
     *@notice pauses the strategy
     */
    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    /**
     *@notice unpauses the strategy
     */
    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    /**
     *@notice Give all allowances
     */
    function _giveAllowances() internal {
        IERC20(want).approve(address(booster), type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);
        IERC20(depositToken).approve(pool, type(uint).max);
        if (zap != address(0))
            IERC20(depositToken).approve(zap, type(uint).max);
    }

    /**
     *@notice Remove all allowances
     */
    function _removeAllowances() internal {
        IERC20(want).approve(address(booster), 0);
        IERC20(native).approve(unirouter, 0);
        IERC20(depositToken).approve(pool, 0);
        if (zap != address(0)) IERC20(depositToken).approve(zap, 0);
    }

    receive() external payable {}
}

