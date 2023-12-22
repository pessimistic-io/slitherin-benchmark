// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

import "./IUniswapRouterETH.sol";
import "./IWrappedNative.sol";
import "./ICurveSwap.sol";
import "./IGaugeFactory.sol";
import "./IRewardsGauge.sol";
import "./SafeCurveSwap.sol";
import "./SafeUniswapRouter.sol";
import "./FeeManager.sol";
import "./SlippageManager.sol";
import "./StratManager.sol";
import "./AddressUtils.sol";

contract StrategyCurveLP is StratManager, FeeManager, SlippageManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeCurveSwap for ICurveSwap;
    using SafeUniswapRouter for IUniswapRouterETH;

    // Tokens used
    address public want; // Curve LP token
    address public crv;
    address public native;
    address public preferredUnderlyingToken;

    // Third party contracts
    address public immutable gaugeFactory;
    address public rewardsGauge;
    address public pool;

    uint public poolSize;
    uint public immutable preferredUnderlyingTokenIndex;

    bool public immutable useUnderlying;
    bool public immutable useMetapool;
    // If preferredUnderlyingToken should be sent as unwrapped native.
    bool public immutable depositNative;

    // Routes
    address[] public crvToNativeRoute;
    address[] public nativeToPreferredUnderlyingTokenRoute;

    struct Reward {
        address token;
        address[] toNativeRoute;
        uint minAmount; // Minimum amount to be swapped to native
    }

    Reward[] public rewards;

    bool public harvestOnDeposit = false;
    uint256 public lastHarvest;

    mapping(address => bool) public underlyingTokenAndFlag;
    mapping(address => uint256) public underlyingTokenAndIndex;

    event Harvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargeFees(uint256 harvestCallFeeAmount, uint256 strategistFeeAmount, uint256 performanceFeeAmount);
    event OwnerOperation(address indexed invoker, string method);

    constructor(
        address _want,
        address _gaugeFactory,
        address _gauge,
        address _pool,
        uint _poolSize,
        bool[] memory _liquidityOptions,
        address[] memory _crvToNativeRoute,
        address[] memory _nativeToPreferredUnderlyingTokenRoute,
        address _vault,
        address _unirouter,
        address _strategist,
        address _companyFeeRecipient,
        address _preferredUnderlyingToken
    ) StratManager(_strategist, _unirouter, _vault, _companyFeeRecipient) public {
        want = AddressUtils.validateOneAndReturn(_want);
        gaugeFactory = AddressUtils.validateOneAndReturn(_gaugeFactory);
        rewardsGauge = AddressUtils.validateOneAndReturn(_gauge);
        pool = AddressUtils.validateOneAndReturn(_pool);
        poolSize = _poolSize;

        useUnderlying = _liquidityOptions[0];
        useMetapool = _liquidityOptions[1];
        depositNative = _liquidityOptions[2];

        AddressUtils.validateMany(_crvToNativeRoute);
        AddressUtils.validateMany(_nativeToPreferredUnderlyingTokenRoute);

        crv = _crvToNativeRoute[0];
        native = _crvToNativeRoute[_crvToNativeRoute.length - 1];
        crvToNativeRoute = _crvToNativeRoute;

        require(_nativeToPreferredUnderlyingTokenRoute[0] == native, '_nativeToPreferredUnderlyingTokenRoute[0] != native');
        nativeToPreferredUnderlyingTokenRoute = _nativeToPreferredUnderlyingTokenRoute;

        preferredUnderlyingToken = AddressUtils.validateOneAndReturn(_preferredUnderlyingToken);

        for (uint256 index = 0; index < poolSize; index++) {
            address tokenAddress = ICurveSwap(pool).coins(index);
            underlyingTokenAndFlag[tokenAddress] = true;
            underlyingTokenAndIndex[tokenAddress] = index;
        }

        preferredUnderlyingTokenIndex = underlyingTokenAndIndex[preferredUnderlyingToken];

        _giveAllowances();
    }

    function deposit() public whenNotPaused nonReentrant {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardsGauge(rewardsGauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external nonReentrant {
        require(msg.sender == vault, "!vault");

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = _amount.mul(withdrawalFee).div(FEE_DENOMINATOR);
            _amount = _amount.sub(withdrawalFeeAmount);
        }

        uint256 wantBal = balanceOfWant();
        if (wantBal < _amount) {
            IRewardsGauge(rewardsGauge).withdraw(_amount.sub(wantBal));
        }

        IERC20(want).safeTransfer(vault, _amount);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            harvest();
        }
    }

    // Compounds earnings and charges fees.
    function harvest() public whenNotPaused {
        if (gaugeFactory != address(0)) {
            IGaugeFactory(gaugeFactory).mint(rewardsGauge);
        }
        IRewardsGauge(rewardsGauge).claim_rewards(address(this));
        _swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            _chargeFees();
            _addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();
            lastHarvest = block.timestamp;
            emit Harvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function addRewardToken(address[] memory _rewardToNativeRoute, uint _minAmount) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != rewardsGauge, "!native");

        rewards.push(Reward(token, _rewardToNativeRoute, _minAmount));
        IERC20(token).safeApprove(unirouter, 0);
        IERC20(token).safeApprove(unirouter, type(uint).max);

        emit OwnerOperation(msg.sender, "StrategyCurveLP.addRewardToken");
    }

    function resetRewardTokens() external onlyOwner {
        delete rewards;

        emit OwnerOperation(msg.sender, "StrategyCurveLP.resetRewardTokens");
    }

    // Calculates the total underlying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // Calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // Calculates how much 'want' the strategy has working in the pool.
    function balanceOfPool() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).balanceOf(address(this));
    }

    function crvToNative() external view returns (address[] memory) {
        return crvToNativeRoute;
    }

    function nativeToPreferredUnderlyingToken() external view returns (address[] memory) {
        return nativeToPreferredUnderlyingTokenRoute;
    }

    function rewardToNative() external view returns (address[] memory) {
        return rewards[0].toNativeRoute;
    }

    function rewardToNative(uint i) external view returns (address[] memory) {
        return rewards[i].toNativeRoute;
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function setCrvRoute(address[] memory _crvToNative) external onlyOwner {
        require(_crvToNative[0] == crv, '!crv');
        require(_crvToNative[_crvToNative.length - 1] == native, '!native');

        crvToNativeRoute = _crvToNative;

        emit OwnerOperation(msg.sender, "StrategyCurveLP.setCrvRoute");
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;

        emit OwnerOperation(msg.sender, "StrategyCurveLP.setHarvestOnDeposit");
    }

    // Returns rewards claimable.
    function rewardsAvailable() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).claimable_reward(address(this), crv);
    }

    // Current native reward amount for calling harvest.
    function callReward() external view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256[] memory amountOut = IUniswapRouterETH(unirouter).getAmountsOut(outputBal, crvToNativeRoute);
        uint256 nativeOut = amountOut[amountOut.length - 1];

        return nativeOut.mul(harvestCallFee).div(FEE_DENOMINATOR);
    }

    // Pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyOwner {
        pause();
        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());

        emit OwnerOperation(msg.sender, "StrategyCurveLP.panic");
    }

    function pause() public onlyOwner {
        _pause();

        _removeAllowances();

        emit OwnerOperation(msg.sender, "StrategyCurveLP.pause");
    }

    function unpause() external onlyOwner {
        _unpause();

        _giveAllowances();

        deposit();

        emit OwnerOperation(msg.sender, "StrategyCurveLP.unpause");
    }

    function coins(uint256 _index) external view returns (address){
        return ICurveSwap(pool).coins(_index);
    }

    function underlyingToken(address _tokenAddress) external view returns (bool){
        return underlyingTokenAndFlag[_tokenAddress];
    }

    function underlyingTokenIndex(address _tokenAddress) external view returns (uint256){
        return underlyingTokenAndIndex[_tokenAddress];
    }

    receive() external payable {}

    function _swapRewardsToNative() internal {
        uint256 crvBal = IERC20(crv).balanceOf(address(this));
        if (crvBal > 0) {
            IUniswapRouterETH(unirouter).safeSwapExactTokensForTokens(slippage, crvBal, crvToNativeRoute, address(this), block.timestamp);
        }

        for (uint i; i < rewards.length; i++) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                IUniswapRouterETH(unirouter).safeSwapExactTokensForTokens(slippage, bal, rewards[i].toNativeRoute, address(this), block.timestamp);
            }
        }
    }

    // Charge harvest call, strategy, and performance fees from profits earned.
    function _chargeFees() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 harvestCallFeeAmount;
        if (harvestCallFee > 0) {
            harvestCallFeeAmount = nativeBal.mul(harvestCallFee).div(FEE_DENOMINATOR);
            IERC20(native).safeTransfer(tx.origin, harvestCallFeeAmount);
        }

        uint256 strategistFeeAmount;
        if (strategistFee > 0 && strategist != address(0)) {
            strategistFeeAmount = nativeBal.mul(strategistFee).div(FEE_DENOMINATOR);
            IERC20(native).safeTransfer(strategist, strategistFeeAmount);
        }

        uint256 performanceFeeAmount = nativeBal.mul(performanceFee).div(FEE_DENOMINATOR);
        IERC20(native).safeTransfer(companyFeeRecipient, performanceFeeAmount);

        emit ChargeFees(harvestCallFeeAmount, strategistFeeAmount, performanceFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function _addLiquidity() internal {
        uint256 preferredUnderlyingBal;
        uint256 depositNativeAmount;
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (preferredUnderlyingToken != native) {
            IUniswapRouterETH(unirouter).safeSwapExactTokensForTokens(slippage, nativeBal, nativeToPreferredUnderlyingTokenRoute, address(this), block.timestamp);
            preferredUnderlyingBal = IERC20(preferredUnderlyingToken).balanceOf(address(this));
        } else {
            preferredUnderlyingBal = nativeBal;
            if (depositNative) {
                depositNativeAmount = nativeBal;
                IWrappedNative(native).withdraw(depositNativeAmount);
            }
        }

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[preferredUnderlyingTokenIndex] = preferredUnderlyingBal;
            if (useUnderlying) ICurveSwap(pool).safeAddLiquidity(slippage, amounts, true);
            else ICurveSwap(pool).safeAddLiquidity(slippage, amounts, depositNativeAmount);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[preferredUnderlyingTokenIndex] = preferredUnderlyingBal;
            if (useUnderlying) ICurveSwap(pool).safeAddLiquidity(slippage, amounts, true);
            else if (useMetapool) ICurveSwap(pool).safeAddLiquidity(slippage, want, amounts);
            else ICurveSwap(pool).safeAddLiquidity(slippage, amounts);
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[preferredUnderlyingTokenIndex] = preferredUnderlyingBal;
            if (useMetapool) ICurveSwap(pool).safeAddLiquidity(slippage, want, amounts);
            else ICurveSwap(pool).safeAddLiquidity(slippage, amounts);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[preferredUnderlyingTokenIndex] = preferredUnderlyingBal;
            ICurveSwap(pool).safeAddLiquidity(slippage, amounts);
        }
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(crv).safeApprove(unirouter, type(uint).max);
        IERC20(preferredUnderlyingToken).safeApprove(pool, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(crv).safeApprove(unirouter, 0);
        IERC20(preferredUnderlyingToken).safeApprove(pool, 0);
    }
}

