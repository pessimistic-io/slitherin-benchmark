// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Metadata.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./PRBMathUD60x18.sol";

import {IStrategist} from "./IStrategist.sol";
import {IAssetManager} from "./IAssetManager.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title Strategist contract is a uses Asset Manager to create leverage positions
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract Strategist is
    IStrategist,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using PRBMathUD60x18 for uint256;

    IERC20Metadata public collateralToken;
    IERC20Metadata public usdc;
    IAssetManager public assetManager;
    IBalanceSheet public balanceSheet;
    uint256 public allowableSlippage;
    uint24 public poolFee;
    uint256 public strategyFee;
    ISwapRouter public swapRouter;

    event WithdrewETH(
        address indexed _operator,
        address indexed _to,
        uint256 _withdrewAmount
    );
    event WithdrewERC20(
        address indexed _operator,
        address indexed _to,
        uint256 _withdrewAmount,
        address _interactedWithTokenContract
    );
    event SwappedExactIn(
        address indexed _user,
        uint256 _amountIn,
        uint256 _amountOut
    );
    event SwappedExactOut(
        address indexed _user,
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _amountInMaximum
    );
    event ClosedLeverage(
        address indexed user,
        uint256 _outstandingLoan,
        uint256 _collateralAmount,
        uint256 _amountUsed
    );
    event TransferedToUser(address indexed _user, uint256 _amount);
    event StrategyFeeSet(
        address _operator,
        uint256 _previousFee,
        uint256 _currentFee
    );
    event AllowableSlippageSet(
        address _operator,
        uint256 _previousSlippage,
        uint256 _currentSlippage
    );
    event PoolFeeSet(
        address _operator,
        uint24 _previousFee,
        uint24 _currentFee
    );
    event SwapRouterSet(
        address _operator,
        address _previousSwapRouter,
        address _currentSwapRouter
    );

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    function initialize(
        address _collateralTokenAddress,
        address _usdcAddress,
        address _assetManagerAddress,
        address _balanceSheetAddress,
        uint256 _allowableSlippage,
        uint24 _poolFee,
        uint256 _strategyFee,
        address _swapRouterAddress
    ) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();

        collateralToken = IERC20Metadata(_collateralTokenAddress);
        usdc = IERC20Metadata(_usdcAddress);
        assetManager = IAssetManager(_assetManagerAddress);
        balanceSheet = IBalanceSheet(_balanceSheetAddress);
        allowableSlippage = _allowableSlippage;
        poolFee = _poolFee;
        strategyFee = _strategyFee;
        swapRouter = ISwapRouter(_swapRouterAddress);

        _pause();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function leverage2x(
        uint256 _depositAmount
    ) public nonReentrant whenNotPaused {
        address user = msg.sender;
        // transfer collateral from the user
        collateralToken.transferFrom(user, address(this), _depositAmount);

        uint256 fee = _depositAmount.mul(strategyFee);
        collateralToken.transfer(assetManager.treasuryAddress(), fee); // transfer fee to treasury

        uint256 depositAmount = _depositAmount - fee;

        uint256 borrowAmount = depositAmount
            .mul(balanceSheet.getMaxBorrow())
            .mul(balanceSheet.getAssetCurrentPrice()); // 70% of deposit * current price

        _borrowForUser(depositAmount, borrowAmount, user);

        // swap USDC for collateral token
        uint256 amountIn = _amountInUSDC(borrowAmount);
        depositAmount = _swapExactIn(
            amountIn,
            address(usdc),
            address(collateralToken)
        );
        emit SwappedExactIn(user, amountIn, depositAmount);

        // use swapped collateral to borrow more
        borrowAmount = depositAmount.mul(43e16).mul(
            balanceSheet.getAssetCurrentPrice()
        ); // 43% of swapped assets * current price

        _borrowForUser(depositAmount, borrowAmount, user);

        amountIn = _amountInUSDC(borrowAmount);
        depositAmount = _swapExactIn(
            amountIn,
            address(usdc),
            address(collateralToken)
        );
        emit SwappedExactIn(user, amountIn, depositAmount);

        _borrowForUser(depositAmount, 0, user);
    }

    function closeLeverage(
        uint256 _collateralAmount
    ) public nonReentrant whenNotPaused {
        address user = msg.sender;
        uint256 outstandingLoan = balanceSheet.getOutstandingLoan(user);
        uint256 fee = outstandingLoan.mul(strategyFee);

        require(
            balanceSheet.getCollateralAmount(user) >= _collateralAmount,
            "Strategist: Non existing collateral"
        );

        require(
            balanceSheet.getCollateralValue(user) >= (outstandingLoan + fee),
            "Strategist: Cannot close leverage"
        );

        // transfer collateral from asset manager
        assetManager.moveCollateral(user, _collateralAmount);

        // send fee to treasury
        uint256 feeInCollateral = _collateralAmount.mul(strategyFee);
        collateralToken.transfer(
            assetManager.treasuryAddress(),
            feeInCollateral
        ); // transfer fee to treasury

        uint256 collateralAmount = _collateralAmount - feeInCollateral;
        uint256 collateralValueAfterFees = collateralAmount.mul(
            balanceSheet.getAssetCurrentPrice()
        );

        if (collateralValueAfterFees >= outstandingLoan) {
            // amountInMaxium needs to be adjusted for slippage
            uint256 collateralAmountNeeded = outstandingLoan.div(
                balanceSheet.getAssetCurrentPrice()
            ) + collateralAmount.mul(allowableSlippage);

            require(
                collateralAmountNeeded <= collateralAmount,
                "Strategist: Not enough collateral"
            );
            uint256 amountUsed = _swapExactOut(
                _amountInUSDC(outstandingLoan),
                collateralAmountNeeded
            );

            emit SwappedExactOut(
                user,
                amountUsed,
                _amountInUSDC(outstandingLoan),
                collateralAmountNeeded
            );

            // make payment on users behalf
            usdc.approve(address(assetManager), _amountInUSDC(outstandingLoan));
            assetManager.makePayment(outstandingLoan, user);
            emit ClosedLeverage(
                user,
                outstandingLoan,
                collateralAmountNeeded,
                amountUsed
            );

            // transfer collateral to user
            if (collateralAmount - amountUsed > 0) {
                TransferHelper.safeTransfer(
                    address(collateralToken),
                    user,
                    collateralAmount - amountUsed
                );

                emit TransferedToUser(user, collateralAmount - amountUsed);
            }
        } else {
            uint256 amountOut = _swapExactIn(
                collateralAmount,
                address(collateralToken),
                address(usdc)
            );
            emit SwappedExactIn(user, collateralAmount, amountOut);

            // make payment on users behalf
            usdc.approve(address(assetManager), amountOut);
            assetManager.makePayment(_paddedAmount(amountOut), user);
            emit ClosedLeverage(
                user,
                _paddedAmount(amountOut),
                collateralAmount,
                collateralAmount
            );
        }

        assetManager.removeCollateralForUser(user, _collateralAmount);
    }

    /**
     * @notice pause borrowing
     */
    function pauseStrategies() public onlyAdmin {
        _pause();
    }

    /**
     * @notice unpause borrowing
     */
    function unpauseStrategies() public onlyAdmin {
        _unpause();
    }

    /**
     * @notice withdraw eth
     * @param _to - address
     * @param _amount - amount
     */
    function withdrawEth(
        address _to,
        uint256 _amount
    ) public nonReentrant onlyAdmin {
        (bool sent, ) = _to.call{value: _amount}("");
        require(sent, "Failed to send Ether");
        emit WithdrewETH(msg.sender, _to, _amount);
    }

    /**
     * @notice withdraw erc20
     * @param _to - address
     * @param _amount - amount
     * @param _tokenAddress - token address
     */
    function withdrawERC20(
        address _to,
        uint256 _amount,
        address _tokenAddress
    ) public nonReentrant onlyAdmin {
        IERC20Metadata(_tokenAddress).transfer(_to, _amount);
        emit WithdrewERC20(msg.sender, _to, _amount, _tokenAddress);
    }

    /**
     * @notice set liquidation fee
     * @param _fee - fee
     */
    function setStrategyFee(uint256 _fee) public nonReentrant onlyAdmin {
        emit StrategyFeeSet(msg.sender, strategyFee, _fee);
        strategyFee = _fee;
    }

    /**
     * @notice set slippage percentage
     * @param _allowableSlippage - slippage percentage
     */
    function setAllowableSlippage(
        uint256 _allowableSlippage
    ) public nonReentrant onlyAdmin {
        emit AllowableSlippageSet(
            msg.sender,
            allowableSlippage,
            _allowableSlippage
        );
        allowableSlippage = _allowableSlippage;
    }

    /**
     * @notice set pool fee
     * @param _poolFee - pool fee
     */
    function setPoolFee(uint24 _poolFee) public nonReentrant onlyAdmin {
        emit PoolFeeSet(msg.sender, poolFee, _poolFee);
        poolFee = _poolFee;
    }

    /**
     * @notice set swap router
     * @param _swapRouterAddress - swap router address
     */
    function setSwapRouter(
        address _swapRouterAddress
    ) public nonReentrant onlyAdmin {
        emit SwapRouterSet(msg.sender, address(swapRouter), _swapRouterAddress);
        swapRouter = ISwapRouter(_swapRouterAddress);
    }

    /// @notice swaps a fixed amount of usdc for a maximum possible amount of collateral.
    /// @dev The calling address must approve this contract to spend its usdc for this function to succeed.
    /// @param amountIn The exact amount of usdc to spend in the swap.
    /// @return amountOut The amount of collateral actually received from the swap.
    function _swapExactIn(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256) {
        // https://github.com/Uniswap/docs/blob/main/examples/smart-contracts/SwapExamples.sol#L36
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        uint256 currentAssetPrice = balanceSheet.getAssetCurrentPrice();
        uint256 amountOutMinimum = (amountIn - amountIn.mul(allowableSlippage))
            .mul(currentAssetPrice);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        uint256 amountOut = swapRouter.exactInputSingle(params);

        return amountOut;
    }

    /// @notice swaps a minimum possible amount of collateral for a fixed amount of USDC.
    /// @dev The calling address must approve this contract to spend its collateral token for this function to succeed. As the amount of input collateral token is variable,
    /// the calling address will need to approve for a slightly higher amount, anticipating some variance.
    /// @param amountOut The exact amount of USDC to receive from the swap.
    /// @param amountInMaximum The amount of collateral token we are willing to spend to receive the specified amount of USDC.
    /// @return amountIn The amount of colleral token actually spent in the swap.
    function _swapExactOut(
        uint256 amountOut,
        uint256 amountInMaximum
    ) internal returns (uint256) {
        // Approve the router to spend the specifed `amountInMaximum` of collateral token.
        // In production, you should choose the maximum amount to spend based on oracles or other data sources to acheive a better swap.
        TransferHelper.safeApprove(
            address(collateralToken),
            address(swapRouter),
            amountInMaximum
        );

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: address(collateralToken),
                tokenOut: address(usdc),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        uint256 amountIn = swapRouter.exactOutputSingle(params);

        return amountIn;
    }

    /**
     * @notice helper to convert wei into USDC
     * @param _amount - 18 decimal amount
     * @return uint256 - USDC decimal compliant amount
     */
    function _amountInUSDC(uint256 _amount) internal view returns (uint256) {
        // because USDC is 6 decimals, we need to fix the decimals
        // https://docs.openzeppelin.com/contracts/4.x/erc20#a-note-on-decimals
        uint8 decimals = usdc.decimals();
        return (_amount / 10 ** (18 - decimals));
    }

    /**
     * @notice Returns the padded amount - 18 decimals
     * @param _amount The amount of ERC20 tokens
     * @return uint256 The padded amount of ERC20 tokens
     */
    function _paddedAmount(uint256 _amount) public view returns (uint256) {
        uint8 decimals = usdc.decimals();
        return (_amount * 10 ** (18 - decimals));
    }

    /**
     * @notice Internal function to borrow for user
     * @param _depositAmount - amount of collateral to deposit
     * @param _borrowAmount - amount of USDC to borrow
     * @param _user - user address
     */
    function _borrowForUser(
        uint256 _depositAmount,
        uint256 _borrowAmount,
        address _user
    ) internal {
        // borrow USDC from asset manager
        collateralToken.approve(address(assetManager), _depositAmount);
        assetManager.borrowForUser(_depositAmount, _borrowAmount, _user);
    }

    function _calculatedBorrowAmount(
        uint256 _depositAmount
    ) internal view returns (uint256) {
        return
            _depositAmount.mul((balanceSheet.getMaxBorrow() - 2e16)).mul(
                balanceSheet.getAssetCurrentPrice()
            ); // 70% - 2% ( for acrued fees ) of deposit * current price
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "Strategist: only DefragSystemAdmin"
        );
        _;
    }
}

