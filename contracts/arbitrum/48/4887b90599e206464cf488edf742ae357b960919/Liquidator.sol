// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAssetManager} from "./IAssetManager.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";
import {ILiquidator} from "./ILiquidator.sol";
import "./AccessControlUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC20Metadata.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./PRBMathUD60x18.sol";

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

/// @title Liquidator: checks for accounts to be liquidated from the BalanceSheet
///                    and executes the liquidation on AssetManager
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract Liquidator is
    ILiquidator,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using PRBMathUD60x18 for uint256;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    IAssetManager public assetManager;
    IBalanceSheet public balanceSheet;
    address public collateralTokenAddress;
    address public usdcAddress;
    uint256 public liquidationFee;
    uint256 public allowableSlippage;
    uint24 public poolFee;
    address public wethAddress;
    ISwapRouter public swapRouter;

    event AddedToLiquidationCandidates(address _account);
    event AddedToReadyForLiquidationCandidates(address _account);
    event RemovedFromLiquidationCandidates(address _account);
    event RemovedFromReadyForLiquidationCandidates(address _account);
    event CandidateLiquidated(
        address _account,
        uint256 _outstandingLoan,
        uint256 _transferedAmount,
        uint256 _liquidationFee,
        uint256 _liquidationAmount
    );
    event WithdrewERC20(
        address _operator,
        address _to,
        uint256 _amount,
        address _tokenAddress
    );
    event LiquidationFeeSet(
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
    event SwappedExactOut(
        uint256 _amountIn,
        uint256 _amountOut,
        uint256 _amountInMaximum
    );
    event SwapRouterSet(
        address _operator,
        address _previousSwapRouter,
        address _currentSwapRouter
    );
    event SwappedExactIn(uint256 _amountIn, uint256 _amountOut);

    EnumerableSetUpgradeable.AddressSet private liquidationCandidates; // 1st time offenders - given a chance to improve health score
    EnumerableSetUpgradeable.AddressSet private readyForLiquidationCandidates; // 2nd time offenders - will be liquidated

    function initialize(
        address _assetManagerAddress,
        address _balanceSheetAddress,
        address _collateralTokenAddress,
        address _usdcAddress,
        uint256 _liquidationFee,
        uint256 _allowableSlippage,
        uint24 _poolFee,
        address _swapRouterAddress,
        address _wethAddress
    ) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();

        assetManager = IAssetManager(_assetManagerAddress);
        balanceSheet = IBalanceSheet(_balanceSheetAddress);
        collateralTokenAddress = _collateralTokenAddress;
        usdcAddress = _usdcAddress;
        wethAddress = _wethAddress;
        liquidationFee = _liquidationFee;
        allowableSlippage = _allowableSlippage;
        poolFee = _poolFee;
        swapRouter = ISwapRouter(_swapRouterAddress);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice calls BalanceSheet to get a list of accounts to be liquidated
     *         and adds them to the liquidationCandidates set
     *         or readyForLiquidationCandidates set if they are already in the liquidationCandidates set
     * @dev only callable by the admin
     */
    function setLiquidationCandidates() public nonReentrant onlyAdmin {
        address[] memory liquidatables = balanceSheet.getLiquidatables();

        // no liquidatable accounts
        // reset the existing liquidation candidates
        // we can't just reset the EnumerableSet
        // because it will corrupt the storage https://docs.openzeppelin.com/contracts/4.x/api/utils#EnumerableSet
        // we have to iterate through the existing set and remove each element
        if (liquidatables.length == 0) {
            address[] memory existingCandidates = EnumerableSetUpgradeable
                .values(liquidationCandidates);
            for (uint256 i = 0; i < existingCandidates.length; i++) {
                liquidationCandidates.remove(existingCandidates[i]);

                emit RemovedFromLiquidationCandidates(existingCandidates[i]);
            }
        } else {
            // there are liquidatable accounts
            for (uint256 i = 0; i < liquidatables.length; i++) {
                // if the account is already in the liquidationCandidates set
                // then we need to remove it from the set
                // and add it to the readyForLiquidationCandidates set
                if (
                    EnumerableSetUpgradeable.contains(
                        liquidationCandidates,
                        liquidatables[i]
                    )
                ) {
                    EnumerableSetUpgradeable.remove(
                        liquidationCandidates,
                        liquidatables[i]
                    );

                    emit RemovedFromLiquidationCandidates(liquidatables[i]);

                    EnumerableSetUpgradeable.add(
                        readyForLiquidationCandidates,
                        liquidatables[i]
                    );

                    emit AddedToReadyForLiquidationCandidates(liquidatables[i]);
                } else {
                    // if the account is not in the liquidationCandidates set
                    // then we need to add it to the set
                    liquidationCandidates.add(liquidatables[i]);

                    emit AddedToLiquidationCandidates(liquidatables[i]);
                }
            }
        }
    }

    /**
     * @notice iterates through the readyForLiquidationCandidates set and calls on Asset Manager to liquidate
     * @dev only callable by the admin
     */
    function executeLiquidations() public nonReentrant onlyAdmin {
        address[] memory candidates = EnumerableSetUpgradeable.values(
            readyForLiquidationCandidates
        );
        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 outstandingLoan = balanceSheet.getOutstandingLoan(
                candidates[i]
            );

            // transfer the collateral to the liquidator
            // mark the loan as liquidated on Balance Sheet
            uint256 transferedAmount = assetManager.liquidate(candidates[i]);
            uint256 liquidationAmount = outstandingLoan +
                (outstandingLoan.mul(liquidationFee));
            uint256 currentAssetPrice = balanceSheet.getAssetCurrentPrice();
            uint256 collateralAmountToSwap = liquidationAmount.div(
                currentAssetPrice
            );
            uint256 amountInMaximum = collateralAmountToSwap +
                (collateralAmountToSwap.mul(allowableSlippage));

            if (currentAssetPrice.mul(transferedAmount) > liquidationAmount) {
                // ARB is 18 decimals
                // USDC is 6 decimals
                uint256 amountUsed = _swapExactOut(
                    _amountInUSDC(liquidationAmount),
                    amountInMaximum
                );

                // if there is any collateral left after covering the loan, send the rest to the user
                if (transferedAmount - amountUsed > 0) {
                    TransferHelper.safeTransfer(
                        collateralTokenAddress,
                        candidates[i],
                        transferedAmount - amountUsed
                    );
                }
            } else {
                // if the collateral value is lower than liquidation amount
                // you have to call Uniswap amount in exact
                // with all transferedAmount
                _swapExactIn(transferedAmount);
            }

            IERC20Metadata(usdcAddress).approve(
                address(assetManager),
                _amountInUSDC(outstandingLoan)
            );

            assetManager.makePayment(outstandingLoan, candidates[i]);

            emit CandidateLiquidated(
                candidates[i],
                outstandingLoan,
                transferedAmount,
                liquidationFee,
                liquidationAmount
            );

            // remove the account from the readyForLiquidationCandidates set
            EnumerableSetUpgradeable.remove(
                readyForLiquidationCandidates,
                candidates[i]
            );
            emit RemovedFromReadyForLiquidationCandidates(candidates[i]);
        }
    }

    /**
     * @notice returns the list of liquidation candidates
     * @return the list of liquidatable accounts
     */
    function getLiquidatableCandidates()
        public
        view
        returns (address[] memory)
    {
        return EnumerableSetUpgradeable.values(liquidationCandidates);
    }

    /**
     * @notice returns the list of ready for liquidation candidates
     * @return the list of ready for liquidation candidates
     */
    function getReadyForLiquidationCandidates()
        public
        view
        returns (address[] memory)
    {
        return EnumerableSetUpgradeable.values(readyForLiquidationCandidates);
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
    function setLiquidationFee(uint256 _fee) public nonReentrant onlyAdmin {
        emit LiquidationFeeSet(msg.sender, liquidationFee, _fee);
        liquidationFee = _fee;
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

    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "Liquidator: only DefragSystemAdmin"
        );
        _;
    }

    /**
     * @notice helper to convert wei into USDC
     * @param _amount - 18 decimal amount
     * @return uint256 - USDC decimal compliant amount
     */
    function _amountInUSDC(uint256 _amount) internal view returns (uint256) {
        // because USDC is 6 decimals, we need to fix the decimals
        // https://docs.openzeppelin.com/contracts/4.x/erc20#a-note-on-decimals
        uint8 decimals = IERC20Metadata(usdcAddress).decimals();
        return (_amount / 10 ** (18 - decimals));
    }

    /**
     * @notice Returns the padded amount - 18 decimals
     * @param _amount The amount of ERC20 tokens
     * @return uint256 The padded amount of ERC20 tokens
     */
    function _paddedAmount(uint256 _amount) public view returns (uint256) {
        uint8 decimals = IERC20Metadata(usdcAddress).decimals();
        return (_amount * 10 ** (18 - decimals));
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
            collateralTokenAddress,
            address(swapRouter),
            amountInMaximum
        );

        ISwapRouter.ExactOutputParams memory params = ISwapRouter
            .ExactOutputParams({
                path: abi.encodePacked(
                    collateralTokenAddress,
                    poolFee,
                    wethAddress,
                    poolFee,
                    usdcAddress
                ),
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        uint256 amountIn = swapRouter.exactOutput(params);

        emit SwappedExactOut(amountIn, amountOut, amountInMaximum);

        return amountIn;
    }

    /// @notice swaps a fixed amount of collateral for a maximum possible amount of USDC.
    /// @dev The calling address must approve this contract to spend its collateral token for this function to succeed.
    /// @param amountIn The exact amount of collateral token to spend in the swap.
    /// @return amountOut The amount of USDC actually received from the swap.
    function _swapExactIn(uint256 amountIn) internal returns (uint256) {
        // https://github.com/Uniswap/docs/blob/main/examples/smart-contracts/SwapExamples.sol#L36
        TransferHelper.safeApprove(
            collateralTokenAddress,
            address(swapRouter),
            amountIn
        );

        ISwapRouter.ExactInputParams memory params = ISwapRouter
            .ExactInputParams({
                path: abi.encodePacked(
                    collateralTokenAddress,
                    poolFee,
                    wethAddress,
                    poolFee,
                    usdcAddress
                ),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0
            });

        uint256 amountOut = swapRouter.exactInput(params);

        emit SwappedExactIn(amountIn, amountOut);

        return amountOut;
    }
}

