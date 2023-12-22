//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

// Libraries
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IRouter} from "./IRouter.sol";
import {IVault} from "./IVault.sol";
import {IPositionRouter} from "./IPositionRouter.sol";
import {IDopexPositionManagerFactory} from "./IDopexPositionManagerFactory.sol";

// Interfaces
import {IDopexPositionManager, IncreaseOrderParams, DecreaseOrderParams} from "./IDopexPositionManager.sol";

contract DopexPositionManager is IDopexPositionManager {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 100000;
    uint256 public minSlippageBps;
    // Min execution fee for orders
    uint256 public minFee;
    // Minimum slippage applied to order price
    uint256 public slippage;
    // Address of the user of this position manager
    address public user;
    // Callback address when position is executed
    address public callback;
    // Address of the strategy contract
    address public strategyController;
    // Address of the position manager factory
    address public factory;
    // initialize check
    bool public isEnabled;
    // Is position released and can be increased/decreased by user
    bool public released;

    // GMX Router
    IRouter public gmxRouter;
    //  GMX Vault
    IVault public gmxVault;
    // GMX Position Router
    IPositionRouter public gmxPositionRouter;

    mapping(address => mapping(address => uint256)) public pendingTokens;

    // Referral code (GMX related)
    bytes32 public referralCode;

    error DopexPositionManagerError(uint256);

    /**
     * @notice Set contract vars and create long position
     * @param _gmxVault           Address of the GMX Vault contract
     * @param _gmxRouter          Address of the GMX Router contract
     * @param _gmxPositionRouter  Address of the GMX Position Router contract
     * @param _user               Address of the user of the position manager
     */
    function enableAndCreateIncreaseOrder(
        IncreaseOrderParams calldata params,
        address _gmxVault,
        address _gmxRouter,
        address _gmxPositionRouter,
        address _user
    ) external payable {
        if (isEnabled) {
            _validate(msg.sender == strategyController, 1);
        }
        strategyController = msg.sender;
        user = _user;

        gmxRouter = IRouter(_gmxRouter);
        gmxVault = IVault(_gmxVault);
        gmxPositionRouter = IPositionRouter(_gmxPositionRouter);
        minFee = gmxPositionRouter.minExecutionFee();
        slippage = IDopexPositionManagerFactory(factory).minSlipageBps();
        minSlippageBps = slippage;

        gmxRouter.approvePlugin(_gmxPositionRouter);
        // Create long position
        increaseOrder(params);

        isEnabled = true;
        released = false;
    }

    /**
     * @notice Create an increase order. note that GMX position router is the approved plugin here
     *         Orders created through this function will not be executed by the strategy handler.
     *         instead GMX's position keeper will execute it.
     * @param params Parameters for creating an order for the futures position in gmx
     */
    function increaseOrder(IncreaseOrderParams memory params) public payable {
        if (msg.sender == user) {
            _validate(released, 2);
            IERC20(params.path[0]).safeTransferFrom(
                msg.sender,
                address(this),
                params.collateralDelta
            );
        } else {
            _validate(msg.sender == strategyController, 1);
        }

        _validate(msg.value >= gmxPositionRouter.minExecutionFee(), 5);

        IERC20(params.path[0]).safeIncreaseAllowance(
            address(gmxRouter),
            params.collateralDelta
        );

        uint256 priceWithSlippage = msg.sender == strategyController
            ? _getPriceWithSlippage(params.indexToken, true)
            : params.acceptablePrice;

        gmxPositionRouter.createIncreasePosition{value: msg.value}(
            params.path,
            params.indexToken,
            params.collateralDelta,
            0,
            params.positionSizeDelta,
            params.isLong,
            priceWithSlippage,
            msg.value,
            referralCode,
            _getCallback()
        );

        emit IncreaseOrderCreated(
            params.path,
            params.indexToken,
            params.collateralDelta,
            params.positionSizeDelta,
            priceWithSlippage
        );
    }

    /**
     * @notice Create an decrease order. note that GMX position router is the approved plugin here
     *         Orders created through this function will not be executed by the strategy handler
     *         instead GMX's position keeper will execute it.
     * @param params Parameters for creating an order for the futures position in gmx
     */
    function decreaseOrder(DecreaseOrderParams memory params) external payable {
        if (msg.sender == user) {
            // Position muste be released
            _validate(released, 2);
        } else {
            // Ensure only strategy controller or user can call
            _validate(msg.sender == strategyController, 1);
        }
        _validate(msg.value >= gmxPositionRouter.minExecutionFee(), 5);

        uint256 priceWithSlippage = msg.sender == strategyController
            ? _getPriceWithSlippage(params.orderParams.indexToken, false)
            : params.orderParams.acceptablePrice;

        gmxPositionRouter.createDecreasePosition{value: msg.value}(
            params.orderParams.path,
            params.orderParams.indexToken,
            params.orderParams.collateralDelta,
            params.orderParams.positionSizeDelta,
            params.orderParams.isLong,
            params.receiver,
            priceWithSlippage,
            0,
            msg.value,
            params.withdrawETH,
            _getCallback()
        );

        pendingTokens[msg.sender][
            params.orderParams.path[params.orderParams.path.length - 1]
        ] = IERC20(params.orderParams.path[params.orderParams.path.length - 1])
            .balanceOf(address(this));

        emit DecreaseOrderCreated(
            params.orderParams.path,
            params.orderParams.indexToken,
            params.orderParams.collateralDelta,
            params.orderParams.positionSizeDelta,
            priceWithSlippage
        );
    }

    function withdrawPendingToken(
        address _pendingToken
    ) external returns (uint256 _pendingAmount) {
        _validate(msg.sender == strategyController, 1);
        uint256 pendingAmount = IERC20(_pendingToken).balanceOf(address(this));
        _pendingAmount = pendingTokens[msg.sender][_pendingToken];
        if (_pendingAmount > 0) {
            pendingAmount = pendingAmount - _pendingAmount;
            IERC20(_pendingToken).safeTransfer(msg.sender, pendingAmount);
        }
    }

    /**
     * @notice Withdraw tokens from this contract.
     *         Callable my strategy contract if not released
     *         otherwise user can call.
     * @param _tokens   Addresses of the tokens to withdraw.
     * @param _receiver Address of the tokens receiver.
     * @return _amounts Amount of tokens transferred.
     */
    function withdrawTokens(
        address[] calldata _tokens,
        address _receiver
    ) external returns (uint256[] memory _amounts) {
        _validate(msg.sender == strategyController, 1);
        _amounts = new uint256[](_tokens.length);
        for (uint256 i; i < _tokens.length; ) {
            _amounts[i] = IERC20(_tokens[i]).balanceOf(address(this));
            if (_amounts[i] > 0) {
                IERC20(_tokens[i]).safeTransfer(_receiver, _amounts[i]);
            }
            unchecked {
                ++i;
            }
        }
        emit TokensWithdrawn(_tokens, _amounts);
    }

    function strategyControllerTransfer(
        address _token,
        address _to,
        uint256 amount
    ) external {
        _validate(msg.sender == strategyController, 1);
        IERC20(_token).safeTransfer(_to, amount);
    }

    /// @notice Release contract from strategy
    function release() external {
        _validate(msg.sender == strategyController, 1);
        released = true;
        emit Released();
    }

    function lock() external {
        _validate(msg.sender == strategyController, 1);
        released = false;
        minFee = IPositionRouter(gmxPositionRouter).minExecutionFee();
        uint256 minSlippage = IDopexPositionManagerFactory(factory)
            .minSlipageBps();
        minSlippageBps = minSlippage;
        slippage = minSlippage;
        callback = IDopexPositionManagerFactory(factory).callback();
        emit Locked();
    }

    /// @notice Set min execution fee for increase/decrease orders after released
    /// @param newFee New execution fee to set
    function setMinFee(uint256 newFee) external {
        _isReleased();
        minFee = newFee;
    }

    /// @notice Set referral code
    /// @param _newReferralCode New referral code
    function setReferralCode(bytes32 _newReferralCode) external {
        if (msg.sender != factory) {
            _isReleased();
        }
        referralCode = _newReferralCode;
        emit ReferralCodeSet(_newReferralCode);
    }

    /// @notice Set slippage for increase/decrease orders
    /// @param _slippageBps Slippage BPS in PRECISION
    function setSlippage(uint256 _slippageBps) external {
        _isReleased();
        // can't be more than PRECISION
        _validate(_slippageBps <= PRECISION, 6);
        // Can't be less than a min amount
        _validate(_slippageBps >= minSlippageBps, 6);
        slippage = _slippageBps;
        emit SlippageSet(_slippageBps);
    }

    /// @dev Helper function to check if position has been released and is called by user
    function _isReleased() private view {
        _validate(msg.sender == user, 1);
        _validate(released, 2);
    }

    function _getPriceWithSlippage(
        address _token,
        bool _max
    ) private view returns (uint256 price) {
        price = _max
            ? gmxVault.getMaxPrice(_token)
            : gmxVault.getMinPrice(_token);
        uint256 precision = PRECISION;
        price =
            (price * (_max ? (precision + slippage) : (precision - slippage))) /
            precision;
    }

    function _getCallback() private view returns (address _callback) {
        if (msg.sender == strategyController) {
            _callback = callback;
        }
    }

    /// @dev validator function to revert contracts custom error and error code
    function _validate(bool requiredCondition, uint256 errorCode) private pure {
        if (!requiredCondition) revert DopexPositionManagerError(errorCode);
    }

    function setStrategyController(address _strategy) external {
        _validate(msg.sender == factory, 1);
        strategyController = _strategy;
        emit StrategyControllerSet(_strategy);
    }

    function setCallback(address _callback) external {
        if (msg.sender != factory) {
            _validate(msg.sender == strategyController, 1);
        }
        callback = _callback;
        emit CallbackSet(_callback);
    }

    function setFactory(address _factory) external {
        if (factory == address(0)) {
            factory = msg.sender;
        } else {
            _validate(msg.sender == factory, 1);
        }
        factory = _factory;
        emit FactorySet(_factory);
    }
}

/**
1 => Forbidden.
2 => Position hasn't been released by the strategy controller.
3 => Cannot provide 0 as amount
4 => Cannot re-initialize
5 => Insufficient exeuction fees
6 => Invalid Slippage
7 => Already initialized
 */

