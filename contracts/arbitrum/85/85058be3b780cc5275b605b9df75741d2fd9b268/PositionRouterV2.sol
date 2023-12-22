// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./UUPSUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./BasePositionV2.sol";
import "./ISwapRouterV2.sol";
import "./IPositionRouterV2.sol";
import "./IVaultV2.sol";
import "./IVaultUtilsV2.sol";

import {Position, OrderInfo, VaultBond, OrderStatus} from "./Structs.sol";

contract PositionRouterV2 is BasePositionV2, IPositionRouterV2, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    mapping(bytes32 => PrepareTransaction) private txns;
    mapping(bytes32 => mapping(uint256 => TxDetail)) private txnDetails;

    IVaultV2 public vault;
    IVaultUtilsV2 public vaultUtils; 
    address public triggerOrderManager;

    //Implement later
    ISwapRouterV2 public swapRouter; 
    uint256[50] private __gap;
    
    event FinalInitialized(
        address priceManager,
        address settingsManager,
        address positionHandler,
        address positionKeeper,
        address vault, 
        address vaultUtils,
        address triggerOrderManager
    );
    event SetSwapRouter(address swapRouter);
    event CreatePrepareTransaction(
        address indexed account,
        bool isLong,
        uint256 posId,
        uint256 txType,
        uint256[] params,
        address[] path,
        bytes32 indexed key,
        bool isFastExecute
    );
    event ExecutionReverted(
        bytes32 key, 
        address account, 
        bool isLong, 
        uint256 posId, 
        uint256[] params, 
        uint256[] prices,
        address[] collateralPath,
        uint256 txType,
        string err
    );

    function initialize (
        address _priceManager,
        address _settingsManager,
        address _positionHandler, 
        address _positionKeeper,
        address _vault, 
        address _vaultUtils,
        address _triggerOrderManager
    ) public initializer {
        require(AddressUpgradeable.isContract(_vault) 
            && AddressUpgradeable.isContract(_vaultUtils)
            && AddressUpgradeable.isContract(_triggerOrderManager), "IVLCA"); //Invalid contract address
        _initialize(
            _priceManager,
            _settingsManager,
            _positionHandler, 
            _positionKeeper
        );
        vault = IVaultV2(_vault);
        vaultUtils = IVaultUtilsV2(_vaultUtils);
        triggerOrderManager = _triggerOrderManager;
        emit FinalInitialized(
            _priceManager,
            _settingsManager,
            _positionHandler, 
            _positionKeeper,
            _vault, 
            _vaultUtils, 
            _triggerOrderManager
        );
    }

    function _authorizeUpgrade(address) internal override onlyOwner {
        
    }

    function setSwapRouter(address _swapRouter) external onlyOwner {
        require(AddressUpgradeable.isContract(_swapRouter), "IVLCA"); //Invalid contract address
        swapRouter = ISwapRouterV2(_swapRouter);
        emit SetSwapRouter(_swapRouter);
    }
    
    function openNewPosition(
        bool _isLong,
        OrderType _orderType,
        uint256[] memory _params,
        address[] memory _path
    ) external payable nonReentrant {
        require(!settingsManager.isEmergencyStop(), "EMSTP"); //Emergency stopped
        bool shouldSwap = _prevalidateAndCheckSwapAndAom(_path, _getLastParams(_params));

        if (_orderType != OrderType.MARKET) {
            require(msg.value == settingsManager.triggerGasFee(), "IVLTGF"); //Invalid triggerGasFee
            payable(settingsManager.getFeeManager()).transfer(msg.value);
        }

        uint256 txType;

        //Scope to avoid stack too deep error
        {
            txType = _getTransactionTypeFromOrder(_orderType);
            _verifyParamsLength(txType, _params);
        }

        bool isFastExecute;
        uint256[] memory prices;

        {
            (isFastExecute, prices) = _getPricesAndCheckFastExecute(_path);
            vaultUtils.validatePositionData(
                _isLong, 
                _getFirstPath(_path), 
                _orderType, 
                _getFirstParams(prices), 
                _params, 
                true,
                isFastExecute
            );
        }

        (bytes32 key, Position memory position, OrderInfo memory order) = _createPosition(
            msg.sender,
            _isLong,
            _orderType,
            txType,
            _path,
            _params
        );

        _modifyPosition(
            key,
            txType,
            true, //isTakeAssetRequired = true for openNewPosition
            shouldSwap,
            isFastExecute = txType != CREATE_POSITION_MARKET ? false : isFastExecute, //Only fast execute for market type
            _path,
            prices,
            abi.encode(position, order)
        );
    }

    function _createPosition(
        address _account,
        bool _isLong,
        OrderType _orderType,
        uint256 _txType,
        address[] memory _path,
        uint256[] memory _params
    ) internal returns (bytes32, Position memory, OrderInfo memory) {
        uint256 posId = positionKeeper.lastPositionIndex(_account);
        bytes32 key = _getPositionKey(_account, _path[0], _isLong, posId);
        require(txnDetails[key][_txType].params.length == 0, "InP");
        txnDetails[key][_txType].params = _params;

        Position memory position;
        OrderInfo memory order;

        //Scope to avoid stack too deep error
        {
            (position, order) = positionKeeper.getPositions(key);
            require(position.owner == address(0), "IVLPO/E"); //Invalid positionOwner/existed
            position.owner = msg.sender;
            position.indexToken = _path[0];
            position.posId = posId;
            position.isLong = _isLong;

            order.pendingCollateral = _params[4];
            order.pendingSize = _params[5];
            order.collateralToken = _path[1];
            order.status = OrderStatus.PENDING;
        }

        if (_orderType == OrderType.MARKET) {
            order.positionType = POSITION_MARKET;
        } else if (_orderType == OrderType.LIMIT) {
            order.positionType = POSITION_LIMIT;
            order.lmtPrice = _params[2];
        } else if (_orderType == OrderType.STOP) {
            order.positionType = POSITION_STOP_MARKET;
            order.stpPrice = _params[3];
        } else if (_orderType == OrderType.STOP_LIMIT) {
            order.positionType = POSITION_STOP_LIMIT;
            order.lmtPrice = _params[2];
            order.stpPrice = _params[3];
        } else {
            revert("IVLOT"); //Invalid order type
        }

        return (key, position, order);
    }

    function _revertExecute(
        bytes32 _key, 
        uint256 _txType,
        uint256[] memory _params, 
        uint256[] memory _prices, 
        address[] memory _path,
        string memory err
    ) internal {
        if (_isTakeAssetBackRequired(_txType)) {
            _takeAssetBack(_key, _txType);
        }

        Position memory position = positionKeeper.getPosition(_key);

        if (_txType == CREATE_POSITION_MARKET || 
            _txType == ADD_TRAILING_STOP || 
            _txType == ADD_COLLATERAL ||
            _isDelayPosition(_txType)) {
                positionHandler.modifyPosition(
                    _key,
                    REVERT_EXECUTE,
                    _path,
                    _prices,
                    abi.encode(_txType, position)
                );
        }

        _clearPrepareTransaction(_key, _txType);

        emit ExecutionReverted(
            _key,
            position.owner,
            position.isLong,
            position.posId,
            _params,
            _prices,
            _path,
            _txType, 
            err
        );
    }

    function addOrRemoveCollateral(
        bool _isLong,
        uint256 _posId,
        bool _isPlus,
        uint256[] memory _params,
        address[] memory _path
    ) external override nonReentrant {
        bool shouldSwap;

        if (_isPlus) {
            _verifyParamsLength(ADD_COLLATERAL, _params);
            shouldSwap = _prevalidateAndCheckSwapAndAom(_path, _getLastParams(_params));
        } else {
            _verifyParamsLength(REMOVE_COLLATERAL, _params);
            shouldSwap = _prevalidateAndCheckSwap(_path, 0, false);
        }

        bytes32 key;
        bool isFastExecute; 
        uint256[] memory prices;

        //Scope to avoid stack too deep error
        {
            key = _getPositionKeyV2(msg.sender, _getFirstPath(_path), _isLong, _posId);
            (isFastExecute, prices) = _getPricesAndCheckFastExecute(_path);
        }

        vaultUtils.validateAddOrRemoveCollateral(
            key,
            _getFirstParams(_params),
            _isPlus,
            _getLastPath(_path), //collateralToken
            _getFirstParams(prices), //indexPrice
            _getLastParams(prices) //collateralPrice
        );

        _modifyPosition(
            _getPositionKeyV2(msg.sender, _getFirstPath(_path), _isLong, _posId),
            _isPlus ? ADD_COLLATERAL : REMOVE_COLLATERAL,
            _isPlus ? true : false, //isTakeAssetRequired = true for addCollateral
            _isPlus ? shouldSwap : false,
            isFastExecute,
            _path,
            prices,
            abi.encode(_params)
        );
    }

    function addPosition(
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params,
        address[] memory _path
    ) external payable override nonReentrant {
        require(msg.value == settingsManager.triggerGasFee(), "IVLTGF");
        _verifyParamsLength(ADD_POSITION, _params);
        bool shouldSwap = _prevalidateAndCheckSwapAndAom(_path, _getLastParams(_params));
        payable(settingsManager.getFeeManager()).transfer(msg.value);
        (, uint256[] memory prices) = _getPricesAndCheckFastExecute(_path);
        _modifyPosition(
            _getPositionKeyV2(msg.sender, _getFirstPath(_path), _isLong, _posId),
            ADD_POSITION,
            true, //isTakeAssetRequired = true for addPosition
            shouldSwap,
            false, //isFastExecute disabled for addPosition
            _path,
            prices,
            abi.encode(_params)
        );
    }

    function addTrailingStop(
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params
    ) external payable override nonReentrant {
        _prevalidate(_indexToken);
        _verifyParamsLength(ADD_TRAILING_STOP, _params);
        require(msg.value == settingsManager.triggerGasFee(), "IVLTGF"); //Invalid triggerFasFee
        payable(settingsManager.getFeeManager()).transfer(msg.value);

        (, address[] memory path, uint256[] memory prices) = _getSingleIndexTokenPathAndPrice(_indexToken);

       //Fast execute for adding trailing stop
        _modifyPosition(
            _getPositionKeyV2(msg.sender, _indexToken, _isLong, _posId),
            ADD_TRAILING_STOP,
            false, //isTakeAssetRequired = false for addTrailingStop
            false, //shouldSwap = false for addTrailingStop
            true, //isFastExecute = true for addTrailingStop
            path,
            prices,
            abi.encode(_params)
        );
    }

    function updateTrailingStop(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        uint256 _indexPrice
    ) external override nonReentrant {
        _prevalidate(_indexToken);
        require(_isExecutor(msg.sender) || msg.sender == _account, "IVLPO"); //Invalid positionOwner
        uint256[] memory prices = new uint256[](1);
        bool isFastExecute;

        if (!_isExecutor(msg.sender)) {
            uint256 indexPrice;
            (isFastExecute, indexPrice) = _getPriceAndCheckFastExecute(_indexToken);
            prices[0] = indexPrice;
        } else {
            prices[0] = _indexPrice;
        }
        
        _modifyPosition(
            _getPositionKeyV2(msg.sender, _indexToken, _isLong, _posId),
            UPDATE_TRAILING_STOP,
            false, //isTakeAssetRequired = false for updateTrailingStop
            false, //shouldSwap = false for updateTrailingStop
            _isExecutor(msg.sender) ? true : isFastExecute,
            _getSingleIndexTokenPath(_indexToken),
            prices,
            new bytes(0)
        );
    }

    function cancelPendingOrder(
        address _indexToken, 
        bool _isLong, 
        uint256 _posId
    ) external override nonReentrant {
        _prevalidate(_indexToken);
        (, uint256 indexPrice) = _getPriceAndCheckFastExecute(_indexToken);
        address[] memory path = new address[](1);
        path[0] = _indexToken;
        uint256[] memory prices = new uint256[](1);
        prices[0] = indexPrice;
        _modifyPosition(
            _getPositionKeyV2(msg.sender, _indexToken, _isLong, _posId),
            CANCEL_PENDING_ORDER,
            false, //isTakeAssetRequired = false for cancelPendingOrder
            false, //shouldSwap = false for cancelPendingOrder
            true, //isFastExecute = true for cancelPendingOrder
            path,
            prices,
            new bytes(0)
        );
    }

    /*
    @dev: Trigger position from triggerOrderManager
    */
    function triggerPosition(
        bytes32 _key,
        uint256 _txType,
        address[] memory _path,
        uint256[] memory _prices
    ) external override {
        require(msg.sender == address(triggerOrderManager), "FBD"); //Forbidden
        require(positionKeeper.getPositionOwner(_key) != address(0), "Position notExist");
        _modifyPosition(
            _key,
            _txType,
            false, //isTakeAssetRequired = false for triggerPosition
            false, //shouldSwap = false for triggerPosition
            true, //isFastExecute = true
            _path,
            _prices,
            abi.encode(_getParams(_key, _txType))
        );
    }

    function closePosition(
        bool _isLong,
        uint256 _posId,
        uint256[] memory _params,
        address[] memory _path
    ) external override nonReentrant {
        _prevalidateAndCheckSwap(_path, 0, false);
        _verifyParamsLength(CLOSE_POSITION, _params);
        (bool isFastExecute, uint256[] memory prices) = _getPricesAndCheckFastExecute(_path);
        _modifyPosition(
            _getPositionKeyV2(msg.sender, _path[0], _isLong, _posId),
            CLOSE_POSITION,
            false, //isTakeAssetRequired = false for closePosition
            false, //shouldSwap = false for closePosition
            isFastExecute,
            _path,
            prices,
            abi.encode(_params)
        );
    }

    function execute(bytes32 _key, uint256 _txType, uint256[] memory _prices) external {
        require(_isExecutor(msg.sender) || msg.sender == address(positionHandler), "FBD"); //Forbidden
        address[] memory path = getExecutePath(_key, _txType);
        require(path.length > 0 && path.length == _prices.length, "IVLAL"); //Invalid array length
        _execute(_key, _txType, path, _prices);
    }

    function revertExecution(
        bytes32 _key, 
        uint256 _txType,
        address[] memory _path,
        uint256[] memory _prices, 
        string memory err
    ) external override {
        require(_isExecutor(msg.sender) || msg.sender == address(positionHandler), "FBD"); //Forbidden

        if (_txType != TRIGGER_POSITION) {
            //Invalid preapre transaction status, must pending
            require(txns[_key].status == TRANSACTION_STATUS_PENDING, "IVLPTS/NPND");
        }

        require(_path.length > 0 && _prices.length == _path.length, "IVLAL"); //Invalid array length
        txns[_key].status == TRANSACTION_STATUS_EXECUTE_REVERTED;

        _revertExecute(
            _key, 
            _txType,
            _getParams(_key, _txType), 
            _prices, 
            _path,
            err
        );
    }

    function _isTakeAssetBackRequired(uint256 _txType) internal pure returns (bool) {
        return _isOpenPosition(_txType) ||
            _txType == ADD_COLLATERAL || 
            _txType == ADD_POSITION;
    }

    function _modifyPosition(
        bytes32 _key,
        uint256 _txType,
        bool _isTakeAssetRequired,
        bool _shouldSwap,
        bool _isFastExecute,
        address[] memory _path,
        uint256[] memory _prices,
        bytes memory _data
    ) internal {
        require(!settingsManager.isEmergencyStop(), "EMS"); //Emergency stopped

        if (_txType == LIQUIDATE_POSITION) {
            positionHandler.modifyPosition(
                _key,
                LIQUIDATE_POSITION,
                _path,
                _prices,
                abi.encode(positionKeeper.getPosition(_key))
            );

            return;
        } 

        Position memory position;
        OrderInfo memory order;
        uint256[] memory params;
        uint256 amountIn;

        if (_isOpenPosition(_txType) && _isOpenPositionData(_data)) {
            (position, order) = abi.decode(_data, ((Position), (OrderInfo)));
            params = txnDetails[_key][_txType].params;
            amountIn = order.pendingCollateral;
        } else {
            params = _data.length == 0 ? new uint256[](0) : abi.decode(_data, (uint256[]));
            (position, order) = positionKeeper.getPositions(_key);
            amountIn = params.length == 0 ? 0 
                : (_isOpenPosition(_txType) && params.length > 5 ? params[4] : _getFirstParams(params));
        }

        //Transfer collateral to vault if required
        if (_isTakeAssetRequired) {
            require(amountIn > 0 && _path.length > 1, "IVLCA/P"); //Invalid collateral amount/path
            _transferAssetToVault(
                position.owner,
                _path[1],
                amountIn,
                _key,
                _txType
            );
        }

        if (_shouldSwap && _isFastExecute) {
            bool isSwapSuccess;
            address collateralToken;
            
            {
                (isSwapSuccess, collateralToken, amountIn) = _processSwap(
                    _key,
                    position.owner,
                    _txType,
                    amountIn,
                    _path,
                    _prices,
                    params.length > 0 ? _getLastParams(params) : 0
                );

                if (!isSwapSuccess) {
                    _revertExecute(
                        _key,
                        _txType,
                        params,
                        _prices,
                        _path,
                        "SWF" //Swap failed
                    );
                    
                    return;
                }
            }

            if (_isOpenPosition(_txType) && _isOpenPositionData(_data)) {
                order.collateralToken = collateralToken;
                uint256 leverage = order.pendingSize * BASIS_POINTS_DIVISOR / order.pendingCollateral;
                order.pendingCollateral = amountIn;
                order.pendingSize = amountIn * leverage / BASIS_POINTS_DIVISOR;
            }
        }

        if (!_isFastExecute) {
            _createPrepareTransaction(
                position.owner,
                position.isLong,
                position.posId,
                _txType,
                params,
                _path,
                _isFastExecute
            );
        }

        if (!_isFastExecute && !_isOpenPosition(_txType)) {
            return;
        }

        if (_txType == ADD_POSITION || 
            _txType == ADD_COLLATERAL ||
            _txType == REMOVE_COLLATERAL ||
            _txType == ADD_TRAILING_STOP ||
            _txType == UPDATE_TRAILING_STOP || 
            _txType == CLOSE_POSITION) {
            require(position.owner != address(0) && position.size > 0, "IVLPS/NI"); //Invalid position, not initialized
        }

        bytes memory data;

        if (_isOpenPosition(_txType) && (_isOpenPositionData(_data) || _txType == CREATE_POSITION_MARKET)) {
            data = abi.encode(_isFastExecute, _isOpenPositionData(_data), params, position, order);
        } else if (_txType == ADD_COLLATERAL || _txType == REMOVE_COLLATERAL) {
            data = abi.encode(amountIn, position);
        } else if (_txType == ADD_TRAILING_STOP) {
            data = abi.encode(position.owner, position.isLong, params, order);
        } else if (_txType == UPDATE_TRAILING_STOP) {
            data = abi.encode(position.owner, position.isLong, order);
        }  else if (_txType == CANCEL_PENDING_ORDER) {
            data = abi.encode(position.owner, order);
        } else if (_txType == CLOSE_POSITION) {
            data = abi.encode(_getFirstParams(params), position);
        } else if (_txType == ADD_POSITION) {
            uint256 leverage = positionKeeper.leverages(_key);
            require(amountIn > 0 && leverage > 0, "IVLCA/L"); //Invalid collateralAmount/Leverage
            data = abi.encode(
                amountIn, 
                amountIn * leverage / BASIS_POINTS_DIVISOR, 
                position
            );
        } else if (_txType == TRIGGER_POSITION || _isDelayPosition(_txType)) {
            data = abi.encode(position, order);
        } else {
            revert("IVLETXT"); //Invalid execute txType
        }

        positionHandler.modifyPosition(
            _key,
            _isDelayPosition(_txType) && !_isOpenPositionData(_data) ? TRIGGER_POSITION : _txType,
            _path,
            _prices,
            data
        );

        if (_isFastExecute) {
            _clearPrepareTransaction(_key, _txType);
        }
    }

    function clearPrepareTransaction(bytes32 _key, uint256 _txType) external {
        require(msg.sender == address(positionHandler), "FBD");
        _clearPrepareTransaction(_key, _txType);
    }

    function _clearPrepareTransaction(bytes32 _key, uint256 _txType) internal {
        if (txns[_key].txType == _txType) {
            delete txns[_key];
            delete txnDetails[_key][_txType];
        }
    }

    function _createPrepareTransaction(
        address _account,
        bool _isLong,
        uint256 _posId,
        uint256 _txType,
        uint256[] memory _params,
        address[] memory _path,
        bool isFastExecute
    ) internal {
        bytes32 key = _getPositionKeyAndCheck(_account, _getFirstPath(_path), _isLong, _posId, false);
        PrepareTransaction storage transaction = txns[key];
        require(transaction.status != TRANSACTION_STATUS_PENDING, "IVLPTS/IP"); //Invalid prepare transaction status, in processing
        transaction.txType = _txType;
        transaction.startTime = block.timestamp;
        transaction.status = TRANSACTION_STATUS_PENDING;
        txnDetails[key][_txType].path = _path;
        txnDetails[key][_txType].params = _params;
        (, uint256 amountOutMin) = _extractDeadlineAndAmountOutMin(_txType, _params, true);
        
        if (_isSwapRequired(_path) && _isRequiredAmountOutMin(_txType)) {
            require(amountOutMin > 0, "IVLAOM");
        }

        emit CreatePrepareTransaction(
            _account,
            _isLong,
            _posId,
            _txType,
            _params,
            _path,
            key,
            isFastExecute
        );
    }

    function _extractDeadlineAndAmountOutMin(uint256 _txType, uint256[] memory _params, bool _isRaise) internal view returns(uint256, uint256) {
        uint256 deadline;
        uint256 amountOutMin;

        if (_isOpenPosition(_txType)) {
            deadline = _txType == CREATE_POSITION_MARKET ? _params[6] : 0;

            if (_txType == CREATE_POSITION_MARKET && _isRaise) {
                require(deadline > 0 && deadline > block.timestamp, "IVLDL"); //Invalid deadline
            }

            amountOutMin = _params[7];
        } else if (_txType == REMOVE_COLLATERAL) {
            deadline = _params[1];

            if (_isRaise) {
                require(deadline > 0 && deadline > block.timestamp, "IVLDL"); //Invalid deadline
            }
        } else if (_txType == ADD_COLLATERAL) {
            deadline = _params[1];

            if (_isRaise) {
                require(deadline > 0 && deadline > block.timestamp, "IVLDL"); //Invalid deadline
            }

            amountOutMin = _params[2];
        } else if (_txType == ADD_POSITION) {
            deadline = _params[2];

            if (_isRaise) {
                require(deadline > 0 && deadline > block.timestamp, "IVLDL"); //Invalid deadline
            }

            amountOutMin = _params[3];
        }

        return (deadline, amountOutMin);
    }

    function _verifyParamsLength(uint256 _type, uint256[] memory _params) internal pure {
        bool isValid;

        if (_type == CREATE_POSITION_MARKET
            || _type == CREATE_POSITION_LIMIT
            || _type == CREATE_POSITION_STOP_MARKET
            || _type == CREATE_POSITION_STOP_LIMIT) {
            isValid = _params.length == 8;
        } else if (_type == ADD_COLLATERAL) {
            isValid = _params.length == 3;
        } else if (_type == REMOVE_COLLATERAL) {
            isValid = _params.length == 2;
        } else if (_type == ADD_POSITION) {
            isValid = _params.length == 4;
        } else if (_type == CLOSE_POSITION) {
            isValid = _params.length == 2;
        } else if (_type == ADD_TRAILING_STOP) {
            isValid = _params.length == 5;
        }

        require(isValid, "IVLPL"); //Invalid params length
    }

    function _execute(
        bytes32 _key, 
        uint256 _txType,
        address[] memory _path,
        uint256[] memory _prices
    ) internal {
        require(_path.length > 0 && _path.length == _prices.length, "IVLAL"); //Invalid array length
        require(positionKeeper.getPositionOwner(_key) != address(0), "Position notExist"); //Not exist
        
        if (_txType == LIQUIDATE_POSITION) {
            _modifyPosition(
                _key,
                LIQUIDATE_POSITION,
                false, //isTakeAssetRequired = false for executing,
                false, //shouldSwap = false for executing
                true, //isFastExecute = true for executing
                _path,
                _prices,
                new bytes(0)
            );
            txns[_key].status = TRANSACTION_STATUS_EXECUTED;
            return;
        }

        //Check deadline
        (uint256 deadline, ) = _extractDeadlineAndAmountOutMin(_txType, _getParams(_key, _txType), false);

        if (deadline > 0 && deadline <= block.timestamp) {
            _revertExecute(
                _key,
                _txType,
                _getParams(_key, _txType),
                _prices,
                _path,
                "DLR" //Deadline reached
            );
            return;
        }
        
        PrepareTransaction storage txn = txns[_key];

        if (!_isTriggerType(_txType)) {
            require(_txType == txn.txType, "IVLPT/ICRT"); //Invalid prepare transaction, not correct txType
            require(txn.status == TRANSACTION_STATUS_PENDING, "IVLPTS/NP"); //Invalid prepare transaction status, not pending
        }

        txn.status = TRANSACTION_STATUS_EXECUTED;
        _modifyPosition(
            _key,
            _txType,
            false, //isTakeAssetRequired = false for executing
            false, //shouldSwap = false for executing
            true, //isFastExecute = true for executing
            _path,
            _prices,
            abi.encode(_getParams(_key, _txType))
        );
    }

    function _isTriggerType(uint256 _txType) internal pure returns (bool) {
        return _isDelayPosition(_txType) || _txType == ADD_TRAILING_STOP || _txType == TRIGGER_POSITION;
    }

    /*
    @dev: Pre-validate check path and amountOutMin (if swap required)
    */
    function _prevalidateAndCheckSwapAndAom(
        address[] memory _path, 
        uint256 _amountOutMin
    ) internal view returns (bool) {
        return _prevalidateAndCheckSwap(_path, _amountOutMin, true);
    }

    function _prevalidateAndCheckSwap(
        address[] memory _path, 
        uint256 _amountOutMin,
        bool _isVerifyAmountOutMin
    ) internal view returns (bool) {
        require(_path.length >= 2, "IVLPTL"); //Invalid path length
        _prevalidate(_getFirstPath(_path));
        bool shouldSwap = settingsManager.validateCollateralPathAndCheckSwap(_path);

        if (shouldSwap && _path.length > 2 && _isVerifyAmountOutMin) {
            //Invalid amountOutMin/swapRouter
            require(_amountOutMin > 0 && address(swapRouter) != address(0), "IVLAOM/SR"); 
        }

        return shouldSwap;
    }

    function _getFirstPath(address[] memory _path) internal pure returns (address) {
        return _path[0];
    }

    function _getLastPath(address[] memory _path) internal pure returns (address) {
        return _path[_path.length - 1];
    }

    function _getFirstParams(uint256[] memory _params) internal pure returns (uint256) {
        return _params[0];
    }

    function _getLastParams(uint256[] memory _params) internal pure returns (uint256) {
        return _params[_params.length - 1];
    }

    function _transferAssetToVault(
        address _account, 
        address _token,
        uint256 _amountIn,
        bytes32 _key,
        uint256 _txType
    ) internal {
        require(_amountIn > 0, "IVLAM"); //Invalid amount
        vault.takeAssetIn(_account, _amountIn, _token, _key, _txType);
    }

    function _isSwapRequired(address[] memory _path) internal pure returns (bool) {
        return _path.length > 2;
    }

    function _processSwap(
        bytes32 _key,
        address _account,
        uint256 _txType,
        uint256 _pendingCollateral,
        address[] memory _path,
        uint256[] memory _prices,
        uint256 _amountOutMin 
    ) internal returns (bool, address, uint256) {
        uint256 tokenOutPrice = _prices.length == 0 ? 0 : _getLastParams(_prices);
        require(tokenOutPrice > 0, "IVLTP"); //Invalid token price

        try swapRouter.swapFromInternal(
            _account,
            _key,
            _txType,
            _pendingCollateral,
            _amountOutMin,
            _path
        ) returns (address tokenOut, uint256 swapAmountOut) {
            uint256 swapAmountOutInUSD = priceManager.fromTokenToUSD(tokenOut, swapAmountOut, tokenOutPrice);
            require(swapAmountOutInUSD > 0, "IVLSAP"); //Invalid swap amount price
            return (true, tokenOut, swapAmountOutInUSD);
        } catch {
            return (false, _path[1], _pendingCollateral);
        }
    }

    function _takeAssetBack(bytes32 _key, uint256 _txType) internal {
        vault.takeAssetBack(
            positionKeeper.getPositionOwner(_key), 
            _key,
            _txType
        );
    }
    
    //
    function getTransaction(bytes32 _key) external view returns (PrepareTransaction memory) {
        return txns[_key];
    }

    function getTxDetail(bytes32 _key, uint256 _txType) external view returns (TxDetail memory) {
        return txnDetails[_key][_txType];
    }

    function getPath(bytes32 _key, uint256 _txType) external view returns (address[] memory) {
        return _getPath(_key, _txType);
    }

    function getParams(bytes32 _key, uint256 _txType) external view returns (uint256[] memory) {
        return _getParams(_key, _txType);
    }
    
    function _getPath(bytes32 _key, uint256 _txType) internal view returns (address[] memory) {
        return txnDetails[_key][_txType].path;
    }

    function getExecutePath(bytes32 _key, uint256 _txType) public view returns (address[] memory) {
        if (_isNotRequirePreparePath(_txType)) {
            return positionKeeper.getPositionFinalPath(_key);
        } else {
            return _getPath(_key, _txType);
        }
    }

    function _isNotRequirePreparePath(uint256 _txType) internal pure returns (bool) {
        return _txType == TRIGGER_POSITION 
            || _txType == REMOVE_COLLATERAL 
            || _txType == LIQUIDATE_POSITION;
    }

    function _getParams(bytes32 _key, uint256 _txType) internal view returns (uint256[] memory) {
        return txnDetails[_key][_txType].params; 
    }

    function _getTransactionTypeFromOrder(OrderType _orderType) internal pure returns (uint256) {
        if (_orderType == OrderType.MARKET) {
            return CREATE_POSITION_MARKET;
        } else if (_orderType == OrderType.LIMIT) {
            return CREATE_POSITION_LIMIT;
        } else if (_orderType == OrderType.STOP) {
            return CREATE_POSITION_STOP_MARKET;
        } else if (_orderType == OrderType.STOP_LIMIT) {
            return CREATE_POSITION_STOP_LIMIT;
        } else {
            revert("IVLOT"); //Invalid order type
        }
    }

    function _isRequiredAmountOutMin(uint256 _txType) internal pure returns (bool) {
        return _isOpenPosition(_txType) || 
            _txType == ADD_COLLATERAL ||
            _txType == ADD_POSITION;
    }

    function _getSingleIndexTokenPath(address _indexToken) internal pure returns (address[] memory) {
        address[] memory path = new address[](1);
        path[0] = _indexToken;
        return path;
    }

    function _getSingleIndexTokenPathAndPrice(address _indexToken) internal view returns (bool, address[] memory, uint256[] memory) {
        address[] memory path = new address[](1);
        uint256[] memory prices = new uint256[](1);
        path[0] = _indexToken;
        (bool isFastExecute, uint256 price) = _getPriceAndCheckFastExecute(_indexToken);
        prices[0] = price;
        return (isFastExecute, path, prices);
    }

    function _getPositionKeyV2(
        address _account, 
        address _indexToken,
        bool _isLong,
        uint256 _posId
    ) internal view returns (bytes32) {
        return _getPositionKeyAndCheck(
            _account,
            _indexToken,
            _isLong,
            _posId,
            true
        );
    }

    function _getPositionKeyAndCheck(
        address _account, 
        address _indexToken,
        bool _isLong,
        uint256 _posId,
        bool _raise
    ) internal view returns (bytes32) {
        bytes32 key = _getPositionKey(_account, _indexToken, _isLong, _posId);

        if (_raise) {
            require(_account == positionKeeper.getPositionOwner(key), "FBD: Invalid pOwner");
        }

        return key;
    }

    /*
    @dev: Min encode data length for position 13 struct and order 9 struct are 22 * 32 = 704
    */
    function _isOpenPositionData(bytes memory _data) internal pure returns (bool) {
        return _data.length == 704;     
    }
}
