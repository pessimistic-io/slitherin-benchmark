// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IExchangeAdapter.sol";
import "./IMinimaxStaking.sol";
import "./MinimaxStaking.sol";
import "./IPoolAdapter.sol";
import "./IERC20Decimals.sol";
import "./IPriceOracle.sol";
import "./IPancakeRouter.sol";
import "./ISmartChef.sol";
import "./IGelatoOps.sol";
import "./IWrapped.sol";
import "./ProxyCaller.sol";
import "./ProxyCallerApi.sol";
import "./ProxyPool.sol";
import "./Market.sol";
import "./PositionInfo.sol";
import "./PositionExchangeLib.sol";
import "./PositionBalanceLib.sol";

/*
    MinimaxMain
*/
contract MinimaxMain is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using ProxyCallerApi for ProxyCaller;

    event PositionWasCreated(uint indexed positionIndex);
    event PositionWasModified(uint indexed positionIndex);
    event PositionWasClosed(uint indexed positionIndex);

    uint public constant FEE_MULTIPLIER = 1e8;
    uint public constant SLIPPAGE_MULTIPLIER = 1e8;
    uint public constant POSITION_PRICE_LIMITS_MULTIPLIER = 1e8;

    address public cakeAddress; // TODO: remove when deploy clean version

    // BUSD for BSC, USDT for POLYGON
    address public busdAddress; // TODO: rename to stableToken when deploy clean version

    address public minimaxStaking;

    uint public lastPositionIndex;

    // Use mapping instead of array for upgradeability of PositionInfo struct
    mapping(uint => PositionInfo) public positions;

    mapping(address => bool) public isLiquidator;

    ProxyCaller[] public proxyPool;
    using ProxyPool for ProxyCaller[];

    // Fee threshold
    struct FeeThreshold {
        uint fee;
        uint stakedAmountThreshold;
    }

    FeeThreshold[] public depositFees;

    /// @custom:oz-renamed-from poolAdapters
    mapping(address => IPoolAdapter) public poolAdaptersDeprecated;

    mapping(IERC20Upgradeable => IPriceOracle) public priceOracles;

    mapping(IERC20Upgradeable => IExchangeAdapter) public tokenExchanges;

    // gelato
    IGelatoOps public gelatoOps;

    address payable public gelatoPayee;

    mapping(address => uint256) public gelatoLiquidateFee; // TODO: remove when deploy clean version
    uint256 public stakeGelatoFee; // TODO: rename to stakeGelatoFee
    address public gelatoFeeToken; // TODO: remove when deploy clean version

    // If token present in tokenExchanges -- use it. Otherwise use defaultExchange.
    IExchangeAdapter public defaultExchange;

    // poolAdapters by bytecode hash
    mapping(uint256 => IPoolAdapter) public poolAdapters;

    Market public market;

    address public wrappedNative;

    address public oneInchRouter;

    //
    //
    // Storage section ends!
    //
    //

    function setGasTankThreshold(uint256 value) external onlyOwner {
        stakeGelatoFee = value;
    }

    function setGelatoOps(address _gelatoOps) external onlyOwner {
        gelatoOps = IGelatoOps(_gelatoOps);
    }

    function setLastPositionIndex(uint newLastPositionIndex) external onlyOwner {
        require(newLastPositionIndex >= lastPositionIndex, "last position index may only be increased");
        lastPositionIndex = newLastPositionIndex;
    }

    function _getPoolAdapterKey(address pool) private view returns (uint256) {
        return uint256(keccak256(pool.code));
    }

    function _getPoolAdapter(address pool) private view returns (IPoolAdapter) {
        uint256 key = _getPoolAdapterKey(pool);
        return poolAdapters[key];
    }

    function _getPoolAdapterSafe(address pool) public view returns (IPoolAdapter) {
        IPoolAdapter adapter = _getPoolAdapter(pool);
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
            uint256 key = _getPoolAdapterKey(pools[i]);
            keys[i] = key;
            adapters[i] = poolAdapters[key];
        }
    }

    // Staking pool adapters
    function setPoolAdapters(address[] calldata pools, IPoolAdapter[] calldata adapters) external onlyOwner {
        require(pools.length == adapters.length, "pools and adapters parameters should have the same length");
        for (uint32 i = 0; i < pools.length; i++) {
            uint256 key = _getPoolAdapterKey(pools[i]);
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

    // Token exchanges
    function setDefaultTokenExchange(IExchangeAdapter exchange) external onlyOwner {
        defaultExchange = exchange;
    }

    function setTokenExchanges(IERC20Upgradeable[] calldata tokens, IExchangeAdapter[] calldata exchanges)
        external
        onlyOwner
    {
        require(tokens.length == exchanges.length, "tokens and exchanges parameters should have the same length");
        for (uint32 i = 0; i < tokens.length; i++) {
            tokenExchanges[tokens[i]] = exchanges[i];
        }
    }

    function getTokenExchangeSafe(IERC20Upgradeable token) public view returns (IExchangeAdapter) {
        // Return default exchange if not found.
        // That should be safe because function is called after token validation in stakeToken.
        IExchangeAdapter exchange = tokenExchanges[token];
        if (address(exchange) != address(0)) {
            return exchange;
        }
        return defaultExchange;
    }

    function setMarket(Market _market) external onlyOwner {
        market = _market;
    }

    function setWrappedNative(address _native) external onlyOwner {
        wrappedNative = _native;
    }

    function setOneInchRouter(address _router) external onlyOwner {
        oneInchRouter = _router;
    }

    modifier onlyLiquidator() {
        require(isLiquidator[address(msg.sender)], "only one of liquidators can close positions");
        _;
    }

    modifier onlyAutomator() {
        require(msg.sender == address(gelatoOps) || isLiquidator[address(msg.sender)], "onlyAutomator");
        _;
    }

    using SafeERC20Upgradeable for IERC20Upgradeable;

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

    function getSlippageMultiplier() public pure returns (uint) {
        return SLIPPAGE_MULTIPLIER;
    }

    function getUserFee() public view returns (uint) {
        IMinimaxStaking staking = IMinimaxStaking(minimaxStaking);

        uint amountPool2 = staking.getUserAmount(2, msg.sender);
        uint amountPool3 = staking.getUserAmount(3, msg.sender);
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

    function getUserFeeAmount(uint stakeAmount) private view returns (uint) {
        uint userFeeShare = getUserFee();
        return (stakeAmount * userFeeShare) / FEE_MULTIPLIER;
    }

    function getPositionInfo(uint positionIndex) external view returns (PositionInfo memory) {
        return positions[positionIndex];
    }

    function fillProxyPool(uint amount) external onlyOwner {
        proxyPool.add(amount);
    }

    function cleanProxyPool() external onlyOwner {
        delete proxyPool;
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

    function setDepositFee(uint poolIdx, uint feeShare) external onlyOwner {
        require(poolIdx < depositFees.length, "wrong pool index");
        depositFees[poolIdx].fee = feeShare;
    }

    function setMinimaxStakingAddress(address stakingAddress) external onlyOwner {
        minimaxStaking = stakingAddress;
    }

    function getPositionBalances(uint[] calldata positionIndexes)
        public
        returns (PositionBalanceLib.PositionBalance[] memory)
    {
        return PositionBalanceLib.getMany(positions, poolAdapters, positionIndexes);
    }

    // before calling _stakeToken
    // tokenAmount of stakingToken should be on MinimaxMain contract
    function _stakeToken(
        IERC20Upgradeable stakingToken,
        address stakingPool,
        uint tokenAmount,
        uint maxSlippage,
        uint stopLossPrice,
        uint takeProfitPrice
    ) private returns (uint) {
        require(msg.value >= stakeGelatoFee, "gasTankThreshold");

        validatePosition(stakingToken, stopLossPrice, takeProfitPrice);
        emit PositionWasCreated(lastPositionIndex);

        IPoolAdapter adapter = _getPoolAdapterSafe(stakingPool);
        require(
            adapter.stakedToken(stakingPool, abi.encode(stakingToken)) == address(stakingToken),
            "stakeToken: invalid staking token."
        );
        address rewardToken = adapter.rewardToken(stakingPool, abi.encode(stakingToken));

        uint userFeeAmount = getUserFeeAmount(tokenAmount);
        uint amountToStake = tokenAmount - userFeeAmount;

        uint positionIndex = lastPositionIndex;
        lastPositionIndex += 1;

        ProxyCaller proxy = proxyPool.acquire();
        depositGasTank(proxy);

        positions[positionIndex] = PositionInfo({
            stakedAmount: amountToStake,
            feeAmount: userFeeAmount,
            stopLossPrice: stopLossPrice,
            maxSlippage: maxSlippage,
            poolAddress: stakingPool,
            owner: address(msg.sender),
            callerAddress: proxy,
            closed: false,
            takeProfitPrice: takeProfitPrice,
            stakedToken: stakingToken,
            rewardToken: IERC20Upgradeable(rewardToken),
            gelatoLiquidateTaskId: _gelatoCreateTask(positionIndex)
        });

        proxyDeposit(positions[positionIndex], amountToStake);
        return positionIndex;
    }

    function stakeToken(
        IERC20Upgradeable stakingToken,
        address stakingPool,
        uint tokenAmount,
        uint maxSlippage,
        uint stopLossPrice,
        uint takeProfitPrice
    ) public payable nonReentrant returns (uint) {
        stakingToken.safeTransferFrom(address(msg.sender), address(this), tokenAmount);
        return _stakeToken(stakingToken, stakingPool, tokenAmount, maxSlippage, stopLossPrice, takeProfitPrice);
    }

    function swapStakeTokenOneInch(
        IERC20Upgradeable inputToken,
        IERC20Upgradeable stakingToken,
        address stakingPool,
        uint inputTokenAmount,
        uint maxSlippage,
        uint stopLossPrice,
        uint takeProfitPrice,
        bytes memory oneInchCallData
    ) public payable nonReentrant returns (uint) {
        inputToken.safeTransferFrom(address(msg.sender), address(this), inputTokenAmount);
        require(oneInchRouter != address(0), "no 1inch router set");
        inputToken.approve(oneInchRouter, inputTokenAmount);

        (bool success, bytes memory retData) = oneInchRouter.call(oneInchCallData);
        require(success == true, "calling 1inch got an error");
        (uint actualAmount, ) = abi.decode(retData, (uint, uint));
        return _stakeToken(stakingToken, stakingPool, actualAmount, maxSlippage, stopLossPrice, takeProfitPrice);
    }

    function swapStakeToken(
        IERC20Upgradeable inputToken,
        IERC20Upgradeable stakingToken,
        address stakingPool,
        uint inputTokenAmount,
        uint stakingTokenAmountMin,
        uint maxSlippage,
        uint stopLossPrice,
        uint takeProfitPrice,
        bytes memory hints
    ) public payable nonReentrant returns (uint) {
        require(address(market) != address(0), "no market");
        inputToken.safeTransferFrom(address(msg.sender), address(this), inputTokenAmount);
        inputToken.approve(address(market), inputTokenAmount);
        uint actualAmount = market.swap(
            address(inputToken),
            address(stakingToken),
            inputTokenAmount,
            stakingTokenAmountMin,
            address(this),
            hints
        );
        return _stakeToken(stakingToken, stakingPool, actualAmount, maxSlippage, stopLossPrice, takeProfitPrice);
    }

    function swapStakeTokenEstimate(
        address inputToken,
        address stakingToken,
        uint inputTokenAmount,
        bool tokenInPair,
        bool tokenOutPair
    ) public view returns (uint amountOut, bytes memory hints) {
        require(address(market) != address(0), "no market");
        return market.estimateOut(inputToken, stakingToken, inputTokenAmount, tokenInPair, tokenOutPair);
    }

    function validatePosition(
        IERC20Upgradeable stakingToken,
        uint stopLossPrice,
        uint takeProfitPrice
    ) private {
        IPriceOracle oracle = priceOracles[stakingToken];
        if (stopLossPrice != 0) {
            require(address(oracle) != address(0), "stopLossPrice: price oracle is zero");
        }
        if (takeProfitPrice != 0) {
            require(address(oracle) != address(0), "takeProfitPrice: price oracle is zero");
        }
    }

    function deposit(uint positionIndex, uint amount) external nonReentrant {
        PositionInfo storage position = positions[positionIndex];
        depositImpl(position, positionIndex, amount);
    }

    function setLiquidator(address user, bool value) external onlyOwner {
        isLiquidator[user] = value;
    }

    function withdrawAll(uint positionIndex) external nonReentrant {
        withdrawImpl({positionIndex: positionIndex, amount: 0, amountAll: true});
    }

    function alterPositionParams(
        uint positionIndex,
        uint newAmount,
        uint newStopLossPrice,
        uint newTakeProfitPrice,
        uint newSlippage
    ) external nonReentrant {
        PositionInfo storage position = positions[positionIndex];
        require(position.owner == address(msg.sender), "stop loss may be changed only by position owner");
        validatePosition(position.stakedToken, newStopLossPrice, newTakeProfitPrice);

        position.stopLossPrice = newStopLossPrice;
        position.takeProfitPrice = newTakeProfitPrice;
        position.maxSlippage = newSlippage;

        if (newAmount < position.stakedAmount) {
            uint withdrawAmount = position.stakedAmount - newAmount;
            withdrawImpl({positionIndex: positionIndex, amount: withdrawAmount, amountAll: false});
        } else if (newAmount > position.stakedAmount) {
            uint depositAmount = newAmount - position.stakedAmount;
            depositImpl(position, positionIndex, depositAmount);
        } else {
            emit PositionWasModified(positionIndex);
        }
    }

    function withdraw(uint positionIndex, uint amount) external nonReentrant {
        withdrawImpl({positionIndex: positionIndex, amount: amount, amountAll: false});
    }

    // Always emits `PositionWasClosed`
    function liquidateByIndexImpl(uint positionIndex) private {
        requireReadyForLiquidation(positionIndex);

        PositionInfo storage position = positions[positionIndex];
        position.callerAddress.withdrawAll(
            _getPoolAdapterSafe(position.poolAddress),
            position.poolAddress,
            abi.encode(position.stakedToken) // pass stakedToken for aave pools
        );

        uint stakedAmount = IERC20Upgradeable(position.stakedToken).balanceOf(address(position.callerAddress));

        if (address(position.stakedToken) != busdAddress) {
            // swapToStable transfers stablecoins directly to position owner address
            PositionExchangeLib.swapTo(
                positions[positionIndex],
                getPriceOracleSafe(position.stakedToken),
                getTokenExchangeSafe(position.stakedToken),
                busdAddress,
                stakedAmount
            );
        } else {
            position.callerAddress.transferAll(position.stakedToken, position.owner);
        }

        // Firstly, 'transfer', then 'dumpRewards': order is important here when (rewardToken == CAKE)
        position.callerAddress.transferAll(position.rewardToken, position.owner);

        closePosition(positionIndex);
    }

    function liquidateByIndex(uint positionIndex) external nonReentrant onlyLiquidator {
        liquidateByIndexImpl(positionIndex);
    }

    // May run out of gas if array length is too big!
    function liquidateManyByIndex(uint[] calldata positionIndexes) external nonReentrant onlyLiquidator {
        for (uint i = 0; i < positionIndexes.length; ++i) {
            liquidateByIndexImpl(positionIndexes[i]);
        }
    }

    function proxyDeposit(PositionInfo storage position, uint amount) private {
        position.stakedToken.safeTransfer(address(position.callerAddress), amount);
        position.callerAddress.approve(position.stakedToken, position.poolAddress, amount);
        position.callerAddress.deposit(
            _getPoolAdapterSafe(position.poolAddress),
            position.poolAddress,
            amount,
            abi.encode(position.stakedToken) // pass stakedToken for aave pools
        );
    }

    // Emits `PositionsWasModified` always.
    function depositImpl(
        PositionInfo storage position,
        uint positionIndex,
        uint amount
    ) private {
        emit PositionWasModified(positionIndex);

        require(position.owner == address(msg.sender), "deposit: only position owner allowed");
        require(position.closed == false, "deposit: position is closed");

        position.stakedToken.safeTransferFrom(address(msg.sender), address(this), amount);

        uint userFeeShare = getUserFee();
        uint userFeeAmount = (amount * userFeeShare) / FEE_MULTIPLIER;
        uint amountToDeposit = amount - userFeeAmount;

        position.stakedAmount = position.stakedAmount + amountToDeposit;
        position.feeAmount = position.feeAmount + userFeeAmount;

        proxyDeposit(position, amountToDeposit);
        position.callerAddress.transferAll(position.rewardToken, position.owner);
    }

    // Emits:
    //   * `PositionWasClosed`,   if `amount == position.stakedAmount`.
    //   * `PositionWasModified`, otherwise.
    function withdrawImpl(
        uint positionIndex,
        uint amount,
        bool amountAll
    ) private {
        PositionInfo storage position = positions[positionIndex];

        require(position.owner == address(msg.sender), "withdraw: only position owner allowed");
        require(position.closed == false, "withdraw: position is closed");

        IPoolAdapter poolAdapter = _getPoolAdapterSafe(position.poolAddress);
        if (amountAll) {
            position.callerAddress.withdrawAll(
                poolAdapter,
                position.poolAddress,
                abi.encode(position.stakedToken) // pass stakedToken for aave pools
            );
        } else {
            position.callerAddress.withdraw(
                poolAdapter,
                position.poolAddress,
                amount,
                abi.encode(position.stakedToken) // pass stakedToken for aave pools
            );
        }

        position.callerAddress.transferAll(position.stakedToken, position.owner);
        position.callerAddress.transferAll(position.rewardToken, position.owner);

        uint poolBalance = position.callerAddress.stakingBalance(
            poolAdapter,
            position.poolAddress,
            abi.encode(position.stakedToken)
        );
        if (poolBalance == 0 || amountAll) {
            closePosition(positionIndex);
        } else {
            emit PositionWasModified(positionIndex);
            position.stakedAmount = poolBalance;
        }
    }

    function requireReadyForLiquidation(uint positionIndex) public view {
        require(isReadyForLiquidation(positionIndex), "requireReadyForLiquidation");
    }

    function isReadyForLiquidation(uint positionIndex) public view returns (bool) {
        PositionInfo memory position = positions[positionIndex];
        if (position.closed == true || position.owner == address(0)) {
            return false;
        }
        return PositionExchangeLib.isPriceOutsideRange(position, priceOracles[position.stakedToken]);
    }

    function closePosition(uint positionIndex) private {
        PositionInfo storage position = positions[positionIndex];

        position.closed = true;

        if (isModernProxy(position.callerAddress)) {
            withdrawGasTank(position.callerAddress, position.owner);
            proxyPool.release(position.callerAddress);
        }

        _gelatoCancelTask(position.gelatoLiquidateTaskId);

        emit PositionWasClosed(positionIndex);
    }

    function depositGasTank(ProxyCaller proxy) private {
        address(proxy).call{value: msg.value}("");
    }

    function withdrawGasTank(ProxyCaller proxy, address owner) private {
        proxy.transferNativeAll(owner);
    }

    function isModernProxy(ProxyCaller proxy) public returns (bool) {
        return address(proxy).code.length == 945;
    }

    //
    // Gelato
    //

    struct AutomationParams {
        uint256 positionIndex;
    }

    function automationResolve(uint positionIndex) public view returns (bool canExec, bytes memory execPayload) {
        canExec = isReadyForLiquidation(positionIndex);
        execPayload = abi.encodeWithSelector(this.automationExec.selector, abi.encode(AutomationParams(positionIndex)));
    }

    function automationExec(bytes calldata raw) public onlyAutomator {
        AutomationParams memory params = abi.decode(raw, (AutomationParams));
        gelatoPayFee(params.positionIndex);
        liquidateByIndexImpl(params.positionIndex);
    }

    function gelatoPayFee(uint positionIndex) private {
        (uint feeAmount, address feeToken) = gelatoOps.getFeeDetails();
        if (feeAmount == 0) {
            return;
        }

        require(feeToken == GelatoNativeToken);

        address feeDestination = gelatoOps.gelato();
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
        gelatoOps.cancelTask(gelatoTaskId);
    }
}

