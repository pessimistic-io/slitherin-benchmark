//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.4;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./IERC20Metadata.sol";

import "./IFlashLoanReceiver.sol";
import "./ILiquidityPool.sol";
import "./IMarket.sol";
import "./IPrice.sol";
import "./IUniswapV3Router.sol";
import "./IWeth.sol";
import "./IxTokenManager.sol";
import "./BlockLock.sol";

contract xAssetLev is
    Initializable,
    IFlashLoanReceiver,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    BlockLock
{
    struct TokenAddresses {
        address baseToken;
        address weth;
        address usdc;
    }

    struct LendingAddresses {
        address liquidityPool;
        address market;
        address price;
    }

    struct FeeDivisors {
        uint256 mintFee;
        uint256 burnFee;
    }

    struct SupplyData {
        uint256 totalCap;
        uint256 userCap;
        uint256 initialSupplyMultiplier;
    }

    struct LeverageFunctionParams {
        bool checkNav;
        bool multiHop;
        uint256 maxNavLoss;
        bytes tradePath;
    }

    struct LiquidityBuffer {
        bool active;
        uint256 amount;
    }

    //--------------------------------------------------------------------------
    // State variables
    //--------------------------------------------------------------------------

    uint256 internal constant MAX_UINT = 2**256 - 1;

    IERC20Metadata public baseToken;
    IERC20Metadata private usdc;
    IWeth private weth;

    ILiquidityPool private liquidityPool;
    IMarket private market;
    IPrice private priceFeed;

    IUniswapV3Router private uniswapV3Router;
    uint24 private uniswapFee;

    IxTokenManager private xTokenManager;

    FeeDivisors public feeDivisors;
    SupplyData public supplyData;
    LiquidityBuffer public liquidityBuffer;

    uint256 public claimableFees;

    uint256 private baseTokenMultiplier;
    uint256 private priceFeedDivisor;
    uint256 private lendingDivisor;
    uint256 private usdcToBaseTokenMultiplier;
    uint256 private baseTokenToUSDCFactor;

    //--------------------------------------------------------------------------
    // Events
    //--------------------------------------------------------------------------

    event Levered(uint256 depositAmount, uint256 borrowAmount, uint256 swapReturn);
    event Delevered(uint256 withdrawAmount, uint256 swapReturn);
    event CollateralWithdraw(uint256 collateral);
    event CollateralDeposit(uint256 collateral);

    //--------------------------------------------------------------------------
    // Modifiers
    //--------------------------------------------------------------------------

    /**
     * @dev Enforce functions only called by management.
     */
    modifier onlyOwnerOrManager() {
        require(msg.sender == owner() || xTokenManager.isManager(msg.sender, address(this)), "Non-admin caller");
        _;
    }

    /**
     * @dev Reverts the transaction if the operation causes a nav loss greater than the tolerance.
     *
     * @param check Performs the check if true
     * @param maxNavLoss The nav loss tolerance, ignored if check is false
     */
    modifier checkNavLoss(bool check, uint256 maxNavLoss) {
        uint256 navBefore;
        uint256 navAfter;

        if (check) {
            (uint256 marketBalance, uint256 bufferBalance) = getFundBalances();
            navBefore = (marketBalance + bufferBalance);

            _;

            (marketBalance, bufferBalance) = getFundBalances();
            navAfter = (marketBalance + bufferBalance);

            require(navAfter >= navBefore - maxNavLoss, "NAV loss greater than tolerance");
        } else {
            _;
        }
    }

    receive() external payable {
        require(msg.sender != tx.origin, "Errant ETH deposit");
    }

    //--------------------------------------------------------------------------
    // Constructor / Initializer
    //--------------------------------------------------------------------------

    /**
     * @dev Initializes this leverage asset
     *
     * @param _symbol The token ticker
     * @param _tokens The tokens needed
     * @param _lending The lending contract addresses
     * @param _uniswapV3Router The uniswap router
     * @param _uniswapFee The uniswap pool fee
     * @param _xTokenManager The xtoken manager contract
     * @param _feeDivisors The fee divisors
     * @param _supplyData The supply data
     * @param _liquidityBuffer The liquidity buffer
     */
    function initialize(
        string calldata _symbol,
        TokenAddresses calldata _tokens,
        LendingAddresses calldata _lending,
        IUniswapV3Router _uniswapV3Router,
        uint24 _uniswapFee,
        IxTokenManager _xTokenManager,
        FeeDivisors calldata _feeDivisors,
        SupplyData calldata _supplyData,
        LiquidityBuffer calldata _liquidityBuffer
    ) external initializer {
        __ERC20_init("xAssetLev", _symbol);
        __Ownable_init_unchained();
        __Pausable_init_unchained();

        // lending contracts
        market = IMarket(_lending.market);
        liquidityPool = ILiquidityPool(_lending.liquidityPool);
        priceFeed = IPrice(_lending.price);

        // token contracts
        baseToken = IERC20Metadata(_tokens.baseToken);
        usdc = IERC20Metadata(_tokens.usdc);
        weth = IWeth(_tokens.weth);

        // uniswap
        uniswapV3Router = _uniswapV3Router;
        uniswapFee = _uniswapFee;

        xTokenManager = _xTokenManager;

        feeDivisors = _feeDivisors;
        supplyData = _supplyData;
        liquidityBuffer = _liquidityBuffer;

        // token approvals for uniswap swap router
        usdc.approve(address(uniswapV3Router), MAX_UINT);
        baseToken.approve(address(uniswapV3Router), MAX_UINT);
        weth.approve(address(uniswapV3Router), MAX_UINT);

        // token approvals for xtoken lending
        baseToken.approve(address(market), MAX_UINT);
        usdc.approve(address(liquidityPool), MAX_UINT);

        // set the decimals converters
        baseTokenMultiplier = 10**baseToken.decimals();
        priceFeedDivisor = 10**12;
        lendingDivisor = 10**18;
        usdcToBaseTokenMultiplier = 10**(usdc.decimals() + baseToken.decimals());
        baseTokenToUSDCFactor = baseToken.decimals() < usdc.decimals()
            ? 10**(usdc.decimals() - baseToken.decimals())
            : 10**(baseToken.decimals() - usdc.decimals());
    }

    //--------------------------------------------------------------------------
    // For Investors
    //--------------------------------------------------------------------------

    /**
     * @dev Mint leveraged asset tokens with ETH
     *
     * @param minReturn The minimum return for the ETH trade
     */
    function mint(uint256 minReturn) external payable notLocked(msg.sender) whenNotPaused {
        require(msg.value > 0, "Must send ETH");
        _lock(msg.sender);

        // make the deposit to weth
        uint256 ethAmount = msg.value;
        weth.deposit{ value: ethAmount }();

        // swap for base token if weth is not the base token
        uint256 baseTokenAmount;
        if (address(baseToken) == address(weth)) {
            baseTokenAmount = ethAmount;
        } else {
            baseTokenAmount = _swapExactInputForOutput(address(weth), address(baseToken), ethAmount, minReturn);
        }

        uint256 fee = baseTokenAmount / feeDivisors.mintFee;
        _incrementFees(fee);

        _mintInternal(msg.sender, baseTokenAmount - fee, totalSupply());
    }

    /**
     * @dev Mint leveraged asset tokens with the base token
     *
     * @param inputAssetAmount The amount of base tokens used to mint
     */
    function mintWithToken(uint256 inputAssetAmount) external notLocked(msg.sender) whenNotPaused {
        require(inputAssetAmount > 0, "Must send token");
        _lock(msg.sender);

        baseToken.transferFrom(msg.sender, address(this), inputAssetAmount);

        uint256 fee = inputAssetAmount / feeDivisors.mintFee;
        _incrementFees(fee);

        _mintInternal(msg.sender, inputAssetAmount - fee, totalSupply());
    }

    /**
     * @dev Burns the leveraged asset token for the base token or ETH
     *
     * @param xassetAmount The amount to burn
     * @param redeemForEth True to return ETH, false otherwise
     * @param minReturn The minimum return to swap from base token to ETH, unused if not redeeming for Eth
     */
    function burn(
        uint256 xassetAmount,
        bool redeemForEth,
        uint256 minReturn
    ) external notLocked(msg.sender) {
        require(xassetAmount > 0, "Must send token");
        _lock(msg.sender);
        (uint256 marketBalance, uint256 bufferBalance) = getFundBalances();

        // Conversion between xasset and base token
        uint256 proRataTokens = ((marketBalance + bufferBalance) * xassetAmount) / totalSupply();
        require(proRataTokens + getLiquidityBuffer() <= bufferBalance, "Insufficient exit liquidity");
        // Determine fee and tokens owed to user
        uint256 fee = proRataTokens / feeDivisors.burnFee;
        uint256 userTokens = proRataTokens - fee;

        // Increment the claimable fees
        _incrementFees(fee);

        if (redeemForEth) {
            uint256 userEth;

            // If the base token is weth there's no need to swap on open market
            if (address(baseToken) == address(weth)) {
                userEth = userTokens;
            } else {
                // swap from base token to weth
                userEth = _swapExactInputForOutput(address(baseToken), address(weth), userTokens, minReturn);
            }
            weth.withdraw(userEth);

            // Send eth
            (bool success, ) = msg.sender.call{ value: userEth }(new bytes(0));
            require(success, "ETH  transfer failed");
        } else {
            baseToken.transfer(msg.sender, userTokens);
        }

        _burn(msg.sender, xassetAmount);
    }

    /**
     * @notice Add block lock functionality to token transfers
     */
    function transfer(address recipient, uint256 amount) public override notLocked(msg.sender) returns (bool) {
        require(balanceOf(recipient) + amount <= supplyData.userCap, "Transfer exceeds user cap");
        return super.transfer(recipient, amount);
    }

    /**
     * @notice Add block lock functionality to token transfers
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override notLocked(sender) returns (bool) {
        require(balanceOf(recipient) + amount <= supplyData.userCap, "Transfer exceeds user cap");
        return super.transferFrom(sender, recipient, amount);
    }

    //--------------------------------------------------------------------------
    // View Functions
    //--------------------------------------------------------------------------

    /**
     * @dev Returns the buffer balance without including fees
     *
     * @return The buffer balance
     */
    function getBufferBalance() public view returns (uint256) {
        return baseToken.balanceOf(address(this)) - claimableFees;
    }

    /**
     * @dev Returns the liquidity buffer amount based on if it's active or not
     *
     * @return 0 if inactive, buffer amount if active
     */
    function getLiquidityBuffer() public view returns (uint256) {
        return liquidityBuffer.active ? liquidityBuffer.amount : 0;
    }

    /**
     * @dev Get the withdrawable fee amounts
     *
     * @return feeAsset The fee asset
     * @return feeAmount The withdrawable amount
     */
    function getWithdrawableFees() public view returns (address feeAsset, uint256 feeAmount) {
        feeAsset = address(baseToken);
        feeAmount = claimableFees;
    }

    /**
     * @dev This function could revert if collateral < debt, since this contract is liquidation proof.
     *
     * @return marketBalance The value of the contract's collateral minus the contract's debt
     * @return bufferBalance The buffer balance
     */
    function getFundBalances() public view returns (uint256 marketBalance, uint256 bufferBalance) {
        uint256 collateral = market.collateral(address(this)); // 18 decimals
        uint256 usdDenominatedDebt = liquidityPool.updatedBorrowBy(address(this)); // 18 decimals

        // convert collateral to baseToken decimals
        uint256 parsedCollateral = (collateral * baseTokenMultiplier) / lendingDivisor; // baseToken decimals

        // Get the asset price in usdc
        uint256 assetUsdPrice = priceFeed.getPrice(); // 12 decimals
        uint256 assetUsdPriceAdjusted = (assetUsdPrice * baseTokenMultiplier) / priceFeedDivisor; // baseToken decimals

        // convert usd denominated debt to base token terms
        uint256 baseTokenDenominatedDebt = (usdDenominatedDebt * baseTokenMultiplier * baseTokenMultiplier) /
            lendingDivisor /
            assetUsdPriceAdjusted; // baseToken decimals

        require(parsedCollateral >= baseTokenDenominatedDebt, "Debt is greater than collateral");
        marketBalance = parsedCollateral - baseTokenDenominatedDebt;
        bufferBalance = getBufferBalance();
    }

    /**
     * @dev Calculates the mint amount based on current supply
     *
     * @param incrementalToken The amount of base tokens used for minting
     * @param totalSupply The current totalSupply of xAssetLev
     *
     * @return The mint amount
     */
    function calculateMintAmount(uint256 incrementalToken, uint256 totalSupply) public view returns (uint256) {
        if (totalSupply == 0) {
            return incrementalToken * supplyData.initialSupplyMultiplier;
        }

        (uint256 marketBalance, uint256 bufferBalance) = getFundBalances();
        require((marketBalance + bufferBalance) > incrementalToken, "NAV too low for minting");
        uint256 navBefore = (marketBalance + bufferBalance) - incrementalToken;
        return (incrementalToken * totalSupply) / navBefore;
    }

    //--------------------------------------------------------------------------
    // Management
    //--------------------------------------------------------------------------

    /**
     * @dev Creates the leveraged position
     *
     * @param depositAmount The amount to be deposited.
     * @param borrowAmount The amount to be borrowed.
     * @param params The leverage function params.
     *
     * @dev When swapping usdc for baseToken on the open market, it is possible (probable even) that the asset price will
     *      be different than xLending's internal asset price. When the open market places a higher value on the baseToken
     *      asset than xLending, the NAV of the contract will go down. The maxNavLoss parameter is the maximum tolerance
     *      of NAV loss. Conversely, if the open market places a lower value on the baseToken asset than xLending, the
     *      NAV of the contract will go up.
     */
    function lever(
        uint256 depositAmount,
        uint256 borrowAmount,
        LeverageFunctionParams calldata params
    ) public onlyOwnerOrManager checkNavLoss(params.checkNav, params.maxNavLoss) {
        // Create the leveraged position
        require(depositAmount <= getBufferBalance(), "Deposit amount too large");

        // It's possible to not need to collateralize and only borrow
        if (depositAmount > 0) {
            market.collateralize(depositAmount);
        }
        liquidityPool.borrow(borrowAmount);
        // => swap usdc for baseToken
        uint256 swapReturn;
        if (params.multiHop) {
            swapReturn = _swapExactInputForOutputMultiHop(params.tradePath, borrowAmount, 0);
        } else {
            swapReturn = _swapExactInputForOutput(address(usdc), address(baseToken), borrowAmount, 0);
        }

        emit Levered(depositAmount, borrowAmount, swapReturn);
    }

    /**
     * @dev Unwinds the leveraged position through flash loan
     *
     * @param withdrawAmount The amount of collateral to be withdrawn.
     * @param params The leverage function params.
     *
     * @dev When swapping usdc for baseToken on the open market, it is possible (probable even) that the asset price will
     *      be different than xLending's internal asset price. When the open market places a lower value on the baseToken
     *      asset than xLending, the NAV of the contract will go down. The maxNavLoss parameter is the maximum tolerance
     *      of NAV loss. Conversely, if the open market places a higher value on the baseToken asset than xLending, the
     *      NAV of the contract will go up.
     */
    function delever(uint256 withdrawAmount, LeverageFunctionParams calldata params)
        public
        onlyOwnerOrManager
        checkNavLoss(params.checkNav, params.maxNavLoss)
    {
        require(withdrawAmount <= market.collateral(address(this)), "Not enough collateral");

        // Get the amount of usd to borrow to cover withdrawAmount
        uint256 assetUsdPrice = priceFeed.getPrice(); // 12 decimals
        uint256 usdcAmount = withdrawAmount * assetUsdPrice; // baseToken decimals + 12 decimals

        // usdcAmountAdjusted is usdc decimals (6)
        uint256 usdcAmountAdjusted = baseToken.decimals() < usdc.decimals()
            ? (usdcAmount * baseTokenToUSDCFactor) / priceFeedDivisor
            : usdcAmount / priceFeedDivisor / baseTokenToUSDCFactor;

        // subtract the flash loan fee, xlend will add it
        uint256 amountFee = (usdcAmountAdjusted * (liquidityPool.getFlashLoanFeeFactor())) / (lendingDivisor);
        usdcAmountAdjusted -= amountFee;

        // encode amount to withdraw
        bytes memory paramsLoan = abi.encode(
            withdrawAmount, // 32 bytes
            params.multiHop, // 1 bytes
            params.tradePath // dynamic bytes
        );

        // Take a flash loan based on debt owed
        // Note function executeOperation is the callback
        liquidityPool.flashLoan(address(this), usdcAmountAdjusted, paramsLoan);
    }

    /**
     * @dev Flash loan callback function.
     * Pay market debt with flash loan funds
     * Withdraw collateral (amount contained in _params)
     * Swap withdrawn collateral for USDC
     * Pay back flash loan
     *
     * @param _amount The amount borrowed from flash loan
     * @param _fee The flash loan fee
     * @param _params The flash loan params, will contain amount of ETH to withdraw
     */
    function executeOperation(
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external override {
        require(msg.sender == address(liquidityPool), "Only callable by flash loan provider");

        // Decode params
        (uint256 withdrawAmount, bool multiHop, bytes memory tradePath) = abi.decode(_params, (uint256, bool, bytes));

        // Pay back debt
        liquidityPool.whitelistRepay(_amount);

        // Withdraw
        _withdraw(withdrawAmount);

        // Swap collateral for flash loan debt
        // Max input to trade is buffer balance so that we don't trade away fees
        uint256 swapReturn;
        if (multiHop) {
            swapReturn = _swapInputForExactOutputMultiHop(tradePath, getBufferBalance(), _amount + _fee);
        } else {
            swapReturn = _swapInputForExactOutput(
                address(baseToken),
                address(usdc),
                getBufferBalance(),
                _amount + _fee
            );
        }

        emit Delevered(withdrawAmount, swapReturn);
    }

    /**
     * @dev Withdraw collateral from xtoken lending
     *
     * @param withdrawAmount The amount to withdraw
     */
    function withdraw(uint256 withdrawAmount) external onlyOwnerOrManager {
        _withdraw(withdrawAmount);

        emit CollateralWithdraw(withdrawAmount);
    }

    /**
     * @dev Deposit collateral to xtoken lending
     *
     * @param depositAmount The amount to deposit
     */
    function deposit(uint256 depositAmount) external onlyOwnerOrManager {
        require(depositAmount <= getBufferBalance(), "Deposit amount exceeds buffer");

        _deposit(depositAmount);

        emit CollateralDeposit(depositAmount);
    }

    /**
     * @dev Set the supply cap
     *
     * @param _supplyCap The new supply cap
     */
    function setTotalSupplyCap(uint256 _supplyCap) external onlyOwnerOrManager {
        supplyData.totalCap = _supplyCap;
    }

    /**
     * @dev Set the user balance cap
     *
     * @param _userBalanceCap The new user balance cap
     */
    function setUserBalanceCap(uint256 _userBalanceCap) external onlyOwnerOrManager {
        supplyData.userCap = _userBalanceCap;
    }

    /**
     * @dev Set the liquidity buffer amount
     *
     * @param _liquidityBufferAmount The liquidity buffer amount
     */
    function setLiquidityBufferAmount(uint256 _liquidityBufferAmount) external onlyOwnerOrManager {
        liquidityBuffer.amount = _liquidityBufferAmount;
    }

    /**
     * @dev Set the liquidity buffer active level
     *
     * @param _active True to make active, false otherwise
     */
    function setLiquidityBufferActive(bool _active) external onlyOwnerOrManager {
        liquidityBuffer.active = _active;
    }

    /**
     * @dev Claim and withdraw fees
     * @notice Only callable by the revenue controller
     */
    function claimFees() external {
        require(xTokenManager.isRevenueController(msg.sender), "Callable only by Revenue Controller");
        // => transfer tokens
        uint256 totalFees = claimableFees;
        claimableFees = 0;
        baseToken.transfer(msg.sender, totalFees);
    }

    /**
     * @dev Exempts an address from blocklock
     * @param lockAddress The address to exempt
     */
    function exemptFromBlockLock(address lockAddress) external onlyOwnerOrManager {
        _exemptFromBlockLock(lockAddress);
    }

    /**
     * @dev Removes exemption for an address from blocklock
     * @param lockAddress The address to remove exemption
     */
    function removeBlockLockExemption(address lockAddress) external onlyOwnerOrManager {
        _removeBlockLockExemption(lockAddress);
    }

    /**
     * @dev Admin function for pausing contract operations. Pausing prevents mints.
     */
    function pauseContract() external onlyOwnerOrManager {
        _pause();
    }

    /**
     * @dev Admin function for unpausing contract operations.
     */
    function unpauseContract() external onlyOwnerOrManager {
        _unpause();
    }

    /**
     * @dev Admin function to update the fee divisors
     *
     * @param newDivisors The new fee divisors
     */
    function setFeeDivisor(FeeDivisors calldata newDivisors) external onlyOwnerOrManager {
        feeDivisors.burnFee = newDivisors.burnFee;
        feeDivisors.mintFee = newDivisors.mintFee;
    }

    //--------------------------------------------------------------------------
    // Private functions
    //--------------------------------------------------------------------------

    function _mintInternal(
        address recipient,
        uint256 baseTokenAmount,
        uint256 totalSupply
    ) private {
        uint256 amountToMint = calculateMintAmount(baseTokenAmount, totalSupply);
        require(totalSupply + amountToMint <= supplyData.totalCap);
        require(balanceOf(recipient) + amountToMint < supplyData.userCap);

        _mint(recipient, amountToMint);
    }

    function _withdraw(uint256 _withdrawAmount) private {
        market.withdraw(_withdrawAmount);
    }

    function _deposit(uint256 _depositAmount) private {
        market.collateralize(_depositAmount);
    }

    function _incrementFees(uint256 _amount) private {
        claimableFees += _amount;
    }

    function _swapExactInputForOutput(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 minReturn
    ) internal returns (uint256) {
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: address(inputToken),
            tokenOut: address(outputToken),
            fee: uniswapFee,
            recipient: address(this),
            deadline: MAX_UINT,
            amountIn: inputAmount,
            amountOutMinimum: minReturn,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = uniswapV3Router.exactInputSingle(params);

        return amountOut;
    }

    function _swapExactInputForOutputMultiHop(
        bytes calldata tradePath,
        uint256 inputAmount,
        uint256 minReturn
    ) internal returns (uint256) {
        IUniswapV3Router.ExactInputParams memory params = IUniswapV3Router.ExactInputParams({
            path: tradePath,
            recipient: address(this),
            deadline: MAX_UINT,
            amountIn: inputAmount,
            amountOutMinimum: minReturn
        });

        uint256 amountOut = uniswapV3Router.exactInput(params);

        return amountOut;
    }

    function _swapInputForExactOutput(
        address inputToken,
        address outputToken,
        uint256 maxInput,
        uint256 exactReturn
    ) internal returns (uint256) {
        IUniswapV3Router.ExactOutputSingleParams memory params = IUniswapV3Router.ExactOutputSingleParams({
            tokenIn: address(inputToken),
            tokenOut: address(outputToken),
            fee: uniswapFee,
            recipient: address(this),
            deadline: MAX_UINT,
            amountOut: exactReturn,
            amountInMaximum: maxInput,
            sqrtPriceLimitX96: 0
        });

        uint256 amountIn = uniswapV3Router.exactOutputSingle(params);

        return amountIn;
    }

    function _swapInputForExactOutputMultiHop(
        bytes memory tradePath,
        uint256 maxInput,
        uint256 exactReturn
    ) internal returns (uint256) {
        IUniswapV3Router.ExactOutputParams memory params = IUniswapV3Router.ExactOutputParams({
            path: tradePath,
            recipient: address(this),
            deadline: MAX_UINT,
            amountOut: exactReturn,
            amountInMaximum: maxInput
        });

        uint256 amountIn = uniswapV3Router.exactOutput(params);

        return amountIn;
    }
}

