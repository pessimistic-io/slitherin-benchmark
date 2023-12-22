//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import {IAtlanticPutsPool} from "./IAtlanticPutsPool.sol";
import {IRouter} from "./IRouter.sol";
import {IVault} from "./IVault.sol";
import {IERC20} from "./IERC20.sol";
import {IDopexPositionManager, IncreaseOrderParams, DecreaseOrderParams} from "./IDopexPositionManager.sol";
import {IInsuredLongsUtils} from "./IInsuredLongsUtils.sol";
import {IInsuredLongsStrategy} from "./IInsuredLongsStrategy.sol";
import {IDopexPositionManagerFactory} from "./IDopexPositionManagerFactory.sol";
import {ICallbackForwarder} from "./ICallbackForwarder.sol";
import {IDopexFeeStrategy} from "./IDopexFeeStrategy.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {Pausable} from "./Pausable.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

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

    /**
     * @notice Time window in which whitelisted keeper can settle positions.
     */
    uint256 public keeperHandleWindow;

    uint256 public maxLeverage;

    /**
     * @notice Multiplier Bps used to calculate extra amount of
     *         collateral required to exist in a long position such
     *         that it has enough to be unwinded back to its
     *         respective atlantic pool if the position has borrowed
     *         collateral and mark price has decreased way below
     *         liquidation price.
     */
    uint256 public liquidationCollateralMultiplierBps;

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
     * @notice A multiplier applied to an atlantic pool's ticksize
     *         when calculating liquidation price. This multiplier
     *         summed up with liquidation price gives a price suitable
     *         for insuring the long position.
     *
     *         same Offset bps will be applied to strike price which acts
     *         as threshold to persist unlocked collateral in the
     *         long position. If mark price of the index token
     *         crosses this trigger price (strike + offsetBps)
     *         collateral will be removed from the long position
     *         and relocked back into the atlantic pool that it
     *         was borrowed from.
     */
    mapping(address => uint256) public tickSizeMultiplierBps;

    /**
     * @notice Keepers are EOA or contracts that will have special
     *         permissions required to carry out insurance related
     *         functions available in this contract.
     *         1. Create a order to add collateral to a position.
     *         2. Create a order to remove collateral from a position.
     *         3. Create a order to exit a position.
     */
    mapping(address => bool) public whitelistedKeepers;

    /**
     * @notice Number of positions active (not settled.)
     *         if it is equal to zero then contract is allowed
     *         to withdraw fee tokens.
     */
    uint256 public activePositions;

    /**
     * @notice Atlantic Put pools that can be used by this strategy contract
     *         for purchasing put options, unlocking, relocking and unwinding of
     *         collateral.
     */
    mapping(bytes32 => address) public whitelistedAtlanticPools;

    mapping(address => bool) public whitelistedUsers;

    mapping(uint256 => address) public pendingStrategyPositionToken;

    address public positionRouter;
    address public router;
    address public vault;
    address public feeDistributor;
    address public gov;
    IDopexFeeStrategy public feeStrategy;

    bool public whitelistMode = true;
    bool public useDiscountForFees = true;

    /**
     *  @notice Index token supported by this strategy contract.
     */
    address public strategyIndexToken;

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
        liquidationCollateralMultiplierBps = 300;
        feeStrategy = IDopexFeeStrategy(_feeStrategy);
    }

    /**
     * @notice Reuse strategy for a position manager that has an active
     *         gmx position.
     *
     * @param _positionId     ID of the position in strategyPositions mapping
     * @param _expiry         Expiry of the insurance
     * @param _keepCollateral Whether to deposit underlying to allow unwinding
     *                        of options
     */
    function reuseStrategy(
        uint256 _positionId,
        uint256 _expiry,
        bool _keepCollateral
    ) external onlyWhitelistedUser {
        _isEligibleSender();
        _whenNotPaused();

        StrategyPosition memory position = strategyPositions[_positionId];

        address userPositionManager = userPositionManagers(msg.sender);

        _validate(position.atlanticsPurchaseId == 0, 28);
        _validate(msg.sender == position.user, 27);
        _validate(
            utils.getPositionLeverage(
                userPositionManager,
                position.indexToken
            ) <= maxLeverage,
            30
        );

        uint256 positionSize = utils.getPositionSize(
            userPositionManager,
            position.indexToken
        );

        _validate(positionSize > 0, 5);

        IDopexPositionManager(userPositionManager).lock();

        position.expiry = _expiry;
        position.keepCollateral = _keepCollateral;

        strategyPositions[_positionId] = position;

        // Collect strategy position fee
        _collectPositionFee(
            positionSize,
            position.collateralToken,
            position.indexToken
        );

        unchecked {
            ++activePositions;
        }

        _enableStrategy(_positionId);

        emit ReuseStrategy(_positionId);
    }

    /**
     * @notice                 Create strategy postiion and create long position order
     * @param _increaseOrder   Parameters related to the long position to open
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
    ) external payable onlyWhitelistedUser nonReentrant {
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

        // Must have enough collateral for fees
        _validate(
            !utils.validateIncreaseExecution(
                _increaseOrder.collateralDelta,
                _increaseOrder.positionSizeDelta,
                _increaseOrder.path[0],
                _increaseOrder.indexToken
            ),
            17
        );

        // Must to exceed max leverage
        _validate(
            utils.calculateLeverage(
                _increaseOrder.positionSizeDelta,
                _increaseOrder.collateralDelta,
                _increaseOrder.path[0]
            ) <= maxLeverage,
            30
        );

        address userPositionManager = userPositionManagers(msg.sender);
        uint256 userPositionId = userPositionIds[msg.sender];

        // Should not have open positions
        _validate(
            utils.getPositionSize(
                userPositionManager,
                _increaseOrder.indexToken
            ) == 0,
            29
        );

        // If position ID and manager is already created for the user, ensure it's a settled one
        _validate(
            strategyPositions[userPositionId].atlanticsPurchaseId == 0,
            9
        );

        _validate(
            _getAtlanticPoolAddress(
                _increaseOrder.indexToken,
                _collateralToken,
                _expiry
            ) != address(0),
            8
        );

        unchecked {
            ++activePositions;
        }

        // If position "state" is already created, use existing one or create new
        if (userPositionId == 0) {
            userPositionId = positionsCount;
            unchecked {
                ++positionsCount;
            }

            _newStrategyPosition(
                userPositionId,
                _expiry,
                _increaseOrder.indexToken,
                _collateralToken,
                _keepCollateral
            );
            userPositionIds[msg.sender] = userPositionId;
        } else {
            _newStrategyPosition(
                userPositionId,
                _expiry,
                _increaseOrder.indexToken,
                _collateralToken,
                _keepCollateral
            );
        }

        // if a position manager is not created for the user, create one or use existing one
        if (userPositionManager == address(0)) {
            userPositionManager = positionManagerFactory.createPositionmanager(
                msg.sender
            );
        }

        _safeTransferFrom(
            _increaseOrder.path[0],
            msg.sender,
            userPositionManager,
            _increaseOrder.collateralDelta
        );

        // Create increase order for long position
        IDopexPositionManager(userPositionManager).enableAndCreateIncreaseOrder{
            value: msg.value
        }(_increaseOrder, vault, router, positionRouter, msg.sender);

        pendingOrders[
            utils.getPositionKey(userPositionManager, true)
        ] = userPositionId;

        // Collect strategy position fee
        if (_increaseOrder.path.length > 1) {
            _collectPositionFee(
                _increaseOrder.positionSizeDelta,
                _increaseOrder.path[0],
                _increaseOrder.path[_increaseOrder.path.length - 1]
            );
        } else {
            _collectPositionFee(
                _increaseOrder.positionSizeDelta,
                _increaseOrder.path[0],
                _collateralToken
            );
        }

        emit UseStrategy(userPositionId);
    }

    /**
     * @notice Enable keepCollateral state of the strategy position
     *         such allowing users to keep their long positions post
     *         expiry of the atlantic put from which options were purch-
     *         -ased from.
     */
    function enableKeepCollateral(uint256 _positionId) external {
        _isEligibleSender();
        StrategyPosition memory position = strategyPositions[_positionId];

        _validate(position.user == msg.sender, 27);
        _validate(position.state != ActionState.Settled, 3);
        // Must be an active position with insurance
        _validate(position.atlanticsPurchaseId != 0, 19);
        _validate(!position.keepCollateral, 18);

        uint256 unwindCost = utils.getAtlanticUnwindCosts(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            ),
            position.atlanticsPurchaseId,
            false
        );

        _safeTransferFrom(
            position.indexToken,
            msg.sender,
            address(this),
            unwindCost
        );

        strategyPositions[_positionId].keepCollateral = true;
        emit KeepCollateralEnabled(_positionId);
    }

    /**
     * @notice            Create a order to add collateral to managed long gmx position
     * @param _positionId ID of the strategy position in strategyPositions Mapping
     */
    function createIncreaseManagedPositionOrder(
        uint256 _positionId
    ) external payable {
        // Only whitelisted keepers are allowed to execute
        _validate(whitelistedKeepers[msg.sender], 2);

        StrategyPosition memory position = strategyPositions[_positionId];

        _validate(position.atlanticsPurchaseId != 0, 19);
        _validate(position.state != ActionState.Increased, 4);

        address positionManager = userPositionManagers(position.user);
        IAtlanticPutsPool pool = IAtlanticPutsPool(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            )
        );

        uint256 collateralUnlocked = utils.getCollateralAccess(
            address(pool),
            position.atlanticsPurchaseId
        );

        uint256 fundingFees = pool.calculateFundingFees(
            position.user,
            collateralUnlocked
        );

        // Skip unlocking if collateral already unlocked
        if (ActionState.IncreasePending != position.state) {
            _safeTransferFrom(
                position.collateralToken,
                position.user,
                address(this),
                fundingFees
            );

            // Unlock collateral from atlantic pool
            pool.unlockCollateral(
                position.atlanticsPurchaseId,
                positionManager,
                position.user
            );
        }

        // Create order to add unlocked collateral
        IDopexPositionManager(positionManager).increaseOrder{value: msg.value}(
            IncreaseOrderParams(
                utils.get2TokenSwapPath(
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
        pendingOrders[
            utils.getPositionKey(positionManager, true)
        ] = _positionId;

        emit ManagedPositionIncreaseOrderSuccess(_positionId);
    }

    /**
     * @notice            Create a order to exit from strategy and long gmx position
     * @param _positionId ID of the strategy position in strategyPositions Mapping
     */
    function createExitStrategyOrder(
        uint256 _positionId,
        bool exitLongPosition
    ) external payable nonReentrant {
        StrategyPosition memory position = strategyPositions[_positionId];

        _updateGmxVaultCummulativeFundingRate(position.indexToken);

        _validate(position.atlanticsPurchaseId != 0, 19);

        // Keeper can only call during keeperHandleWindow before expiry
        if (msg.sender != position.user) {
            _validate(whitelistedKeepers[msg.sender], 2);
            if (!_isKeeperHandleWindow(position.expiry)) {
                _validate(isManagedPositionLiquidatable(_positionId), 21);
            }
        }
        _validate(position.state != ActionState.Settled, 3);

        address positionManager = userPositionManagers(position.user);

        address[] memory swapPath = isManagedPositionDecreasable(_positionId)
            ? utils.get2TokenSwapPath(
                position.indexToken,
                position.collateralToken
            )
            : utils.get1TokenSwapPath(position.indexToken);

        uint256 sizeDelta = exitLongPosition
            ? utils.getPositionSize(positionManager, position.indexToken)
            : 0;

        uint256 collateralDelta;
        // if position has borrowed collateral and user wishes to exit
        if (position.state == ActionState.Increased && !exitLongPosition) {
            collateralDelta = IVault(vault).tokenToUsdMin(
                swapPath[0],
                utils.getAmountIn(
                    utils.getCollateralAccess(
                        _getAtlanticPoolAddress(
                            position.indexToken,
                            position.collateralToken,
                            position.expiry
                        ),
                        position.atlanticsPurchaseId
                    ) +
                        utils.getMarginFees(
                            positionManager,
                            position.indexToken,
                            position.collateralToken
                        ),
                    IDopexPositionManager(positionManager).minSlippageBps(),
                    position.collateralToken,
                    position.indexToken
                )
            );
        }

        if (collateralDelta > 0) {
            _validate(
                utils.validateDecreaseCollateralDelta(
                    positionManager,
                    position.indexToken,
                    collateralDelta
                ),
                31
            );
        }

        if (collateralDelta > 0 || sizeDelta > 0) {
            // Create order to exit position
            IDopexPositionManager(positionManager).decreaseOrder{
                value: msg.value
            }(
                DecreaseOrderParams(
                    IncreaseOrderParams(
                        swapPath,
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

            pendingStrategyPositionToken[_positionId] = swapPath[
                swapPath.length - 1
            ];

            strategyPositions[_positionId].state = ActionState.ExitPending;

            pendingOrders[
                utils.getPositionKey(positionManager, false)
            ] = _positionId;
        } else {
            _exitStrategy(_positionId, position.user);
        }
        emit CreateExitStrategyOrder(_positionId);
    }

    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool
    ) external payable nonReentrant {
        _validate(whitelistedKeepers[msg.sender], 2);
        uint256 positionId = pendingOrders[positionKey];
        ActionState currentState = strategyPositions[positionId].state;

        if (currentState == ActionState.EnablePending) {
            if (isExecuted) {
                _enableStrategy(positionId);
                return;
            } else {
                emergencyStrategyExit(positionId);
                return;
            }
        }
        if (currentState == ActionState.IncreasePending) {
            if (isExecuted) {
                strategyPositions[positionId].state = ActionState.Increased;
                return;
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
            _validate(whitelistedKeepers[msg.sender], 2);
        }

        address atlanticPool = _getAtlanticPoolAddress(
            indexToken,
            collateralToken,
            expiry
        );

        _validate(state != ActionState.Increased, 26);

        if (keepCollateral) {
            (, uint256 amount) = _getOptionsPurchase(atlanticPool, purchaseId);

            _safeTransfer(indexToken, user, amount);
        }

        _exitStrategy(_positionId, user);

        emit EmergencyStrategyExit(_positionId);
    }

    /**
     * @notice              Check if a managed position can have added collateral
     *                      removed and relocked into atlantics pool
     * @param  _positionId  ID of the position in strategyPositions mapping
     * @return isDecreasable
     */
    function isManagedPositionDecreasable(
        uint256 _positionId
    ) public view returns (bool isDecreasable) {
        StrategyPosition memory position = strategyPositions[_positionId];

        address pool = _getAtlanticPoolAddress(
            position.indexToken,
            position.collateralToken,
            position.expiry
        );

        (uint256 strike, ) = _getOptionsPurchase(
            pool,
            position.atlanticsPurchaseId
        );

        isDecreasable =
            utils.getPrice(position.indexToken) >=
            getStrikeWithOffsetBps(strike, pool);
    }

    /**
     * @notice Check if a long position has enough collateral + offset
     *         to unwind. After which the position must be strictly closed.
     *         positions of users who have deposited collateral will be ignored.
     * @param  _positionId  ID of the position in strategyPositions mapping
     * @return isLiquidatable
     */
    function isManagedPositionLiquidatable(
        uint256 _positionId
    ) public view returns (bool isLiquidatable) {
        StrategyPosition memory position = strategyPositions[_positionId];

        if (position.atlanticsPurchaseId == 0) return false;

        uint256 unwindCosts = (utils.getAtlanticUnwindCosts(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            ),
            position.atlanticsPurchaseId,
            false
        ) * (BPS_PRECISION + liquidationCollateralMultiplierBps)) /
            BPS_PRECISION;

        uint256 amountOut = utils.getAmountReceivedOnExitPosition(
            userPositionManagers(position.user),
            position.indexToken,
            address(0)
        );

        if (!position.keepCollateral) {
            if (position.state == ActionState.Increased) {
                isLiquidatable = unwindCosts > amountOut;
            }
        }
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
        // Unchecked meant first usdWithFee calculation
        // Overflow/underflow is checked within IVault().usdToTokenMin()
        unchecked {
            uint256 feeBps = feeStrategy.getFeeBps(
                STRATEGY_FEE_KEY,
                _account,
                useDiscountForFees
            );
            uint256 usdWithFee = (_size * (10000000 + feeBps)) / 10000000;
            fees = IVault(vault).usdToTokenMin(_toToken, (usdWithFee - _size));
        }
    }

    /**
     * @notice            Get strike amount added with offset bps of
     *                    the index token
     * @param _strike     Strike of the option
     * @param _pool Address of the index token / underlying
     *                     of the option
     */
    function getStrikeWithOffsetBps(
        uint256 _strike,
        address _pool
    ) public view returns (uint256 strikeWithOffset) {
        unchecked {
            uint256 offset = (IAtlanticPutsPool(_pool)
                .getCurrentEpochTickSize() *
                (BPS_PRECISION + tickSizeMultiplierBps[_pool])) / BPS_PRECISION;
            strikeWithOffset = _strike + offset;
        }
    }

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
        uint256 receivedTokens = IDopexPositionManager(
            userPositionManagers(position.user)
        ).withdrawTokens(utils.get1TokenSwapPath(pendingToken), address(this))[
                0
            ];

        IAtlanticPutsPool pool = IAtlanticPutsPool(
            _getAtlanticPoolAddress(
                position.indexToken,
                position.collateralToken,
                position.expiry
            )
        );

        uint256 unwindAmount = utils.getAtlanticUnwindCosts(
            address(pool),
            position.atlanticsPurchaseId,
            true
        );

        uint256 deductable;
        if (pendingToken == position.indexToken) {
            pool.unwind(position.atlanticsPurchaseId);
            if (!position.keepCollateral) {
                deductable = unwindAmount;
            }
        } else {
            if (pool.getOptionsPurchase(position.atlanticsPurchaseId).unlock) {
                deductable = utils.getCollateralAccess(
                    address(pool),
                    position.atlanticsPurchaseId
                );
                // Relock collateral
                pool.relockCollateral(position.atlanticsPurchaseId);
            }

            if (position.keepCollateral) {
                _safeTransfer(position.indexToken, position.user, unwindAmount);
            }
        }

        delete pendingStrategyPositionToken[_positionId];

        _exitStrategy(_positionId, position.user);

        _safeTransfer(pendingToken, position.user, receivedTokens - deductable);

        emit ManagedPositionExitStrategy(_positionId);
    }

    function _exitStrategy(uint256 _positionId, address _user) private {
        delete strategyPositions[_positionId].atlanticsPurchaseId;
        delete strategyPositions[_positionId].expiry;
        delete strategyPositions[_positionId].keepCollateral;
        strategyPositions[_positionId].state = ActionState.Settled;
        strategyPositions[_positionId].user = _user;
        unchecked {
            --activePositions;
        }
        IDopexPositionManager(userPositionManagers(_user)).release();
    }

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
            tickSizeMultiplierBps[atlanticPool],
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

        _safeTransferFrom(
            position.collateralToken,
            position.user,
            address(this),
            optionsCosts
        );

        uint256 purchaseId = pool.purchase(
            putStrike,
            optionsAmount,
            address(this),
            position.user
        );

        strategyPositions[_positionId].atlanticsPurchaseId = purchaseId;
        strategyPositions[_positionId].state = ActionState.Active;

        if (position.keepCollateral) {
            _safeTransferFrom(
                position.indexToken,
                position.user,
                address(this),
                utils.getAtlanticUnwindCosts(atlanticPool, purchaseId, false)
            );
        }

        ICallbackForwarder(positionManagerFactory.callback())
            .createIncreaseOrder(_positionId);

        emit StrategyPositionEnabled(_positionId);
    }

    function _collectPositionFee(
        uint256 _positionSize,
        address _tokenIn,
        address _tokenOut
    ) private {
        uint256 fee = getPositionfee(_positionSize, _tokenIn, msg.sender);
        _safeTransferFrom(_tokenIn, msg.sender, address(this), fee);
        _balanceFeeReserves(fee, _tokenIn, _tokenOut);
    }

    function _isKeeperHandleWindow(
        uint256 _expiry
    ) private view returns (bool isInWindow) {
        // Unchecked because keeperHandleWindow is hours/minutes unix timestamp format
        unchecked {
            return block.timestamp > _expiry - keeperHandleWindow;
        }
    }

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

    function _getPoolKey(
        address _indexToken,
        address _quoteToken,
        uint256 _expiry
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_indexToken, _quoteToken, _expiry));
    }

    function setAtlanticPool(
        address _poolAddress,
        address _indexToken,
        address _quoteToken,
        uint256 _expiry,
        uint256 _tickSizeMultiplierBps
    ) external onlyGov {
        whitelistedAtlanticPools[
            _getPoolKey(_indexToken, _quoteToken, _expiry)
        ] = _poolAddress;
        tickSizeMultiplierBps[_poolAddress] = _tickSizeMultiplierBps;

        _safeApprove(_indexToken, _poolAddress, type(uint256).max);
        _safeApprove(_quoteToken, _poolAddress, type(uint256).max);

        emit AtlanticPoolWhitelisted(
            _poolAddress,
            _quoteToken,
            _indexToken,
            _expiry,
            _tickSizeMultiplierBps
        );
    }

    function setMaxLeverage(uint256 _maxLeverage) external onlyGov {
        maxLeverage = _maxLeverage;
    }

    function setLiquidationCollateralMultiplierBps(
        uint256 _multiplier
    ) external onlyGov {
        liquidationCollateralMultiplierBps = _multiplier;
        emit LiquidationCollateralMultiplierBpsSet(_multiplier);
    }

    function setKeeperhandleWindow(uint256 _window) external onlyGov {
        keeperHandleWindow = _window;
    }

    function setKeeper(address _keeper, bool setAs) external onlyGov {
        whitelistedKeepers[_keeper] = setAs;
    }

    function whitelistUsers(
        address[] calldata _users,
        bool[] calldata _whitelist
    ) external onlyGov {
        for (uint256 i; i < _users.length; ) {
            whitelistedUsers[_users[i]] = _whitelist[i];
            unchecked {
                ++i;
            }
        }
    }

    function setWhitelistMode(bool _mode) external onlyGov {
        whitelistMode = _mode;
    }

    function setAddresses(
        address _positionRouter,
        address _router,
        address _vault,
        address _feeDistributor,
        address _utils,
        address _positionManagerFactory
    ) external onlyGov {
        positionRouter = _positionRouter;
        router = _router;
        vault = _vault;
        feeDistributor = _feeDistributor;
        utils = IInsuredLongsUtils(_utils);
        positionManagerFactory = IDopexPositionManagerFactory(
            _positionManagerFactory
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
        useDiscountForFees = _setAs;
        emit UseDiscountForFeesSet(_setAs);
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
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        for (uint256 i; i < tokens.length; ) {
            IERC20 token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
            unchecked {
                ++i;
            }
        }

        return true;
    }

    /**
     * @notice Withdraw fees in tokens.
     * @param _tokens   Addresses of tokens to withdraw fees for.
     * @return _amounts Amounts of tokens withdrawn.
     */
    function withdrawFees(
        address[] calldata _tokens
    ) external onlyGov returns (uint256[] memory _amounts) {
        _validate(activePositions == 0, 123);

        if (_tokens.length > 0) {
            _amounts = new uint256[](_tokens.length);

            for (uint256 i; i < _tokens.length; ) {
                _amounts[i] = IERC20(_tokens[i]).balanceOf(address(this));

                _safeTransfer(_tokens[i], feeDistributor, _amounts[i]);

                unchecked {
                    ++i;
                }
            }
        }
    }

    function _safeTransferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) private {
        IERC20(_token).safeTransferFrom(_from, _to, _amount);
    }

    function _safeApprove(
        address _token,
        address _spender,
        uint256 _amount
    ) private {
        IERC20(_token).safeApprove(_spender, _amount);
    }

    function _safeTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) private {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _validate(bool trueCondition, uint256 errorCode) private pure {
        if (!trueCondition) {
            revert InsuredLongsStrategyError(errorCode);
        }
    }

    /**
     * @notice Swap fee tokens to ensure 50-50 ratio.
     * @param _amountIn Amount of tokens.
     * @param _tokenIn  Address of the token received.
     * @param _tokenOut Address of the token to swap to.
     */
    function _balanceFeeReserves(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) private {
        _amountIn = (_amountIn / 2);
        uint256 received = IERC20(_tokenOut).balanceOf(address(this));
        _safeApprove(_tokenIn, router, _amountIn);
        IRouter(router).swap(
            utils.get2TokenSwapPath(_tokenIn, _tokenOut),
            _amountIn,
            0,
            address(this)
        );
        received = IERC20(_tokenOut).balanceOf(address(this)) - received;
    }

    function _getOptionsPurchase(
        address _atlanticPool,
        uint256 _purchaseId
    ) private view returns (uint256 strike, uint256 amount) {
        (strike, amount) = utils.getOptionsPurchase(_atlanticPool, _purchaseId);
    }

    modifier onlyWhitelistedUser() {
        if (whitelistMode) {
            _validate(whitelistedUsers[msg.sender], 10);
        }
        _;
    }

    modifier onlyGov() {
        _validate(msg.sender == gov, 32);
        _;
    }
}

