// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./IMinimaxStaking.sol";
import "./IMinimaxMain.sol";
import "./IPriceOracle.sol";
import "./IGelatoOps.sol";

import "./IPoolAdapter.sol";
import "./ProxyCaller.sol";
import "./ProxyCallerApi.sol";
import "./ProxyPool.sol";
import "./PositionInfo.sol";
import "./PositionBalanceLib.sol";
import "./PositionLib.sol";
import "./IProxyOwner.sol";
import "./MinimaxAdvanced.sol";
import "./MinimaxBase.sol";

/*
    MinimaxMain
*/
contract MinimaxMain is IMinimaxMain, IProxyOwner, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // -----------------------------------------------------------------------------------------------------------------
    // Using declarations.

    using SafeERC20Upgradeable for IERC20Upgradeable;

    using ProxyCallerApi for ProxyCaller;

    using ProxyPool for ProxyCaller[];

    // -----------------------------------------------------------------------------------------------------------------
    // Events.

    // NB: If `estimatedStakedTokenPrice` is equal to `0`, then the price is unavailable for some reason.

    event PositionWasCreated(uint indexed positionIndex);
    event PositionWasCreatedV2(
        uint indexed positionIndex,
        uint timestamp,
        uint stakedTokenPrice,
        uint8 stakedTokenPriceDecimals
    );

    event PositionWasModified(uint indexed positionIndex);

    event PositionWasClosed(uint indexed positionIndex);
    event PositionWasClosedV2(
        uint indexed positionIndex,
        uint timestamp,
        uint stakedTokenPrice,
        uint8 stakedTokenPriceDecimals
    );

    event PositionWasLiquidatedV2(
        uint indexed positionIndex,
        uint timestamp,
        uint stakedTokenPrice,
        uint8 stakedTokenPriceDecimals
    );

    event StakedBaseTokenWithdraw(uint indexed positionIndex, address token, uint amount);

    event StakedSwapTokenWithdraw(uint indexed positionIndex, address token, uint amount);

    event RewardTokenWithdraw(uint indexed positionIndex, address token, uint amount);

    // -----------------------------------------------------------------------------------------------------------------
    // Storage.

    uint constant FEE_MULTIPLIER = 1e8;
    uint constant SLIPPAGE_MULTIPLIER = 1e8;
    uint constant POSITION_PRICE_LIMITS_MULTIPLIER = 1e8;

    address cakeAddress; // TODO: remove when deploy clean version

    // BUSD for BSC, USDT for POLYGON
    address public busdAddress; // TODO: rename to stableToken when deploy clean version

    address minimaxStaking;

    uint public lastPositionIndex;

    // Use mapping instead of array for upgradeability of PositionInfo struct
    mapping(uint => PositionInfo) positions;

    mapping(address => bool) isLiquidator;

    ProxyCaller[] proxyPool;

    // Fee threshold
    struct FeeThreshold {
        uint fee;
        uint stakedAmountThreshold;
    }

    FeeThreshold[] depositFees;

    /// @custom:oz-renamed-from poolAdapters
    mapping(address => IPoolAdapter) poolAdaptersDeprecated;

    mapping(IERC20Upgradeable => IPriceOracle) public priceOracles;

    // TODO: deprecated
    mapping(address => address) tokenExchanges;

    // gelato
    IGelatoOps public gelatoOps;

    address payable public gelatoPayee;

    mapping(address => uint256) gelatoLiquidateFee; // TODO: remove when deploy clean version
    uint256 liquidatorFee; // transfered to liquidator (not gelato) when `gelatoOps` is not set
    address gelatoFeeToken; // TODO: remove when deploy clean version

    // TODO: deprecated
    address defaultExchange;

    // poolAdapters by bytecode hash
    mapping(uint256 => IPoolAdapter) public poolAdapters;

    IMarket public market;

    address wrappedNative;

    address public oneInchRouter;

    // Migrate

    bool public disabled;

    mapping(address => bool) public isProxyManager;

    // -----------------------------------------------------------------------------------------------------------------
    // Methods.

    function setGasTankThreshold(uint256 value) external onlyOwner {
        liquidatorFee = value;
    }

    function setDisabled(bool _disabled) external onlyOwner {
        disabled = _disabled;
    }

    function setGelatoOps(address _gelatoOps) external onlyOwner {
        gelatoOps = IGelatoOps(_gelatoOps);
    }

    function getPoolAdapterKey(address pool) public view returns (uint256) {
        return uint256(keccak256(pool.code));
    }

    function getPoolAdapter(address pool) public view returns (IPoolAdapter) {
        uint256 key = getPoolAdapterKey(pool);
        return poolAdapters[key];
    }

    function getPoolAdapterSafe(address pool) public view returns (IPoolAdapter) {
        IPoolAdapter adapter = getPoolAdapter(pool);
        require(address(adapter) != address(0), "pool adapter not found");
        return adapter;
    }

    function getPoolAdapters(address[] calldata pools)
        public
        view
        returns (IPoolAdapter[] memory adapters, uint256[] memory keys)
    {
        adapters = new IPoolAdapter[](pools.length);
        keys = new uint256[](pools.length);
        for (uint i = 0; i < pools.length; i++) {
            uint256 key = getPoolAdapterKey(pools[i]);
            keys[i] = key;
            adapters[i] = poolAdapters[key];
        }
    }

    // Staking pool adapters
    function setPoolAdapters(address[] calldata pools, IPoolAdapter[] calldata adapters) external onlyOwner {
        require(pools.length == adapters.length, "pools and adapters parameters should have the same length");
        for (uint32 i = 0; i < pools.length; i++) {
            uint256 key = getPoolAdapterKey(pools[i]);
            poolAdapters[key] = adapters[i];
        }
    }

    // Price oracles
    function setPriceOracles(IERC20Upgradeable[] calldata tokens, IPriceOracle[] calldata oracles) external onlyOwner {
        require(tokens.length == oracles.length, "tokens and oracles parameters should have the same length");
        for (uint32 i = 0; i < tokens.length; i++) {
            priceOracles[tokens[i]] = oracles[i];
        }
    }

    function getPriceOracleSafe(IERC20Upgradeable token) public view returns (IPriceOracle) {
        IPriceOracle oracle = priceOracles[token];
        require(address(oracle) != address(0), "price oracle not found");
        return oracle;
    }

    function setMarket(IMarket _market) external onlyOwner {
        market = _market;
    }

    function setOneInchRouter(address _router) external onlyOwner {
        oneInchRouter = _router;
    }

    modifier onlyAutomator() {
        require(msg.sender == address(gelatoOps) || isLiquidator[address(msg.sender)], "onlyAutomator");
        _;
    }

    modifier onlyThis() {
        require(msg.sender == address(this));
        _;
    }

    modifier onlyPositionOwner(uint positionIndex) {
        require(positions[positionIndex].owner == address(msg.sender), "onlyPositionOwner");
        _;
    }

    function initialize(
        address _minimaxStaking,
        address _busdAddress,
        address _gelatoOps
    ) external initializer {
        minimaxStaking = _minimaxStaking;
        busdAddress = _busdAddress;
        gelatoOps = IGelatoOps(_gelatoOps);

        __Ownable_init();
        __ReentrancyGuard_init();

        // staking pool
        depositFees.push(
            FeeThreshold({
                fee: 100000, // 0.1%
                stakedAmountThreshold: 1000 * 1e18 // all stakers <= 1000 MMX would have 0.1% fee for deposit
            })
        );

        depositFees.push(
            FeeThreshold({
                fee: 90000, // 0.09%
                stakedAmountThreshold: 5000 * 1e18
            })
        );

        depositFees.push(
            FeeThreshold({
                fee: 80000, // 0.08%
                stakedAmountThreshold: 10000 * 1e18
            })
        );

        depositFees.push(
            FeeThreshold({
                fee: 70000, // 0.07%
                stakedAmountThreshold: 50000 * 1e18
            })
        );
        depositFees.push(
            FeeThreshold({
                fee: 50000, // 0.05%
                stakedAmountThreshold: 10000000 * 1e18 // this level doesn't matter
            })
        );
    }

    receive() external payable {}

    function getUserFee(address user) public view returns (uint) {
        IMinimaxStaking staking = IMinimaxStaking(minimaxStaking);

        uint amountPool2 = staking.getUserAmount(2, user);
        uint amountPool3 = staking.getUserAmount(3, user);
        uint totalStakedAmount = amountPool2 + amountPool3;

        uint length = depositFees.length;

        for (uint bucketId = 0; bucketId < length; ++bucketId) {
            uint threshold = depositFees[bucketId].stakedAmountThreshold;
            if (totalStakedAmount <= threshold) {
                return depositFees[bucketId].fee;
            }
        }

        return depositFees[length - 1].fee;
    }

    function getUserFeeAmount(address user, uint amount) public view returns (uint) {
        uint userFeeShare = getUserFee(user);
        return (amount * userFeeShare) / FEE_MULTIPLIER;
    }

    function getPositionInfo(uint positionIndex) external view returns (PositionInfo memory) {
        return positions[positionIndex];
    }

    function transferTo(
        address token,
        address to,
        uint amount
    ) external onlyOwner {
        address nativeToken = address(0);
        if (token == nativeToken) {
            (bool success, ) = to.call{value: amount}("");
            require(success, "transferTo: BNB transfer failed");
        } else {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(token), to, amount);
        }
    }

    function emergencyWithdraw(uint positionIndex) external onlyOwner {
        PositionLib.emergencyWithdraw(this, positions[positionIndex], positionIndex);
    }

    function setDepositFee(uint poolIdx, uint feeShare) external onlyOwner {
        require(poolIdx < depositFees.length, "wrong pool index");
        depositFees[poolIdx].fee = feeShare;
    }

    function setMinimaxStakingAddress(address stakingAddress) external onlyOwner {
        minimaxStaking = stakingAddress;
    }

    // Deprecated
    // TODO: revert at the end to prevent state change
    function getPositionBalances(uint[] calldata positionIndexes)
        public
        returns (PositionBalanceLib.PositionBalanceV1[] memory)
    {
        return PositionBalanceLib.getManyV1(this, positions, positionIndexes);
    }

    // TODO: revert at the end to prevent state change
    function getPositionBalancesV2(uint[] calldata positionIndexes)
        public
        returns (PositionBalanceLib.PositionBalanceV2[] memory)
    {
        return PositionBalanceLib.getManyV2(this, positions, positionIndexes);
    }

    // TODO: revert at the end to prevent state change
    function getPositionBalancesV3(uint[] calldata positionIndexes)
        public
        returns (PositionBalanceLib.PositionBalanceV3[] memory)
    {
        return PositionBalanceLib.getManyV3(this, positions, positionIndexes);
    }

    function stake(
        uint inputAmount,
        IERC20Upgradeable inputToken,
        uint stakingAmountMin,
        IERC20Upgradeable stakingToken,
        address stakingPool,
        uint maxSlippage,
        uint stopLossPrice,
        uint takeProfitPrice,
        uint swapKind,
        bytes calldata swapParams
    ) public payable nonReentrant returns (uint) {
        return
            _stake(
                PositionLib.StakeParams({
                    inputAmount: inputAmount,
                    inputToken: inputToken,
                    stakeAmountMin: stakingAmountMin,
                    stakeToken: stakingToken,
                    stakePool: stakingPool,
                    maxSlippage: maxSlippage,
                    stopLossPrice: stopLossPrice,
                    takeProfitPrice: takeProfitPrice,
                    swapKind: swapKind,
                    swapArgs: swapParams,
                    stakeTokenPrice: 0
                })
            );
    }

    struct StakeV2Params {
        address pool;
        bytes poolArgs;
        IERC20Upgradeable stakeToken;
        uint stopLossPrice;
        uint takeProfitPrice;
        uint maxSlippage;
        uint stakeTokenPrice;
        SwapParams swapParams;
    }

    struct WithdrawV2Params {
        uint positionIndex;
        uint amount;
        bool amountAll;
        uint stakeTokenPrice;
        SwapParams swapParams;
    }

    struct SwapParams {
        IERC20Upgradeable tokenIn;
        uint amountIn;
        IERC20Upgradeable tokenOut;
        uint amountOutMin;
        uint swapKind;
        bytes swapArgs;
    }

    function stakeV2(StakeV2Params calldata params) public payable nonReentrant returns (uint) {
        return
            _stake(
                PositionLib.StakeParams({
                    inputAmount: params.swapParams.amountIn,
                    inputToken: params.swapParams.tokenIn,
                    stakeAmountMin: params.swapParams.amountOutMin,
                    stakeToken: params.stakeToken,
                    stakePool: params.pool,
                    maxSlippage: params.maxSlippage,
                    stopLossPrice: params.stopLossPrice,
                    takeProfitPrice: params.takeProfitPrice,
                    swapKind: params.swapParams.swapKind,
                    swapArgs: params.swapParams.swapArgs,
                    stakeTokenPrice: params.stakeTokenPrice
                })
            );
    }

    function _stake(PositionLib.StakeParams memory params) private returns (uint) {
        require(msg.value >= liquidatorFee, "gasTankThreshold");

        uint positionIndex = lastPositionIndex;
        lastPositionIndex += 1;

        PositionInfo memory position = PositionLib.stake({
            main: this,
            proxy: proxyPool.acquire(),
            positionIndex: positionIndex,
            params: params
        });

        // NB: current implementation assume that liquidation in some way should work. If we want to deploy on a new
        // blockchain without liquidation, this code should be modified.
        if (address(gelatoOps) != address(0)) {
            position.gelatoLiquidateTaskId = _gelatoCreateTask(positionIndex);
        }

        depositGasTank(position.callerAddress);

        positions[positionIndex] = position;
        return positionIndex;
    }

    function swapEstimate(
        address inputToken,
        address stakingToken,
        uint inputTokenAmount
    ) public view returns (uint amountOut, bytes memory hints) {
        require(address(market) != address(0), "no market");
        return market.estimateOut(inputToken, stakingToken, inputTokenAmount);
    }

    function deposit(uint positionIndex, uint amount) external nonReentrant onlyPositionOwner(positionIndex) {
        PositionLib.deposit(this, positions[positionIndex], positionIndex, amount);
    }

    function setLiquidator(address user, bool value) external onlyOwner {
        isLiquidator[user] = value;
    }

    function alterPositionParams(
        uint positionIndex,
        uint newAmount,
        uint newStopLossPrice,
        uint newTakeProfitPrice,
        uint newSlippage
    ) external nonReentrant onlyPositionOwner(positionIndex) {
        PositionLib.alterPositionParams(
            this,
            positions[positionIndex],
            PositionLib.AlterParams({
                positionIndex: positionIndex,
                amount: newAmount,
                stopLossPrice: newStopLossPrice,
                takeProfitPrice: newTakeProfitPrice,
                maxSlippage: newSlippage,
                stakeTokenPrice: 0
            })
        );
    }

    struct AlterPositionV2Params {
        uint positionIndex;
        uint amount;
        uint stopLossPrice;
        uint takeProfitPrice;
        uint maxSlippage;
        uint stakeTokenPrice;
    }

    function alterPositionV2(AlterPositionV2Params calldata params)
        external
        nonReentrant
        onlyPositionOwner(params.positionIndex)
    {
        PositionLib.alterPositionParams(
            this,
            positions[params.positionIndex],
            PositionLib.AlterParams({
                positionIndex: params.positionIndex,
                amount: params.amount,
                stopLossPrice: params.stopLossPrice,
                takeProfitPrice: params.takeProfitPrice,
                maxSlippage: params.maxSlippage,
                stakeTokenPrice: params.stakeTokenPrice
            })
        );
    }

    function withdrawAll(uint positionIndex) external nonReentrant onlyPositionOwner(positionIndex) {
        PositionLib.withdraw(
            this,
            positions[positionIndex],
            PositionLib.WithdrawType.Manual,
            PositionLib.WithdrawParams({
                positionIndex: positionIndex,
                amount: 0,
                amountAll: true,
                destinationToken: positions[positionIndex].stakedToken,
                destinationTokenAmountMin: 0,
                swapKind: PositionLib.SwapNoSwapKind,
                swapParams: "",
                stakeTokenPrice: 0
            })
        );
    }

    function withdraw(uint positionIndex, uint amount) external nonReentrant onlyPositionOwner(positionIndex) {
        PositionLib.withdraw(
            this,
            positions[positionIndex],
            PositionLib.WithdrawType.Manual,
            PositionLib.WithdrawParams({
                positionIndex: positionIndex,
                amount: amount,
                amountAll: false,
                destinationToken: positions[positionIndex].stakedToken,
                destinationTokenAmountMin: 0,
                swapKind: PositionLib.SwapNoSwapKind,
                swapParams: "",
                stakeTokenPrice: 0
            })
        );
    }

    function estimateLpPartsForPosition(uint positionIndex)
        external
        nonReentrant
        onlyPositionOwner(positionIndex)
        returns (uint, uint)
    {
        return PositionLib.estimateLpParts(this, positions[positionIndex], positionIndex);
    }

    function estimateWithdrawalAmountForPosition(uint positionIndex)
        external
        nonReentrant
        onlyPositionOwner(positionIndex)
        returns (uint)
    {
        return PositionLib.estimateWithdrawnAmount(this, positions[positionIndex], positionIndex);
    }

    function withdrawAllWithSwap(
        uint positionIndex,
        address withdrawalToken,
        bytes memory oneInchCallData
    ) external nonReentrant onlyPositionOwner(positionIndex) {
        PositionLib.withdraw(
            this,
            positions[positionIndex],
            PositionLib.WithdrawType.Manual,
            PositionLib.WithdrawParams({
                positionIndex: positionIndex,
                amount: 0,
                amountAll: true,
                destinationToken: IERC20Upgradeable(withdrawalToken),
                destinationTokenAmountMin: 0,
                swapKind: PositionLib.SwapOneInchKind,
                swapParams: abi.encode(PositionLib.SwapOneInch(oneInchCallData)),
                stakeTokenPrice: 0
            })
        );
    }

    // TODO: add slippage for swaps
    function withdrawAllWithSwapLp(
        uint positionIndex,
        address withdrawalToken,
        bytes memory oneInchCallDataToken0,
        bytes memory oneInchCallDataToken1
    ) external nonReentrant onlyPositionOwner(positionIndex) {
        PositionLib.withdraw(
            this,
            positions[positionIndex],
            PositionLib.WithdrawType.Manual,
            PositionLib.WithdrawParams({
                positionIndex: positionIndex,
                amount: 0,
                amountAll: true,
                destinationToken: IERC20Upgradeable(withdrawalToken),
                destinationTokenAmountMin: 0,
                swapKind: PositionLib.SwapOneInchPairKind,
                swapParams: abi.encode(PositionLib.SwapOneInchPair(oneInchCallDataToken0, oneInchCallDataToken1)),
                stakeTokenPrice: 0
            })
        );
    }

    function withdrawV2(WithdrawV2Params calldata params)
        external
        nonReentrant
        onlyPositionOwner(params.positionIndex)
    {
        PositionLib.withdraw(
            this,
            positions[params.positionIndex],
            PositionLib.WithdrawType.Manual,
            PositionLib.WithdrawParams({
                positionIndex: params.positionIndex,
                amount: params.amount,
                amountAll: params.amountAll,
                destinationToken: params.swapParams.tokenOut,
                destinationTokenAmountMin: params.swapParams.amountOutMin,
                swapKind: params.swapParams.swapKind,
                swapParams: params.swapParams.swapArgs,
                stakeTokenPrice: params.stakeTokenPrice
            })
        );
    }

    function closePosition(uint positionIndex) external onlyThis {
        PositionInfo storage position = positions[positionIndex];

        position.closed = true;

        if (isModernProxy(position.callerAddress)) {
            withdrawGasTank(position.callerAddress, position.owner);
            proxyPool.release(position.callerAddress);
        }

        _gelatoCancelTask(position.gelatoLiquidateTaskId);
    }

    function depositGasTank(ProxyCaller proxy) private {
        address(proxy).call{value: msg.value}("");
    }

    function withdrawGasTank(ProxyCaller proxy, address owner) private {
        proxy.transferNativeAll(owner);
    }

    function isModernProxy(ProxyCaller proxy) public view returns (bool) {
        return address(proxy).code.length == 945;
    }

    function tokenPrice(IERC20Upgradeable token) public view returns (uint) {
        return PositionLib.estimatePositionStakedTokenPrice(this, token);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Position events.

    function emitPositionWasModified(uint positionIndex) external onlyThis {
        emit PositionWasModified(positionIndex);
    }

    function emitPositionWasCreated(
        uint positionIndex,
        IERC20Upgradeable token,
        uint price
    ) external onlyThis {
        // TODO(TmLev): Remove once `PositionWasCreatedV2` is stable.
        emit PositionWasCreated(positionIndex);

        if (price == 0) {
            price = PositionLib.estimatePositionStakedTokenPrice(this, token);
        }
        emit PositionWasCreatedV2(positionIndex, block.timestamp, price, IERC20Decimals(address(token)).decimals());
    }

    function emitPositionWasClosed(
        uint positionIndex,
        IERC20Upgradeable token,
        uint price
    ) external onlyThis {
        // TODO(TmLev): Remove once `PositionWasClosedV2` is stable.
        emit PositionWasClosed(positionIndex);

        if (price == 0) {
            price = PositionLib.estimatePositionStakedTokenPrice(this, token);
        }
        emit PositionWasClosedV2(positionIndex, block.timestamp, price, IERC20Decimals(address(token)).decimals());
    }

    function emitPositionWasLiquidated(
        uint positionIndex,
        IERC20Upgradeable token,
        uint price
    ) external onlyThis {
        // TODO(TmLev): Remove once `PositionWasLiquidatedV2` is stable.
        emit PositionWasClosed(positionIndex);

        if (price == 0) {
            price = PositionLib.estimatePositionStakedTokenPrice(this, token);
        }
        emit PositionWasLiquidatedV2(positionIndex, block.timestamp, price, IERC20Decimals(address(token)).decimals());
    }

    function emitStakedBaseTokenWithdraw(
        uint positionIndex,
        address token,
        uint amount
    ) external onlyThis {
        emit StakedBaseTokenWithdraw(positionIndex, token, amount);
    }

    function emitStakedSwapTokenWithdraw(
        uint positionIndex,
        address token,
        uint amount
    ) external onlyThis {
        emit StakedSwapTokenWithdraw(positionIndex, token, amount);
    }

    function emitRewardTokenWithdraw(
        uint positionIndex,
        address token,
        uint amount
    ) external onlyThis {
        emit RewardTokenWithdraw(positionIndex, token, amount);
    }

    // -----------------------------------------------------------------------------------------------------------------
    // Gelato

    struct AutomationParams {
        uint256 positionIndex;
        uint256 minAmountOut;
        bytes marketHints;
        uint256 stakeTokenPrice;
    }

    // TODO: revert at the end to prevent state change
    function automationResolve(uint positionIndex) public returns (bool canExec, bytes memory execPayload) {
        PositionInfo storage position = positions[positionIndex];
        uint256 amountOut;
        bytes memory hints;
        (canExec, amountOut, hints) = PositionLib.isOutsideRange(this, position);
        if (canExec) {
            uint minAmountOut = amountOut - (amountOut * position.maxSlippage) / SLIPPAGE_MULTIPLIER;
            uint stakeTokenPrice = tokenPrice(position.stakedToken);

            AutomationParams memory params = AutomationParams(positionIndex, minAmountOut, hints, stakeTokenPrice);
            execPayload = abi.encodeWithSelector(this.automationExec.selector, abi.encode(params));
        }
    }

    function automationExec(bytes calldata raw) public nonReentrant onlyAutomator {
        AutomationParams memory params = abi.decode(raw, (AutomationParams));
        _gelatoPayFee(params.positionIndex);
        PositionLib.withdraw(
            this,
            positions[params.positionIndex],
            PositionLib.WithdrawType.Liquidation,
            PositionLib.WithdrawParams({
                positionIndex: params.positionIndex,
                amount: 0,
                amountAll: true,
                destinationToken: IERC20Upgradeable(busdAddress),
                destinationTokenAmountMin: params.minAmountOut,
                swapKind: PositionLib.SwapMarketKind,
                swapParams: abi.encode(PositionLib.SwapMarket(params.marketHints)),
                stakeTokenPrice: params.stakeTokenPrice
            })
        );
    }

    function _gelatoPayFee(uint positionIndex) private {
        uint feeAmount;
        address feeDestination;

        if (address(gelatoOps) != address(0)) {
            address feeToken;
            (feeAmount, feeToken) = gelatoOps.getFeeDetails();
            if (feeAmount == 0) {
                return;
            }

            require(feeToken == GelatoNativeToken);

            feeDestination = gelatoOps.gelato();
        } else {
            feeAmount = liquidatorFee;
            feeDestination = msg.sender;
        }

        ProxyCaller proxy = positions[positionIndex].callerAddress;
        proxy.transferNative(feeDestination, feeAmount);
    }

    function _gelatoCreateTask(uint positionIndex) private returns (bytes32) {
        return
            gelatoOps.createTaskNoPrepayment(
                address(this), /* execAddress */
                this.automationExec.selector, /* execSelector */
                address(this), /* resolverAddress */
                abi.encodeWithSelector(this.automationResolve.selector, positionIndex), /* resolverData */
                GelatoNativeToken
            );
    }

    function _gelatoCancelTask(bytes32 gelatoTaskId) private {
        if (address(gelatoOps) != address(0) && gelatoTaskId != "") {
            gelatoOps.cancelTask(gelatoTaskId);
        }
    }

    // Migrate functions

    function migratePosition(
        uint positionIndex,
        MinimaxAdvanced advanced,
        MinimaxBase base
    ) external onlyOwner {
        PositionInfo storage position = positions[positionIndex];
        PositionLib.migratePosition(this, position, positionIndex, advanced, base);
        _gelatoCancelTask(position.gelatoLiquidateTaskId);
        position.closed = true;
    }

    // This is the only code that should remain in MinimaxMain
    // and MinimaxMain should be renamed to MinimaxProxyOwner

    function setProxyManager(address _address, bool _value) external onlyOwner {
        isProxyManager[_address] = _value;
    }

    modifier onlyProxyManager() {
        require(isProxyManager[address(msg.sender)], "onlyProxyManager");
        _;
    }

    function acquireProxy() external onlyProxyManager returns (ProxyCaller) {
        return proxyPool.acquire();
    }

    function releaseProxy(ProxyCaller proxy) external onlyProxyManager {
        if (isModernProxy(proxy)) {
            proxyPool.release(proxy);
        }
    }

    function proxyExec(
        ProxyCaller proxy,
        bool delegate,
        address target,
        bytes calldata data
    ) external nonReentrant onlyProxyManager returns (bool success, bytes memory) {
        return proxy.exec(delegate, target, data);
    }

    function proxyTransfer(
        ProxyCaller proxy,
        address target,
        uint256 amount
    ) external nonReentrant onlyProxyManager returns (bool success, bytes memory) {
        return proxy.transfer(target, amount);
    }
}

