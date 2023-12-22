//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

// Libraries/Contracts
import {SafeERC20} from "./SafeERC20.sol";
import {Pausable} from "./Pausable.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {OwnableRoles} from "./OwnableRoles.sol";

// Interfaces
import {IAtlanticPutsPool} from "./IAtlanticPutsPool.sol";
import {IRouter} from "./IRouter.sol";
import {IVault} from "./IVault.sol";
import {IPositionRouter} from "./IPositionRouter.sol";
import {IERC20} from "./IERC20.sol";
import {IDopexPositionManager, IncreaseOrderParams, DecreaseOrderParams} from "./IDopexPositionManager.sol";
import {IInsuredLongsUtils} from "./IInsuredLongsUtils.sol";
import {IInsuredLongsStrategy} from "./IInsuredLongsStrategy.sol";
import {IDopexPositionManagerFactory} from "./IDopexPositionManagerFactory.sol";
import {ICallbackForwarder} from "./ICallbackForwarder.sol";
import {IDopexFeeStrategy} from "./IDopexFeeStrategy.sol";

// Enums
import {OptionsState} from "./AtlanticPutsPoolEnums.sol";

// Structs
import {OptionsPurchase} from "./AtlanticPutsPoolStructs.sol";

contract InsuredLongsStrategy is
    ContractWhitelist,
    Pausable,
    ReentrancyGuard,
    IInsuredLongsStrategy
{
    using SafeERC20 for IERC20;

    uint256 private constant BPS_PRECISION = 100000;
    uint256 private constant STRATEGY_FEE_KEY = 3;
    uint256 public positionsCount = 1;
    uint256 public useDiscountForFees = 1;

    /**
     * @notice Time window in which whitelisted keeper can settle positions.
     */
    uint256 public keeperHandleWindow;

    uint256 public maxLeverage;

    mapping(uint256 => StrategyPosition) public strategyPositions;

    /**
     * @notice Orders after created are saved here and used in
     *         gmxPositionCallback() for reference when a order
     *         is executed.
     */
    mapping(bytes32 => uint256) public pendingOrders;

    /**
     * @notice ID of the strategy position belonging to a user.
     */
    mapping(address => uint256) public userPositionIds;

    /**
     * @notice Keepers are EOA or contracts that will have special
     *         permissions required to carry out insurance related
     *         functions available in this contract.
     *         1. Create a order to add collateral to a position.
     *         2. Create a order to exit a position.
     */
    mapping(address => uint256) public whitelistedKeepers;

    /**
     * @notice Atlantic Put pools that can be used by this strategy contract
     *         for purchasing put options, unlocking, relocking and unwinding of
     *         collateral.
     */
    mapping(bytes32 => address) public whitelistedAtlanticPools;

    mapping(uint256 => address) public pendingStrategyPositionToken;

    address public immutable positionRouter;
    address public immutable router;
    address public immutable vault;
    address public feeDistributor;
    address public gov;
    IDopexFeeStrategy public feeStrategy;

    /**
     *  @notice Index token supported by this strategy contract.
     */
    address public immutable strategyIndexToken;

    IInsuredLongsUtils public utils;
    IDopexPositionManagerFactory public positionManagerFactory;

    constructor(
        address _vault,
        address _positionRouter,
        address _router,
        address _positionManagerFactory,
        address _feeDistributor,
        address _utils,
        address _gov,
        address _indexToken,
        address _feeStrategy
    ) {
        utils = IInsuredLongsUtils(_utils);
        positionManagerFactory = IDopexPositionManagerFactory(
            _positionManagerFactory
        );
        positionRouter = _positionRouter;
        router = _router;
        vault = _vault;
        feeDistributor = _feeDistributor;
        gov = _gov;
        strategyIndexToken = _indexToken;
        feeStrategy = IDopexFeeStrategy(_feeStrategy);
    }

    /**
     * @notice                Reuse strategy for a position manager that has an active
     *                        gmx position.
     * @param _positionId     ID of the position in strategyPositions mapping
     * @param _expiry         Expiry of the insurance
     * @param _keepCollateral Whether to deposit underlying to allow unwinding
     *                        of options.
     */
    function reuseStrategy(
        uint256 _positionId,
        uint256 _expiry,
        bool _keepCollateral
    ) external {
        _isEligibleSender();
        _whenNotPaused();

        StrategyPosition memory position = strategyPositions[_positionId];

        address userPositionManager = userPositionManagers(msg.sender);

        _validate(position.atlanticsPurchaseId == 0, 28);
        _validate(msg.sender == position.user, 27);

        (uint256 positionSize, uint256 collateral) = _getPosition(_positionId);

        _validate(positionSize != 0, 5);

        _validate((positionSize * 1e4) / collateral <= maxLeverage, 30);

        address atlanticPool = _getAtlanticPoolAddress(
            position.indexToken,
            position.collateralToken,
            _expiry
        );

        _validate(atlanticPool != address(0), 8);

        _validteNotWithinExerciseWindow(atlanticPool);

        IDopexPositionManager(userPositionManager).lock();

        position.expiry = _expiry;
        position.keepCollateral = _keepCollateral;

        strategyPositions[_positionId] = position;

        if (position.state != ActionState.EnablePending) {
            // Collect strategy position fee
            _collectStrategyPositionFee(
                positionSize,
                position.collateralToken,
                position.user
            );
        }

        _enableStrategy(_positionId);
    }

    /**
     * @notice                 Create strategy postiion and create long position order
     * @param _collateralToken Address of the collateral token. Also to refer to
     *                         atlantic pool to buy puts from
     * @param _expiry          Timestamp of expiry for selecting a atlantic pool
     * @param _keepCollateral  Deposit underlying to keep collateral if position
     *                         is left increased before expiry
     */
    function useStrategyAndOpenLongPosition(
        IncreaseOrderParams calldata _increaseOrder,
        address _collateralToken,
        uint256 _expiry,
        bool _keepCollateral
    ) external payable nonReentrant {
        _whenNotPaused();
        _isEligibleSender();

        // Only longs are accepted
        _validate(_increaseOrder.isLong, 0);
        _validate(_increaseOrder.indexToken == strategyIndexToken, 1);
        _validate(
            _increaseOrder.path[_increaseOrder.path.length - 1] ==
                strategyIndexToken,
            1
        );

        // Collateral token and path[0] must be the same
        if (_increaseOrder.path.length > 1) {
            _validate(_collateralToken == _increaseOrder.path[0], 16);
        }

        _validate(
            (_increaseOrder.positionSizeDelta * 1e4) /
                IVault(vault).tokenToUsdMin(
                    _increaseOrder.path[0],
                    _increaseOrder.collateralDelta
                ) <=
                maxLeverage,
            30
        );

        address userPositionManager = userPositionManagers(msg.sender);
        uint256 userPositionId = userPositionIds[msg.sender];

        (uint256 size, ) = _getPosition(userPositionId);
        // Should not have open positions
        _validate(size == 0, 29);

        // If position ID and manager is already created for the user, ensure it's a settled one
        _validate(
            strategyPositions[userPositionId].atlanticsPurchaseId == 0,
            9
        );

        address atlanticPool = _getAtlanticPoolAddress(
            _increaseOrder.indexToken,
            _collateralToken,
            _expiry
        );

        _validate(atlanticPool != address(0), 8);

        _validteNotWithinExerciseWindow(atlanticPool);

        // If position is already created, use existing one or create new
        if (userPositionId == 0) {
            userPositionId = positionsCount;

            unchecked {
                ++positionsCount;
            }

            userPositionIds[msg.sender] = userPositionId;
        }

        _newStrategyPosition(
            userPositionId,
            _expiry,
            _increaseOrder.indexToken,
            _collateralToken,
            _keepCollateral
        );

        // if a position manager is not created for the user, create one or use existing one
        if (userPositionManager == address(0)) {
            userPositionManager = positionManagerFactory.createPositionmanager(
                msg.sender
            );
        }

        _transferFrom(
            _increaseOrder.path[0],
            msg.sender,
            userPositionManager,
            _increaseOrder.collateralDelta
        );

        // Create increase order for long position
        IDopexPositionManager(userPositionManager).enableAndCreateIncreaseOrder{
            value: msg.value
        }(_increaseOrder, vault, router, positionRouter, msg.sender);

        // Called after gmx position is created since position key is generated after gmx position is opened.
        pendingOrders[
            _getPositionKey(userPositionManager, true)
        ] = userPositionId;

        emit OrderCreated(userPositionId, ActionState.EnablePending);
    }

    /**
     * @notice            Enable keepCollateral state of the strategy position
     *                    such allowing users to keep their long positions post
     *                    expiry of the atlantic put from which options were purch-
     *                    -ased from.
     * @param _positionId ID of the position.
     */
    function enableKeepCollateral(uint256 _positionId) external {
        _isEligibleSender();

        StrategyPosition memory position = strategyPositions[_positionId];

        _validate(position.user == msg.sender, 27);
        _validate(position.state != ActionState.Settled, 3);
        // Must be an active position with insurance
        _validate(position.atlanticsPurchaseId != 0, 19);
        _validate(!position.keepCollateral, 18);

        (, uint256 unwindCost) = _getOptionsPurchase(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            ),
            position.atlanticsPurchaseId
        );

        _transferFrom(
            position.indexToken,
            msg.sender,
            address(this),
            unwindCost
        );

        strategyPositions[_positionId].keepCollateral = true;
    }

    /**
     * @notice            Create a order to add collateral to managed long gmx position
     * @param _positionId ID of the strategy position in strategyPositions Mapping
     */
    function createIncreaseManagedPositionOrder(
        uint256 _positionId
    ) external payable {
        StrategyPosition memory position = strategyPositions[_positionId];

        if (msg.sender != position.user) {
            _validate(whitelistedKeepers[msg.sender] == 1, 2);
        }

        _validate(position.state != ActionState.Increased, 4);
        _validate(position.atlanticsPurchaseId != 0, 19);

        address positionManager = userPositionManagers(position.user);

        IAtlanticPutsPool pool = IAtlanticPutsPool(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            )
        );

        _validate(
            pool.getOptionsState(position.atlanticsPurchaseId) !=
                OptionsState.Settled,
            19
        );

        uint256 collateralUnlocked = _getCollateralAccess(
            address(pool),
            position.atlanticsPurchaseId
        );

        // Skip unlocking if collateral already unlocked
        if (ActionState.IncreasePending != position.state) {
            _transferFrom(
                position.collateralToken,
                position.user,
                address(this),
                pool.calculateFundingFees(collateralUnlocked, block.timestamp)
            );

            // Unlock collateral from atlantic pool
            pool.unlockCollateral(
                position.atlanticsPurchaseId,
                positionManager
            );
        } else {
            _validate(
                pool.getOptionsState(position.atlanticsPurchaseId) ==
                    OptionsState.Unlocked,
                33
            );
        }

        // Create order to add unlocked collateral
        IDopexPositionManager(positionManager).increaseOrder{value: msg.value}(
            IncreaseOrderParams(
                _get2TokenSwapPath(
                    position.collateralToken,
                    position.indexToken
                ),
                position.indexToken,
                collateralUnlocked,
                0,
                0,
                true
            )
        );

        strategyPositions[_positionId].state = ActionState.IncreasePending;
        pendingOrders[_getPositionKey(positionManager, true)] = _positionId;

        emit OrderCreated(_positionId, ActionState.IncreasePending);
    }

    /**
     * @notice            Create a order to exit from strategy and long gmx position
     * @param _positionId ID of the strategy position in strategyPositions Mapping
     */
    function createExitStrategyOrder(
        uint256 _positionId,
        address withdrawAs,
        bool exitLongPosition
    ) external payable nonReentrant {
        StrategyPosition memory position = strategyPositions[_positionId];

        _updateGmxVaultCummulativeFundingRate(position.indexToken);

        _validate(position.atlanticsPurchaseId != 0, 19);

        // Keeper can only call during keeperHandleWindow before expiry
        if (msg.sender != position.user) {
            _validate(whitelistedKeepers[msg.sender] == 1, 2);
            _validate(_isKeeperHandleWindow(position.expiry), 21);
        }
        _validate(position.state != ActionState.Settled, 3);

        address positionManager = userPositionManagers(position.user);

        uint256 collateralDelta;
        address tokenOut;
        uint256 sizeDelta;
        address[] memory path;

        // Only decrease from position is it has borrowed collateral.
        (sizeDelta, ) = _getPosition(_positionId);
        if (position.state == ActionState.Increased) {
            (tokenOut, collateralDelta) = getAmountAndTokenReceviedOnExit(
                _positionId
            );

            if (
                !utils.validateDecreaseCollateralDelta(
                    positionManager,
                    position.indexToken,
                    collateralDelta
                )
            ) {
                tokenOut = position.indexToken;
            }

            // if token out == index token, close the position
            if (tokenOut == position.indexToken) {
                path = _get1TokenSwapPath(position.indexToken);
                delete collateralDelta;

                // else only remove borrowed collateral
            } else {
                path = _get2TokenSwapPath(
                    position.indexToken,
                    position.collateralToken
                );

                // if user wishes to exit position let size delta persist. (sizeDelta assigned earlier).
                if (!exitLongPosition) {
                    delete sizeDelta;
                }
            }
        } else {
            if (exitLongPosition) {
                if (withdrawAs != position.indexToken) {
                    path = _get2TokenSwapPath(position.indexToken, withdrawAs);
                } else {
                    path = _get1TokenSwapPath(position.indexToken);
                }
            } else {
                delete sizeDelta;
            }
        }

        if (collateralDelta != 0 || sizeDelta != 0) {
            // Create order to exit position
            IDopexPositionManager(positionManager).decreaseOrder{
                value: msg.value
            }(
                DecreaseOrderParams(
                    IncreaseOrderParams(
                        path,
                        position.indexToken,
                        collateralDelta,
                        sizeDelta,
                        0,
                        true
                    ),
                    positionManager,
                    false
                )
            );

            pendingStrategyPositionToken[_positionId] = path[path.length - 1];

            strategyPositions[_positionId].state = ActionState.ExitPending;

            pendingOrders[
                _getPositionKey(positionManager, false)
            ] = _positionId;
        } else {
            if (
                strategyPositions[_positionId].state == ActionState.ExitPending
            ) {
                _exitStrategy(_positionId);
            } else {
                _exitStrategy(_positionId, position.user);
            }
        }

        emit OrderCreated(_positionId, ActionState.ExitPending);
    }

    /**
     * @notice             Callback fn called by callback forwarder
     *                     contract (instead of gmx's position router)
     *                     after an order has been executed by gmx.
     * @param positionKey  Position key in gmx's position router.
     * @param isExecuted   Everything the order was executed order.
     */
    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool
    ) external payable nonReentrant {
        _validate(whitelistedKeepers[msg.sender] == 1, 2);
        uint256 positionId = pendingOrders[positionKey];
        ActionState currentState = strategyPositions[positionId].state;

        if (currentState == ActionState.EnablePending) {
            if (isExecuted) {
                _enableStrategy(positionId);
                return;
            } else {
                _enableStrategyFail(positionId);
                return;
            }
        }
        if (currentState == ActionState.IncreasePending) {
            if (isExecuted) {
                strategyPositions[positionId].state = ActionState.Increased;
                return;
            } else {
                _increaseManagedPositionFail(positionId);
            }
            return;
        }

        if (currentState == ActionState.ExitPending) {
            _exitStrategy(positionId);
            return;
        }
    }

    /**
     * @notice            Exit strategy by abandoning the options position.
     *                    Can only be called if gmx position has no borrowed
     *                    collateral.
     * @param _positionId Id of the position in strategyPositions mapping .
     *
     */
    function emergencyStrategyExit(uint256 _positionId) public nonReentrant {
        (
            uint256 expiry,
            uint256 purchaseId,
            address indexToken,
            address collateralToken,
            address user,
            bool keepCollateral,
            ActionState state
        ) = getStrategyPosition(_positionId);

        if (msg.sender != user) {
            _validate(whitelistedKeepers[msg.sender] == 1, 2);
        }

        address atlanticPool = _getAtlanticPoolAddress(
            indexToken,
            collateralToken,
            expiry
        );

        // Position shouldn't be increased or have an increase order initationed
        _validate(
            state != ActionState.Increased &&
                state != ActionState.IncreasePending,
            26
        );

        delete pendingOrders[_getPositionKey(userPositionManagers(user), true)];

        if (keepCollateral) {
            (, uint256 amount) = _getOptionsPurchase(atlanticPool, purchaseId);

            _transfer(indexToken, user, amount);
        }

        _exitStrategy(_positionId, user);
    }

    /**
     * @notice                 Get strategy position details
     * @param _positionId      Id of the position in strategy positions
     *                         mapping
     * @return expiry
     * @return purchaseId      Options purchase id
     * @return indexToken      Address of the index token
     * @return collateralToken Address of the collateral token
     * @return user            Address of the strategy position owner
     * @return keepCollateral  Has deposited underlying to persist
     *                         borrowed collateral
     * @return state           State of the position from ActionState enum
     */
    function getStrategyPosition(
        uint256 _positionId
    )
        public
        view
        returns (uint256, uint256, address, address, address, bool, ActionState)
    {
        StrategyPosition memory position = strategyPositions[_positionId];
        return (
            position.expiry,
            position.atlanticsPurchaseId,
            position.indexToken,
            position.collateralToken,
            position.user,
            position.keepCollateral,
            position.state
        );
    }

    /**
     * @notice         Get fee charged on creating a strategy postion
     * @param _size    Size of the gmx position in 1e30 decimals
     * @param _toToken Address of the index token of the gmx position
     * @return fees    Fee amount in index token / _toToken decimals
     */
    function getPositionfee(
        uint256 _size,
        address _toToken,
        address _account
    ) public view returns (uint256 fees) {
        uint256 feeBps = feeStrategy.getFeeBps(
            STRATEGY_FEE_KEY,
            _account,
            useDiscountForFees == 1 ? true : false
        );
        uint256 usdWithFee = (_size * (10000000 + feeBps)) / 10000000;
        fees = IVault(vault).usdToTokenMin(_toToken, (usdWithFee - _size));
    }

    /**
     * @notice                  Fetch user's position manager.
     * @param _user             Address of the user.
     * @return _positionManager Address of the position manager.
     */
    function userPositionManagers(
        address _user
    ) public view returns (address _positionManager) {
        return
            IDopexPositionManagerFactory(positionManagerFactory)
                .userPositionManagers(_user);
    }

    function _exitStrategy(uint256 _positionId) private {
        StrategyPosition memory position = strategyPositions[_positionId];

        address pendingToken = pendingStrategyPositionToken[_positionId];

        IAtlanticPutsPool pool = IAtlanticPutsPool(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            )
        );

        (, uint256 unwindAmount) = _getOptionsPurchase(
            address(pool),
            position.atlanticsPurchaseId
        );

        uint256 receivedTokenAmount = IDopexPositionManager(
            userPositionManagers(position.user)
        ).withdrawTokens(_get1TokenSwapPath(pendingToken), address(this))[0];

        uint256 deductable;
        if (
            pool.getOptionsState(position.atlanticsPurchaseId) ==
            OptionsState.Unlocked
        ) {
            if (pendingToken == position.indexToken) {
                // if received tokens < unwind amount, use remaining token amount
                // Make exception if underlying was deposited
                if (
                    unwindAmount > receivedTokenAmount &&
                    !position.keepCollateral
                ) {
                    unwindAmount = receivedTokenAmount;
                }
                // unwind options
                pool.unwind(position.atlanticsPurchaseId, unwindAmount);

                if (!position.keepCollateral) {
                    deductable = unwindAmount;
                }
            } else {
                if (
                    pool
                        .getOptionsPurchase(position.atlanticsPurchaseId)
                        .state == OptionsState.Unlocked
                ) {
                    deductable = _getCollateralAccess(
                        address(pool),
                        position.atlanticsPurchaseId
                    );

                    if (deductable > receivedTokenAmount) {
                        deductable = receivedTokenAmount;
                    }
                    // Relock collateral
                    pool.relockCollateral(
                        position.atlanticsPurchaseId,
                        deductable
                    );
                }

                if (position.keepCollateral) {
                    _transfer(position.indexToken, position.user, unwindAmount);
                }
            }
        } else {
            if (position.keepCollateral) {
                _transfer(position.indexToken, position.user, unwindAmount);
            }
        }

        delete pendingStrategyPositionToken[_positionId];

        _exitStrategy(_positionId, position.user);

        _transfer(
            pendingToken,
            position.user,
            receivedTokenAmount - deductable
        );
    }

    /**
     * @notice            Get amount of a token received when
     *                    a position is closed before closing
     *                    the position and also considering if
     *                    options are ITM or not. if ITM then
     *                    token received will be the underlying
     *                    or indexToken, otherwise collateral token
     * @param _positionId ID of the position strategyPositions mapping
     * @return _tokenOut  Address of the token out.
     * @return _amount    Amount of _tokenOut receivable.
     */
    function getAmountAndTokenReceviedOnExit(
        uint256 _positionId
    ) public view returns (address _tokenOut, uint256 _amount) {
        StrategyPosition memory position = strategyPositions[_positionId];
        address positionManager = userPositionManagers(position.user);

        uint256 collateralAccess = _getCollateralAccess(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            ),
            position.atlanticsPurchaseId
        );

        uint256 marginFees = utils.getMarginFees(
            positionManager,
            position.indexToken,
            position.collateralToken
        );

        _amount = utils.getAmountReceivedOnExitPosition(
            userPositionManagers(position.user),
            position.indexToken,
            position.collateralToken
        );

        if (_amount > collateralAccess) {
            _tokenOut = position.collateralToken;

            _amount = utils.getAmountIn(
                collateralAccess + marginFees,
                IDopexPositionManager(positionManager).minSlippageBps(),
                position.collateralToken,
                position.indexToken
            );

            _amount = IVault(vault).tokenToUsdMin(position.indexToken, _amount);
        } else {
            _tokenOut = position.indexToken;
        }
    }

    /**
     * @notice            Delete states related strategy positions.
     * @param _positionId Id of the strategy position.
     * @param _user       Address of the user
     */
    function _exitStrategy(uint256 _positionId, address _user) private {
        delete strategyPositions[_positionId].atlanticsPurchaseId;
        delete strategyPositions[_positionId].expiry;
        delete strategyPositions[_positionId].keepCollateral;
        strategyPositions[_positionId].state = ActionState.Settled;
        strategyPositions[_positionId].user = _user;
        IDopexPositionManager(userPositionManagers(_user)).release();
    }

    /**
     * @notice                 Save/replace a new strategy position for a user.
     * @param _positionId      Id of the strategy position.
     * @param _expiry          Expiry of the AP options.
     * @param _indexToken      Address of the index token.
     * @param _collateralToken Address of the collateral token.
     * @param _keepCollateral  To deposit underlying or not.
     */
    function _newStrategyPosition(
        uint256 _positionId,
        uint256 _expiry,
        address _indexToken,
        address _collateralToken,
        bool _keepCollateral
    ) private {
        strategyPositions[_positionId].expiry = _expiry;
        strategyPositions[_positionId].indexToken = _indexToken;
        strategyPositions[_positionId].collateralToken = _collateralToken;
        strategyPositions[_positionId].user = msg.sender;
        strategyPositions[_positionId].keepCollateral = _keepCollateral;
        strategyPositions[_positionId].state = ActionState.EnablePending;
    }

    /**
     * @notice            Fallback for failure of execution of gmx position
     *                    order. User is refunded their collateral they used
     *                    to open the position.
     * @param _positionId ID of the strategy position.
     */
    function _enableStrategyFail(uint256 _positionId) private {
        StrategyPosition memory position = strategyPositions[_positionId];
        address positionManager = userPositionManagers(position.user);

        delete pendingOrders[_getPositionKey(positionManager, true)];

        strategyPositions[_positionId].state = ActionState.None;

        IDopexPositionManager(positionManager).withdrawTokens(
            _get1TokenSwapPath(position.collateralToken),
            position.user
        );

        _exitStrategy(_positionId, position.user);
    }

    /**
     * @notice            Fallback on successful exeuction of gmx position
     *                    order. In this fall back options are purchased
     *                    and underlying is collected if enabled to.
     * @param _positionId ID of the strategy position.
     */
    function _enableStrategy(uint256 _positionId) private {
        StrategyPosition memory position = strategyPositions[_positionId];

        address positionManager = userPositionManagers(position.user);

        address atlanticPool = _getAtlanticPoolAddress(
            position.indexToken,
            position.collateralToken,
            position.expiry
        );

        uint256 putStrike = utils.getEligiblePutStrike(
            atlanticPool,
            utils.getLiquidationPrice(positionManager, position.indexToken) /
                1e22
        );

        uint256 optionsAmount = utils.getRequiredAmountOfOptionsForInsurance(
            putStrike,
            positionManager,
            position.indexToken,
            position.collateralToken
        );

        IAtlanticPutsPool pool = IAtlanticPutsPool(atlanticPool);

        uint256 optionsCosts = pool.calculatePremium(putStrike, optionsAmount) +
            pool.calculatePurchaseFees(position.user, putStrike, optionsAmount);

        (uint256 size, ) = _getPosition(_positionId);

        // Collect strategy position fee
        _collectStrategyPositionFee(
            size,
            position.collateralToken,
            position.user
        );

        _transferFrom(
            position.collateralToken,
            position.user,
            address(this),
            optionsCosts
        );

        strategyPositions[_positionId].atlanticsPurchaseId = pool.purchase(
            putStrike,
            optionsAmount,
            address(this),
            position.user
        );

        strategyPositions[_positionId].state = ActionState.Active;

        if (position.keepCollateral) {
            _transferFrom(
                position.indexToken,
                position.user,
                address(this),
                optionsAmount
            );
        }

        ICallbackForwarder(positionManagerFactory.callback())
            .createIncreaseOrder(_positionId);

        emit StrategyEnabled(_positionId, putStrike, optionsAmount);
    }

    /**
     * @notice            Fallback for handling failure of adding collateral
     *                    to the gmx position. Collateral unlocked is relocked
     *                    back to the options pool.
     * @param _positionId ID of the strategy position.
     */
    function _increaseManagedPositionFail(uint256 _positionId) private {
        StrategyPosition memory position = strategyPositions[_positionId];

        uint256 receivedTokenAmount = IDopexPositionManager(
            userPositionManagers(position.user)
        ).withdrawTokens(
                _get1TokenSwapPath(position.collateralToken),
                address(this)
            )[0];

        IAtlanticPutsPool pool = IAtlanticPutsPool(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            )
        );

        uint256 collateralAccess = _getCollateralAccess(
            address(pool),
            position.atlanticsPurchaseId
        );

        if (receivedTokenAmount > collateralAccess) {
            _transfer(
                position.collateralToken,
                position.user,
                receivedTokenAmount - collateralAccess
            );
        }

        pool.relockCollateral(position.atlanticsPurchaseId, collateralAccess);

        strategyPositions[_positionId].state = ActionState.Active;

        ICallbackForwarder(positionManagerFactory.callback())
            .createIncreaseOrder(_positionId);
    }

    /**
     * @notice              Collect strategy fees.
     * @param _positionSize Size of the gmx position.
     * @param _tokenIn      Address of the token used
     *                      to open the gmx position with.
     */
    function _collectStrategyPositionFee(
        uint256 _positionSize,
        address _tokenIn,
        address _user
    ) private {
        uint256 fee = getPositionfee(_positionSize, _tokenIn, _user);
        _transferFrom(_tokenIn, _user, feeDistributor, fee);
        emit StrategyFeesCollected(fee);
    }

    /**
     * @notice        Check whether block.timestamp is
     *                within keeper handler window.
     * @param _expiry Expiry of the options associated with
     *                the gmx position.
     */
    function _isKeeperHandleWindow(
        uint256 _expiry
    ) private view returns (bool isInWindow) {
        return block.timestamp > _expiry - keeperHandleWindow;
    }

    /**
     * @notice             Get address of an atlantic pool.
     * @param _indexToken  Address of the index token/ base token.
     * @param _quoteToken  Address of the quote token / collateral token.
     * @param _expiry      Expiry timestamp of the pool.
     * @return poolAddress Address of the atlantic pool.
     */
    function _getAtlanticPoolAddress(
        address _indexToken,
        address _quoteToken,
        uint256 _expiry
    ) private view returns (address poolAddress) {
        return
            whitelistedAtlanticPools[
                _getPoolKey(_indexToken, _quoteToken, _expiry)
            ];
    }

    /**
     * @notice             AP addresses are stored with keys of bytes32.
     *                     hence, helper fn to generate the key.
     * @param _indexToken  Address of the index token/ base token.
     * @param _quoteToken  Address of the quote token / collateral token.
     * @param _expiry      Expiry timestamp of the pool
     */
    function _getPoolKey(
        address _indexToken,
        address _quoteToken,
        uint256 _expiry
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_indexToken, _quoteToken, _expiry));
    }

    /**
     * @notice                       Set/Add an atlantic pool usable by
     *                               this strategy contract.
     * @param _poolAddress           Address of the pool.
     * @param _indexToken            Address of the index token/ base token.
     * @param _quoteToken            Address of the quote token / collateral token.
     * @param _expiry                Expiry timestamp of the pool
     */
    function setAtlanticPool(
        address _poolAddress,
        address _indexToken,
        address _quoteToken,
        uint256 _expiry
    ) external onlyGov {
        whitelistedAtlanticPools[
            _getPoolKey(_indexToken, _quoteToken, _expiry)
        ] = _poolAddress;

        IERC20(_indexToken).approve(_poolAddress, type(uint256).max);
        IERC20(_quoteToken).approve(_poolAddress, type(uint256).max);
    }

    /**
     * @notice             Set max leverage for opening positions throuugh this
     *                     Strategy contract.
     * @param _maxLeverage Max leverage allowable.
     */
    function setMaxLeverage(uint256 _maxLeverage) external onlyGov {
        maxLeverage = _maxLeverage;
        emit MaxLeverageSet(_maxLeverage);
    }

    /**
     * @notice        Set amount of seconds before options expiry.
     *                keepers are allowed handle positions (or create
     *                orders).
     * @param _window Amount of seconds.
     */
    function setKeeperhandleWindow(uint256 _window) external onlyGov {
        keeperHandleWindow = _window;
        emit KeeperHandleWindowSet(_window);
    }

    /**
     * @notice        Set a keeper who can call:
     *                createIncreaseOrder()
     *                createExitOrder()
     *                emergencyStrategyExit()
     * @param _keeper Address of the keeper.
     * @param _setAs  True = can keep, false = cannot.
     */
    function setKeeper(address _keeper, bool _setAs) external onlyGov {
        whitelistedKeepers[_keeper] = _setAs ? 1 : 0;
        emit KeeperSet(_keeper, _setAs);
    }

    /**
     * @notice                         Set addresses of contracts used by the strategy.
     * @param _feeDistributor          Address of the fee distributor.
     * @param _utils                   Address of the utils/calculations contract.
     * @param _positionManagerFactory  Address of the position manager factory.
     * @param _gov,                    Address of the gov.
     * @param _feeStrategy             Address of dopex fee strategy contract.
     */
    function setAddresses(
        address _feeDistributor,
        address _utils,
        address _positionManagerFactory,
        address _gov,
        address _feeStrategy
    ) external onlyGov {
        feeDistributor = _feeDistributor;
        utils = IInsuredLongsUtils(_utils);
        positionManagerFactory = IDopexPositionManagerFactory(
            _positionManagerFactory
        );

        feeStrategy = IDopexFeeStrategy(_feeStrategy);
        feeDistributor = _feeDistributor;
        gov = _gov;

        emit AddressesSet(
            _feeDistributor,
            _utils,
            _positionManagerFactory,
            _gov,
            _feeStrategy
        );
    }

    /**
     * @notice Add a contract to the whitelist
     * @dev    Can only be called by the owner
     * @param _contract Address of the contract that needs to be added to the whitelist
     */
    function addToContractWhitelist(address _contract) external onlyGov {
        _addToContractWhitelist(_contract);
    }

    /**
     * @notice Add a contract to the whitelist
     * @dev    Can only be called by the owner
     * @param _contract Address of the contract that needs to be added to the whitelist
     */
    function removeFromContractWhitelist(address _contract) external onlyGov {
        _removeFromContractWhitelist(_contract);
    }

    function setUseDiscountForFees(
        bool _setAs
    ) external onlyGov returns (bool) {
        useDiscountForFees = _setAs ? 1 : 0;
        return true;
    }

    /**
     * @notice Pauses the vault for emergency cases
     * @dev     Can only be called by DEFAULT_ADMIN_ROLE
     * @return  Whether it was successfully paused
     */
    function pause() external onlyGov returns (bool) {
        _pause();
        return true;
    }

    /**
     *  @notice Unpauses the vault
     *  @dev    Can only be called by DEFAULT_ADMIN_ROLE
     *  @return success it was successfully unpaused
     */
    function unpause() external onlyGov returns (bool) {
        _unpause();
        return true;
    }

    function _updateGmxVaultCummulativeFundingRate(address _token) private {
        IVault(vault).updateCumulativeFundingRate(_token);
    }

    /**
     * @notice               Transfers all funds to msg.sender
     * @dev                  Can only be called by DEFAULT_ADMIN_ROLE
     * @param tokens         The list of erc20 tokens to withdraw
     * @param transferNative Whether should transfer the native currency
     */
    function emergencyWithdraw(
        address[] calldata tokens,
        bool transferNative
    ) external onlyGov returns (bool) {
        _whenPaused();
        if (transferNative) payable(gov).transfer(address(this).balance);

        for (uint256 i; i < tokens.length; ) {
            _transfer(
                tokens[i],
                gov,
                IERC20(tokens[i]).balanceOf(address(this))
            );
            unchecked {
                ++i;
            }
        }

        return true;
    }

    /**
     * @notice              Fetch options purchase data from AP.
     * @param _atlanticPool Address of the atlantic pool.
     * @param _purchaseId   ID of the options purchase.
     * @return strike       Strike of the options.
     * @return amount       Amount of options.
     */
    function _getOptionsPurchase(
        address _atlanticPool,
        uint256 _purchaseId
    ) private view returns (uint256 strike, uint256 amount) {
        OptionsPurchase memory position = IAtlanticPutsPool(_atlanticPool)
            .getOptionsPurchase(_purchaseId);
        strike = position.optionStrike;
        amount = position.optionsAmount;
    }

    /**
     * @notice                  Fetch Collateral access or amount of
     *                          collateral a gmx position can borrow
     *                          against the AP options.
     * @param _atlanticPool     Address of the atlantic pool the op-
     *                          tions were purchased from.
     * @param _purchaseId       ID of the options purchase.
     * @return collateralAccess Amount of collateral access.
     */
    function _getCollateralAccess(
        address _atlanticPool,
        uint256 _purchaseId
    ) private view returns (uint256 collateralAccess) {
        (uint256 strike, uint256 amount) = _getOptionsPurchase(
            _atlanticPool,
            _purchaseId
        );
        collateralAccess = IAtlanticPutsPool(_atlanticPool).strikeMulAmount(
            strike,
            amount
        );
    }

    /**
     * @notice             Fetch gmx position size and collateral.
     * @param _positionId  ID of the position in strategy positions.
     * @return _size       Size of the gmx position.
     * @return _collateral Collateral balance of the gmx position
     */
    function _getPosition(
        uint256 _positionId
    ) private view returns (uint256 _size, uint256 _collateral) {
        (_size, _collateral, , , , , , ) = IVault(vault).getPosition(
            userPositionManagers(strategyPositions[_positionId].user),
            strategyIndexToken,
            strategyIndexToken,
            true
        );
    }

    /**
     * @notice Fetch the unique key created when a position manager
     *         calls GMX position router contract to create an order
     *         the return key is directly linked to the order in the GMX
     *         position router contract.
     * @param  _positionManager Address of the position manager
     * @param  _isIncrease      Whether to create an order to increase
     *                          collateral size of a position or decrease
     *                          it.
     * @return key
     */
    function _getPositionKey(
        address _positionManager,
        bool _isIncrease
    ) private view returns (bytes32 key) {
        IPositionRouter _positionRouter = IPositionRouter(positionRouter);

        if (_isIncrease) {
            key = _positionRouter.getRequestKey(
                _positionManager,
                _positionRouter.increasePositionsIndex(_positionManager)
            );
        } else {
            key = _positionRouter.getRequestKey(
                _positionManager,
                _positionRouter.decreasePositionsIndex(_positionManager)
            );
        }
    }

    /**
     * @notice Create and return an array of 1 item.
     * @param _token Address of the token.
     * @return path
     */
    function _get1TokenSwapPath(
        address _token
    ) private pure returns (address[] memory path) {
        path = new address[](1);
        path[0] = _token;
    }

    /**
     * @notice Create and return an 2 item array of addresses used for
     *         swapping.
     * @param _token1 Token in or input token.
     * @param _token2 Token out or output token.
     * @return path
     */
    function _get2TokenSwapPath(
        address _token1,
        address _token2
    ) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = _token1;
        path[1] = _token2;
    }

    function _validteNotWithinExerciseWindow(
        address _atlanticPool
    ) private view {
        _validate(
            !IAtlanticPutsPool(_atlanticPool).isWithinExerciseWindow(),
            34
        );
    }

    modifier onlyGov() {
        _validate(msg.sender == gov, 32);
        _;
    }

    function _transfer(address _token, address _to, uint256 _amount) internal {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _transferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    function _validate(bool trueCondition, uint256 errorCode) private pure {
        if (!trueCondition) {
            revert InsuredLongsStrategyError(errorCode);
        }
    }
}

