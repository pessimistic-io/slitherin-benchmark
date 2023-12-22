// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {Math} from "./Math.sol";
import {SafeCast} from "./SafeCast.sol";
import {ERC20Permit, ERC20} from "./draft-ERC20Permit.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
import {IAlgebraPool} from "./IAlgebraPool.sol";
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {PositionKey} from "./PositionKey.sol";
import {PoolAddress} from "./PoolAddress.sol";
import {CallbackValidation} from "./CallbackValidation.sol";
import {ILiquidityManager} from "./ILiquidityManager.sol";
import {IAlgebraMintCallback} from "./IAlgebraMintCallback.sol";
import {IDataStorageOperator} from "./IDataStorageOperator.sol";

import {ISwapRouter} from "./ISwapRouter.sol";
import "./ILiquidityManagerFactory.sol";

/// @title LiquidityManager v1.0
/// @notice A Algebra V2-like interface with fungible liquidity to Algebra
/// which allows for arbitrary liquidity provision: one-sided, lop-sided, and balanced
contract LiquidityManager is ILiquidityManager, ERC20Permit, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint128;
    using SafeCast for uint256;

    /*****************************************************************/
    /******************           STRUCTS           ******************/
    /*****************************************************************/

    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    struct MintLiquidityData {
        int24 tickLower; // The lower tick of the position for which to mint liquidity
        int24 tickUpper; // The upper tick of the position for which to mint liquidity
        uint256 amount0Desired; // amount of token0 which we intend to deposit
        uint256 amount1Desired; // amount of token1 which we intend deposit
        uint256 amount0Min; // minimum amount of token0 we require to be deposited to the pool
        uint256 amount1Min; // minimum amount of token1 we require to be deposited to the pool
    }

    struct BurnLiquidityData {
        int24 tickLower; // The lower tick of the position for which to burn liquidity
        int24 tickUpper; // The upper tick of the position for which to burn liquidity
        uint256 liquidity; // The amount of liquidity to burn
        address to; // The address which should receive the fees collected
        bool collectAll; // If true, collect all tokens owed in the pool, else collect the owed tokens of the burn
        uint256 amount0Min; // minimum amount of token0 we want back
        uint256 amount1Min; // minimum amount of token1 we want back
    }

    /*****************************************************************/
    /******************            EVENTS           ******************/
    /*****************************************************************/

    event Deposit(address sender, address to, uint256 amount0, uint256 amount1, uint256 shares);
    event Withdraw(address sender, address to, uint256 amount0, uint256 amount1);
    event Rebalance(int24 tick, uint256 totalAmount0, uint256 totalAmount1);
    event SwapToken(address token, uint256 amountIn, uint256 amountOutMin, uint256 amountOut);
    event SetFeeBP(uint16 newFee);
    event SetRebalancer(address rebalancerAddr);
    event SetWhitelistStatus(address account, bool status);
    event SetMaxTotalSupply(uint256 maxTotalSupply);
    event SetFeeRecipient(address newFeeRecipient);
    event SetIsWhitelistOn(bool value);
    event SetDirectDeposit(bool value);
    event SetDirectDepositRespectingRatio(bool value);
    event Compounded();
    event PullLiquidity(int24 tickLower, int24 tickUpper, uint256 liquidity, uint256 token0Amount, uint256 token1Amount);
    event AlgebraMintCallback(uint256 token0Amount, uint256 token1Amount);
    event MintLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 token0Amount, uint256 token1Amount);
    event BurnLiquidity(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 token0Amount, uint256 token1Amount);
    event FeeCollected(int24 tickLower, int24 tickUpper, uint256 token0Fee, uint256 token1Fee);
    event SetSwapSlippage(uint256 maxSwapSlippage_);

    /*****************************************************************/
    /******************          CONSTANTS         ******************/
    /*****************************************************************/
    ILiquidityManagerFactory factory;
    IAlgebraPool internal immutable POOL;
    ISwapRouter internal immutable SWAP_ROUTER;
    address internal immutable POOL_DEPLOYER;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public constant MAX_SWAP_SLIPPAGE_BP = 5000;

    /*****************************************************************/
    /*****************           STORAGE            ******************/
    /*****************************************************************/

    bool public isWhitelistOn = true;
    mapping(address => bool) public whitelistedAddresses;

    address public rebalancer;
    address public feeRecipient;

    uint256 public maxTotalSupply;
    // Adjust based on tokens volatility type
    uint256 public maxSwapSlippageBP = 500; // 5%
    /**
    * [0]: baseLower
    * [1]: baseUpper
    * [2]: limitLower
    * [3]: limitUpper
    **/
    int24[4] ranges;
    uint16 public constant MAX_FEE_BP = 3000;
    uint16 public feeBP = 1000; // 10%
    bool public directDeposit;
    bool public directDepositRespectingRatio;

    bool internal _MINT_CALLED_;

    /*****************************************************************/
    /******************         CONSTRUCTOR         ******************/
    /*****************************************************************/

    /// @param _pool Algebra pool for which liquidity is managed
    /// @param _feeRecipient Address which receives fees
    /// @param _name Name of the LiquidityManager
    /// @param _symbol Symbol of the LiquidityManager
    /// @param _poolDeployer Address of the pool deployer
    /// @param _swapRouter Address of the swap router
    constructor(address _pool, address token0_, address token1_, address _feeRecipient, string memory _name,
        string memory _symbol, address _poolDeployer, address _swapRouter
    ) ERC20Permit(_name)  ERC20(_name, _symbol) {
        factory = ILiquidityManagerFactory(msg.sender);
        POOL = IAlgebraPool(_pool);
        SWAP_ROUTER = ISwapRouter(_swapRouter);
        token0 = IERC20(token0_);
        token1 = IERC20(token1_);

        POOL_DEPLOYER = _poolDeployer;
        feeRecipient = _feeRecipient;
    }

    /********************************************************************/
    /****************** EXTERNAL ADMIN-ONLY FUNCTIONS  ******************/
    /********************************************************************/

    function setMaxTotalSupply(uint256 maxTotalSupply_) external nonReentrant {
        _onlyAdmin();
        maxTotalSupply = maxTotalSupply_;
        emit SetMaxTotalSupply(maxTotalSupply_);
    }

    function setRebalancer(address rebalancer_) external nonReentrant {
        _onlyAdmin();
        require(rebalancer_ != address(0), "R0");
        rebalancer = rebalancer_;
        emit SetRebalancer(rebalancer_);
    }

    function setWhitelistStatus(address _address, bool value) external nonReentrant {
        _onlyAdmin();
        whitelistedAddresses[_address] = value;
        emit SetWhitelistStatus(_address, value);
    }

    function setSwapSlippage(uint256 maxSwapSlippage_) external {
        _onlyAdmin();
        require(maxSwapSlippage_ < MAX_SWAP_SLIPPAGE_BP, "ITS"); // invalid twap settings
        maxSwapSlippageBP = maxSwapSlippage_;
        emit SetSwapSlippage(maxSwapSlippage_);
    }

    /// @notice set fee
    /// @param newFee new fee
    function setFeeBP(uint16 newFee) external nonReentrant {
        _onlyAdmin();
        require(newFee <= MAX_FEE_BP, "F30");
        feeBP = newFee;
        emit SetFeeBP(newFee);
    }

    /// @notice set fee recipient
    /// @param newFeeRecipient new fee recipient
    function setFeeRecipient(address newFeeRecipient) external nonReentrant {
        _onlyAdmin();
        require(newFeeRecipient != address(0), "FR0");
        feeRecipient = newFeeRecipient;
        emit SetFeeRecipient(newFeeRecipient);
    }

    /// @notice Toggle isWhitelistOn
    function toggleWhitelistOn() external nonReentrant {
        _onlyAdmin();
        bool _isWhitelistOn = !isWhitelistOn;
        isWhitelistOn = _isWhitelistOn;
        emit SetIsWhitelistOn(_isWhitelistOn);
    }

    /// @notice Toggle Direct Deposit
    function toggleDirectDeposit() external nonReentrant {
        _onlyAdmin();
        bool _directDeposit = !directDeposit;
        directDeposit = _directDeposit;
        emit SetDirectDeposit(_directDeposit);
    }

    /// @notice Toggle Direct Deposit
    function toggleDirectDepositRespectingRatio() external nonReentrant {
        _onlyAdmin();
        bool _directDepositRespectingRatio = !directDepositRespectingRatio;
        directDepositRespectingRatio = _directDepositRespectingRatio;
        emit SetDirectDepositRespectingRatio(_directDepositRespectingRatio);
    }

    function swapToken(IERC20 token, uint256 amountIn, uint256 amountOutMin, uint160 limitSqrtPrice)
        external nonReentrant returns (uint256 amountOut)
    {
        _onlyRebalancer();

        require(amountIn != 0 && (address(token) == address(token0) || address(token) == address(token1)), "SP"); // invalid swap params

        // Check if limitSqrtPrice does not exceed maxSwapSlippageBP of twap price
        require(!validateSlippageFromTick(maxSwapSlippageBP, getCurrentTick(), TickMath.getTickAtSqrtRatio(limitSqrtPrice)), "MSP"); // limitSqrtPrice exceed maxPriceChange threshold

        token.safeApprove(address(SWAP_ROUTER), 0);
        token.safeApprove(address(SWAP_ROUTER), amountIn);

        amountOut = SWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token),
                tokenOut: address(token == token0 ? token1 : token0),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                limitSqrtPrice: limitSqrtPrice
            })
        );

        emit SwapToken(address(token), amountIn, amountOutMin, amountOut);
    }

    /// @notice Compound available tokens
    /// @param inMax max spend into each position
    /// @param inMin min spend into each position
    function compound(uint256[4] calldata inMax, uint256[4] calldata inMin) external nonReentrant {
        _onlyRebalancer();

        // update fees for compounding
        _settleBaseAndLimit();

        _mintLiquidity(
            MintLiquidityData({
                tickLower: ranges[0], // baseLower
                tickUpper: ranges[1], // baseUpper
                amount0Desired: Math.min(_token0Balance(), inMax[0]),
                amount1Desired: Math.min(_token1Balance(), inMax[1]),
                amount0Min: inMin[0],
                amount1Min: inMin[1]
            })
        );

        _mintLiquidity(
            MintLiquidityData({
                tickLower: ranges[2], // tickLower
                tickUpper: ranges[3], // tickUpper
                amount0Desired: Math.min(_token0Balance(), inMax[2]),
                amount1Desired: Math.min(_token1Balance(), inMax[3]),
                amount0Min: inMin[2],
                amount1Min: inMin[3]
            })
        );
        emit Compounded();
    }

    /// @notice Pull liquidity tokens from liquidity and receive the tokens
    /// @param tickLower lower tick
    /// @param tickUpper upper tick
    /// @param shares Number of liquidity tokens to pull from liquidity
    /// @param amountMin min outs
    /// @return amount0 amount of TOKEN_0 received from base position
    /// @return amount1 amount of TOKEN_1 received from base position
    function pullLiquidity(int24 tickLower, int24 tickUpper, uint128 shares, uint256[2] calldata amountMin)
        external nonReentrant returns (uint256 amount0, uint256 amount1)
    {
        _onlyAdmin();
        _settle(tickLower, tickUpper);
        uint256 liquidity = _liquidityForShares(tickLower, tickUpper, shares);
        (amount0, amount1) = _burnLiquidity(
            BurnLiquidityData({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidity: liquidity,
                to: address(this),
                collectAll: false,
                amount0Min: amountMin[0],
                amount1Min: amountMin[1]
            })
        );
        emit PullLiquidity(tickLower, tickUpper, liquidity, amount0, amount1);
    }

    /// @notice Rebalance the pool
    /// @param ranges_[0] The lower tick of the base position
    /// @param ranges_[1] The upper tick of the base position
    /// @param ranges_[2] The lower tick of the limit position
    /// @param ranges_[3] The upper tick of the limit position
    /// @param inMax spend into each position
    /// @param inMin min spend
    /// @param outMin min amount0,1 returned for shares of liq
    function rebalance(int24[4] calldata ranges_, uint256[4] calldata inMax,
        uint256[4] calldata inMin, uint256[4] calldata outMin) external nonReentrant
    {
        _onlyRebalancer();

        int24 spacing = tickSpacing();
        require(ranges_[0] < ranges_[1] && ranges_[0] % spacing == 0 && ranges_[1] % spacing == 0 &&
                ranges_[2] < ranges_[3] && ranges_[2] % spacing == 0 && ranges_[3] % spacing == 0, "IT"); // invalid ticks

        require(ranges_[3] != ranges_[1] || ranges_[2] != ranges_[0], "IBL");
        { // avoids stack too deep
            /// collect fees
            _settleBaseAndLimit();

            int24[4] storage _ranges = ranges;
            (uint256 baseLiquidity,,) = _position(_ranges[0], _ranges[1]);
            (uint256 limitLiquidity,,) = _position(_ranges[2], _ranges[3]);

            /// Withdraw all liquidity from Algebra pool
            _burnLiquidity(
                BurnLiquidityData({
                    tickLower: _ranges[0], // baseLower
                    tickUpper: _ranges[1], // baseUpper
                    liquidity: baseLiquidity,
                    to: address(this),
                    collectAll: true,
                    amount0Min: outMin[0],
                    amount1Min: outMin[1]
                })
            );

            _burnLiquidity(
                BurnLiquidityData({
                    tickLower: _ranges[2], // limitLower
                    tickUpper: _ranges[3], // limitUpper
                    liquidity: limitLiquidity,
                    to: address(this),
                    collectAll: true,
                    amount0Min: outMin[2],
                    amount1Min: outMin[3]
                })
            );

            emit Rebalance(getCurrentTick(), _token0Balance(), _token1Balance());
        }

        ranges = ranges_;

        _mintLiquidity(
            MintLiquidityData({
                tickLower: ranges_[0],
                tickUpper: ranges_[1],
                amount0Desired: Math.min(_token0Balance(), inMax[0]),
                amount1Desired: Math.min(_token1Balance(), inMax[1]),
                amount0Min: inMin[0],
                amount1Min: inMin[1]
            })
        );

        _mintLiquidity(
            MintLiquidityData({
                tickLower: ranges_[2],
                tickUpper: ranges_[3],
                amount0Desired: Math.min(_token0Balance(), inMax[2]),
                amount1Desired: Math.min(_token1Balance(), inMax[3]),
                amount0Min: inMin[2],
                amount1Min: inMin[3]
            })
        );
    }


    /********************************************************************/
    /******************       EXTERNAL FUNCTIONS       ******************/
    /********************************************************************/

    /// @notice Deposit tokens
    /// @param deposit0 Amount of TOKEN_0 transfered from sender to LiquidityManager
    /// @param deposit1 Amount of TOKEN_1 transfered from sender to LiquidityManager
    /// @param to Address to which liquidity tokens are minted
    /// @param inMin min spend for directDeposit is true
    /// @return shares Quantity of liquidity tokens minted as a result of deposit
    function deposit(uint256 deposit0, uint256 deposit1, address to, uint256[4] calldata inMin) external nonReentrant
        returns (uint256 shares)
    {
        require((deposit0 > 0 || deposit1 > 0) && to != address(0) && to != address(this), "DP"); // invalid deposit params

        address from = msg.sender;

        require(!isWhitelistOn || whitelistedAddresses[from], "WHE");

        /// update fees
        _settleBaseAndLimit();

        uint256 total = totalSupply();
        if(total == 0) {
            if (deposit0 > 0) token0.safeTransferFrom(from, address(this), deposit0);
            if (deposit1 > 0) token1.safeTransferFrom(from, address(this), deposit1);
            shares = Math.max(deposit0, deposit1);
            require(shares > 1e6);
            _mint(0x000000000000000000000000000000000000dEaD, 1e6);
            shares -= 1e6;
        }
        else {
            (uint256 pool0, uint256 pool1) = getTotalAmounts();
            if(pool0 == 0) {
                require(deposit0 == 0, "ID0"); // Invalid deposit0
                shares = deposit1 * total / pool1;
            } else if(pool1 == 0) {
                require(deposit1 == 0, "ID1"); // Invalid deposit1
                shares = deposit0 * total / pool0;
            } else {
                require(deposit0 > 0 && deposit1 > 0, "ID"); // Invalid deposits
                uint256 cross = Math.min(deposit0 * pool1, deposit1 * pool0);

                deposit0 = ((cross - 1) / pool1) + 1;
                deposit1 = ((cross - 1) / pool0) + 1;
                shares = cross * total / pool0 / pool1;
            }

            if (deposit0 > 0) token0.safeTransferFrom(from, address(this), deposit0);
            if (deposit1 > 0) token1.safeTransferFrom(from, address(this), deposit1);

            if (directDeposit) {

                uint256 inBaseMax0 = _token0Balance();
                uint256 inBaseMax1 = _token1Balance();

                if(directDepositRespectingRatio) {
                    (,uint256 base0, uint256 base1) = getBasePosition();
                    (,uint256 limit0, uint256 limit1) = getLimitPosition();
                    uint256 base0Ratio = base0 + limit0 > 0 ? base0 * 1e18 / (base0 + limit0) : 0;
                    uint256 base1Ratio = base1 + limit1 > 0 ? base1 * 1e18 / (base1 + limit1) : 0;
                    inBaseMax0 = inBaseMax0 * base0Ratio / 1e18;
                    inBaseMax1 = inBaseMax1 * base1Ratio / 1e18;
                }

                _mintLiquidity(
                    MintLiquidityData({
                        tickLower: ranges[0], // baseLower
                        tickUpper: ranges[1], // baseUpper
                        amount0Desired: inBaseMax0,
                        amount1Desired: inBaseMax1,
                        amount0Min: inMin[0],
                        amount1Min: inMin[1]
                    })
                );
                _mintLiquidity(
                    MintLiquidityData({
                        tickLower: ranges[2], // limitLower
                        tickUpper: ranges[3], // limitUpper
                        amount0Desired: _token0Balance(),
                        amount1Desired: _token1Balance(),
                        amount0Min: inMin[2],
                        amount1Min: inMin[3]
                    })
                );
            }
        }
        _mint(to, shares);
        emit Deposit(from, to, deposit0, deposit1, shares);
        /// Check total supply cap not exceeded. A value of 0 means no limit.
        require(maxTotalSupply == 0 || totalSupply() <= maxTotalSupply, "MS");
    }

    /// @param shares Number of liquidity tokens to redeem as pool assets
    /// @param to Address to which redeemed pool assets are sent
    /// @param minAmounts min amount0,1 returned for shares of liq
    /// @return amount0 Amount of TOKEN_0 redeemed by the submitted liquidity tokens
    /// @return amount1 Amount of TOKEN_1 redeemed by the submitted liquidity tokens
    function withdraw(uint256 shares, address to, uint256[4] calldata minAmounts) external nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(shares > 0 && to != address(0), "WP"); // invalid deposit params

        /// collect fees
        _settleBaseAndLimit();

        /// Withdraw liquidity from Algebra pool
        (uint256 base0, uint256 base1) = _burnLiquidity(
            BurnLiquidityData({
                tickLower: ranges[0], // baseLower
                tickUpper: ranges[1], // baseUpper
                liquidity: _liquidityForShares(ranges[0], ranges[1], shares),
                to: to,
                collectAll: false,
                amount0Min: minAmounts[0],
                amount1Min: minAmounts[1]
            })
        );

        (uint256 limit0, uint256 limit1) = _burnLiquidity(
            BurnLiquidityData({
                tickLower: ranges[2], // limitLower
                tickUpper: ranges[3], // limitUpper
                liquidity: _liquidityForShares(ranges[2], ranges[3], shares),
                to: to,
                collectAll: false,
                amount0Min: minAmounts[2],
                amount1Min: minAmounts[3]
            })
        );

        // Push tokens proportional to unused balances
        uint256 totalSupply = totalSupply();
        uint256 unusedAmount0 = (_token0Balance() * shares) / totalSupply;
        uint256 unusedAmount1 = (_token1Balance() * shares) / totalSupply;

        _safeTransfer(token0, to, unusedAmount0);
        _safeTransfer(token1, to, unusedAmount1);

        amount0 = base0 + limit0 + unusedAmount0;
        amount1 = base1 + limit1 + unusedAmount1;

        _burn(msg.sender, shares);

        emit Withdraw(msg.sender, to, amount0, amount1);
    }

    /// @inheritdoc IAlgebraMintCallback
    function algebraMintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(msg.sender == address(POOL), "SNP");

        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        require(decoded.payer == address(this) && _MINT_CALLED_ == true, "PNT");

        _MINT_CALLED_ = false;

        CallbackValidation.verifyCallback(POOL_DEPLOYER, decoded.poolKey);

        _safeTransfer(IERC20(decoded.poolKey.token0), address(POOL), amount0);
        _safeTransfer(IERC20(decoded.poolKey.token1), address(POOL), amount1);

        emit AlgebraMintCallback(amount0, amount1);
    }

    function collectAllFees() external nonReentrant returns (uint256 baseFees0, uint256 baseFees1, uint256 limitFees0, uint256 limitFees1) {
        (baseFees0, baseFees1) = _settle(ranges[0], ranges[1]);
        (limitFees0, limitFees1) = _settle(ranges[2], ranges[3]);
    }

    /********************************************************************/
    /******************        PUBLIC VIEWS FUNCTIONS        ******************/
    /********************************************************************/

    function admin() public view returns (address) {
        return factory.owner();
    }

    /// @notice getter for the algebra pool
    function pool() external view returns (IAlgebraPool) {
        return POOL;
    }

    function positionsSettings() external view returns (int24 baseLower, int24 baseUpper, int24 limitLower, int24 limitUpper) {
        baseLower = ranges[0];
        baseUpper = ranges[1];
        limitLower = ranges[2];
        limitUpper = ranges[3];
    }

    function validateSlippageFromTick(uint256 maxSlippageBP, int24 fromTick, int24 toTick) public virtual view returns (bool hasExceedThreshold) {
        int256 tickDifference = toTick > fromTick ? int256(toTick - fromTick) : int256(fromTick - toTick);
        uint256 tickDifferenceAbs = tickDifference > 0 ? uint256(tickDifference): uint256(-tickDifference);
        hasExceedThreshold = tickDifferenceAbs > maxSlippageBP;
    }

    /// @notice getter for the current tick spacing
    function tickSpacing() public view returns (int24 spacing) {
        return POOL.tickSpacing();
    }

    /// @notice Get the current sqrt ratio of the pool
    /// @return sqrtPriceX96 The current sqrt ratio of the pool
    function getCurrentSqrtRatioX96() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,) = _poolGlobalStates();
    }

    /// @notice Get the current tick of the pool
    /// @return tick The current tick of the pool
    function getCurrentTick() public view virtual returns (int24 tick) {
        (, tick) = _poolGlobalStates();
    }

    function dataStorageOperator() public view virtual returns (address) {
        return POOL.dataStorageOperator();
    }

    /// @notice get the sqrt ratio at a particular tick
    /// @param tick The tick to get the sqrt ratio for
    /// @return sqrtRatioX96 The sqrt ratio at the given tick
    function getSqrtRatioAtTick(int24 tick) public pure returns (uint160 sqrtRatioX96) {
        sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
    }

    /// @notice Get total amounts of TOKEN_0 and TOKEN_1 deposited (in positions and unused)
    /// @return total0 Quantity of TOKEN_0 in both positions and unused
    /// @return total1 Quantity of TOKEN_1 in both positions and unused
    function getTotalAmounts() public view virtual returns (uint256 total0, uint256 total1) {
        (, uint256 base0, uint256 base1) = getBasePosition();
        (, uint256 limit0, uint256 limit1) = getLimitPosition();
        total0 = _token0Balance() + base0 + limit0;
        total1 = _token1Balance() + base1 + limit1;
    }

    /// @notice Get total amounts of TOKEN_0 and TOKEN_1 by shares (in positions and unused)
    /// @return total0 Quantity of TOKEN_0 in both positions and unused
    /// @return total1 Quantity of TOKEN_1 in both positions and unused
    function getTotalAmountsForShares(uint256 shares) external returns (uint256 total0, uint256 total1) {
        _settleBaseAndLimit();
        (total0, total1) = getTotalAmounts();
        total0 = shares * total0 / totalSupply();
        total1 = shares * total1 / totalSupply();
    }

    /// @notice Get the base position token0, token1 and liquidity amounts
    /// @return liq Amount of total liquidity in the base position
    /// @return amount0 Estimated amount of TOKEN_0 that could be collected by
    /// burning the base position
    /// @return amount1 Estimated amount of TOKEN_1 that could be collected by
    /// burning the base position
    function getBasePosition() public view returns (uint256 liq, uint256 amount0, uint256 amount1){
        (uint256 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = _position(ranges[0], ranges[1]);
        (amount0, amount1) = _amountsForLiquidity(ranges[0], ranges[1], positionLiquidity);
        amount0 = amount0 + uint256(tokensOwed0);
        amount1 = amount1 + uint256(tokensOwed1);
        liq = positionLiquidity;
    }

    /// @notice Get the limit position token0, token1 and liquidity amounts
    /// @return liq Amount of total liquidity in the limit position
    /// @return amount0 Estimated amount of TOKEN_0 that could be collected by
    /// burning the limit position
    /// @return amount1 Estimated amount of TOKEN_1 that could be collected by
    /// burning the limit position
    function getLimitPosition() public view returns (uint256 liq, uint256 amount0, uint256 amount1) {
        (uint256 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = _position(ranges[2], ranges[3]);
        (amount0, amount1) = _amountsForLiquidity(ranges[2], ranges[3], positionLiquidity);
        amount0 = amount0 + uint256(tokensOwed0);
        amount1 = amount1 + uint256(tokensOwed1);
        liq = positionLiquidity;
    }

    /********************************************************************/
    /******************       INTERNAL FUNCTIONS       ******************/
    /********************************************************************/

    /**
     * @dev Throws if called by any account other than the factory's owner.
     */
    function _onlyAdmin() internal view {
        require(admin() == msg.sender, "OA");
    }

    /**
     * @dev Throws if called by any account other than the rebalancer.
     */
    function _onlyRebalancer() internal view {
        require(rebalancer == msg.sender, "OR");
    }

    function _token0Balance() internal view returns (uint256) {
        return token0.balanceOf(address(this));
    }

    function _token1Balance() internal view returns (uint256) {
        return token1.balanceOf(address(this));
    }

    function _poolGlobalStates() internal view returns (uint160 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick,,,,,) = POOL.globalState();
    }

    function _settleBaseAndLimit() internal {
        _settle(ranges[0], ranges[1]);
        _settle(ranges[2], ranges[3]);
    }

    function _mintLiquidity(MintLiquidityData memory payload) internal {
        uint128 liq = _liquidityForAmounts(payload.tickLower, payload.tickUpper, payload.amount0Desired, payload.amount1Desired);
        if (liq > 0) {
            _MINT_CALLED_ = true;
            PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
                token0: address(token0),
                token1: address(token1)
            });

            (uint256 amount0, uint256 amount1, uint128 liquidity) = POOL.mint(
                address(this), address(this), payload.tickLower, payload.tickUpper,
                liq, abi.encode(MintCallbackData({poolKey: poolKey, payer: address(this)}))
            );

            require(amount0 >= payload.amount0Min && amount1 >= payload.amount1Min, "PSC");
            emit MintLiquidity(payload.tickLower, payload.tickUpper, liquidity, amount0, amount1);
        }
    }

    function _burnLiquidity(BurnLiquidityData memory payload) internal returns (uint256 amount0, uint256 amount1) {
        if (payload.liquidity > 0) {
            /// Burn liquidity
            (uint256 owed0, uint256 owed1) = _burnPosition(payload.tickLower, payload.tickUpper, uint128(payload.liquidity));
            require(owed0 >= payload.amount0Min && owed1 >= payload.amount1Min, "PSC");

            // Collect amount owed
            uint128 collect0 = payload.collectAll ? type(uint128).max: uint128(owed0);
            uint128 collect1 = payload.collectAll ? type(uint128).max: uint128(owed1);
            if (collect0 > 0 || collect1 > 0) {
                (amount0, amount1) = _collectFromPosition(payload.to, payload.tickLower, payload.tickUpper, collect0, collect1);
            }
            emit BurnLiquidity(payload.tickLower, payload.tickUpper, uint128(payload.liquidity), amount0, amount1);
        }
    }

    function _settle(int24 tickLower, int24 tickUpper) internal returns (uint256 owed0, uint256 owed1) {
        (uint256 liq,,) = _position(tickLower, tickUpper);
        if (liq > 0) {
            _burnPosition(tickLower, tickUpper, 0);

            (owed0, owed1) = _collectFromPosition(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);

            if(feeBP > 0 && feeRecipient != address(0)) {
                _safeTransfer(token0, feeRecipient, owed0 * feeBP / 10000);
                _safeTransfer(token1, feeRecipient, owed1 * feeBP / 10000);
            }

            emit FeeCollected(tickLower, tickUpper, owed0, owed1);
        }
    }

    function _burnPosition(int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = POOL.burn(tickLower, tickUpper, liquidity);
    }

    function _collectFromPosition(address to, int24 tickLower, int24 tickUpper, uint128 collect0Max, uint128 collect1Max)
        internal returns (uint256 amount0Collected, uint256 amount1Collected)
    {
        (amount0Collected, amount1Collected) = POOL.collect(to, tickLower, tickUpper, collect0Max, collect1Max);
    }

    function _liquidityForShares(int24 tickLower, int24 tickUpper, uint256 shares) internal view returns (uint128) {
        (uint256 position, ,) = _position(tickLower, tickUpper);
        return uint128((uint256(position) * shares) / totalSupply());
    }

    function _position(int24 tickLower, int24 tickUpper) internal view returns (uint256 liq, uint128 tokensOwed0, uint128 tokensOwed1){
        (liq, , , tokensOwed0, tokensOwed1) = POOL.positions(PositionKey.compute(address(this), tickLower, tickUpper));
    }

    function _amountsForLiquidity(int24 tickLower, int24 tickUpper, uint256 liq) internal view returns (uint256, uint256){
        return LiquidityAmounts.getAmountsForLiquidity(getCurrentSqrtRatioX96(), TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper), uint128(liq));
    }

    function _liquidityForAmounts(int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1) internal view returns (uint128){
        return LiquidityAmounts.getLiquidityForAmounts(getCurrentSqrtRatioX96(), TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper), amount0, amount1);
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        if(amount > 0) token.safeTransfer(to, amount);
    }
}

