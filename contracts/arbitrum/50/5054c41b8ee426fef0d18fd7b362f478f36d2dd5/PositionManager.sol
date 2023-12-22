// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./IRouter.sol";
import "./IVault.sol";
import "./IOrderBook.sol";

import "./ITimelock.sol";
import "./BasePositionManager.sol";

contract PositionManager is BasePositionManager {
    address public orderBook;
    bool public inLegacyMode;

    bool public shouldValidateIncreaseOrder = true;

    mapping(address => bool) public isOrderKeeper;
    mapping(address => bool) public isPartner;
    mapping(address => bool) public isLiquidator;

    event SetOrderKeeper(address indexed account, bool isActive);
    event SetLiquidator(address indexed account, bool isActive);
    event SetOrderBook(address orderBook);
    event SetPartner(address account, bool isActive);
    event SetInLegacyMode(bool inLegacyMode);
    event SetShouldValidateIncreaseOrder(bool shouldValidateIncreaseOrder);
    event LiquidationError(address account, address indexToken, string reason);
    event ExecuteSwapOrderError(address indexed account, uint256 orderIndex, string reason);
    event ExecuteIncreaseOrderError(address indexed account, uint256 orderIndex, string reason);
    event ExecuteDecreaseOrderError(address indexed account, uint256 orderIndex, string reason);

    modifier onlyOrderKeeper() {
        require(isOrderKeeper[msg.sender] || msg.sender == address(this), "PositionManager: forbidden");
        _;
    }

    modifier onlyLiquidator() {
        require(isLiquidator[msg.sender] || msg.sender == address(this), "PositionManager: forbidden");
        _;
    }

    modifier onlyPartnersOrLegacyMode() {
        require(isPartner[msg.sender] || inLegacyMode, "PositionManager: forbidden");
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _weth,
        uint256 _depositFee,
        address _orderBook
    ) public BasePositionManager(_vault, _router, _weth, _depositFee) {
        orderBook = _orderBook;
    }

    function setOrderKeeper(address _account, bool _isActive) external onlyAdmin {
        isOrderKeeper[_account] = _isActive;
        emit SetOrderKeeper(_account, _isActive);
    }

    function setOrderBook(address _orderBook) external onlyAdmin {
        orderBook = _orderBook;
        emit SetOrderBook(_orderBook);
    }

    function setLiquidator(address _account, bool _isActive) external onlyAdmin {
        isLiquidator[_account] = _isActive;
        emit SetLiquidator(_account, _isActive);
    }

    function setPartner(address _account, bool _isActive) external onlyAdmin {
        isPartner[_account] = _isActive;
        emit SetPartner(_account, _isActive);
    }

    function setInLegacyMode(bool _inLegacyMode) external onlyAdmin {
        inLegacyMode = _inLegacyMode;
        emit SetInLegacyMode(_inLegacyMode);
    }

    function setShouldValidateIncreaseOrder(bool _shouldValidateIncreaseOrder) external onlyAdmin {
        shouldValidateIncreaseOrder = _shouldValidateIncreaseOrder;
        emit SetShouldValidateIncreaseOrder(_shouldValidateIncreaseOrder);
    }

    function increasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        require(_path.length == 1 || _path.length == 2, "PositionManager: invalid _path.length");

        if (_amountIn > 0) {
            if (_path.length == 1) {
                IRouter(router).pluginTransfer(_path[0], msg.sender, address(this), _amountIn);
            } else {
                IRouter(router).pluginTransfer(_path[0], msg.sender, vault, _amountIn);
                _amountIn = _swap(_path, _minOut, address(this));
            }

            uint256 afterFeeAmount = _collectFees(msg.sender, _path, _amountIn, _indexToken, _isLong, _sizeDelta);
            IERC20(_path[_path.length - 1]).safeTransfer(vault, afterFeeAmount);
        }

        _increasePosition(msg.sender, _path[_path.length - 1], _indexToken, _sizeDelta, _isLong, _price);
    }

    function increasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price
    ) external payable nonReentrant onlyPartnersOrLegacyMode {
        require(_path.length == 1 || _path.length == 2, "PositionManager: invalid _path.length");
        require(_path[0] == weth, "PositionManager: invalid _path");

        if (msg.value > 0) {
            _transferInETH();
            uint256 _amountIn = msg.value;

            if (_path.length > 1) {
                IERC20(weth).safeTransfer(vault, msg.value);
                _amountIn = _swap(_path, _minOut, address(this));
            }

            uint256 afterFeeAmount = _collectFees(msg.sender, _path, _amountIn, _indexToken, _isLong, _sizeDelta);
            IERC20(_path[_path.length - 1]).safeTransfer(vault, afterFeeAmount);
        }

        _increasePosition(msg.sender, _path[_path.length - 1], _indexToken, _sizeDelta, _isLong, _price);
    }

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        _decreasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _price
        );
    }

    function decreasePositionETH(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price
    ) external nonReentrant onlyPartnersOrLegacyMode {
        require(_collateralToken == weth, "PositionManager: invalid _collateralToken");

        uint256 amountOut = _decreasePosition(
            msg.sender,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(this),
            _price
        );
        _transferOutETH(amountOut, _receiver);
    }

    function decreasePositionAndSwap(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price,
        uint256 _minOut
    ) external nonReentrant onlyPartnersOrLegacyMode {
        require(_path.length == 2, "PositionManager: invalid _path.length");

        uint256 amount = _decreasePosition(
            msg.sender,
            _path[0],
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(this),
            _price
        );
        IERC20(_path[0]).safeTransfer(vault, amount);
        _swap(_path, _minOut, _receiver);
    }

    function decreasePositionAndSwapETH(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price,
        uint256 _minOut
    ) external nonReentrant onlyPartnersOrLegacyMode {
        require(_path.length == 2, "PositionManager: invalid _path.length");
        require(_path[_path.length - 1] == weth, "PositionManager: invalid _path");

        uint256 amount = _decreasePosition(
            msg.sender,
            _path[0],
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            address(this),
            _price
        );
        IERC20(_path[0]).safeTransfer(vault, amount);
        uint256 amountOut = _swap(_path, _minOut, address(this));
        _transferOutETH(amountOut, _receiver);
    }

    function liquidatePosition(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        address _feeReceiver
    ) external nonReentrant onlyLiquidator {
        address _vault = vault;
        address timelock = IVault(_vault).gov();

        ITimelock(timelock).enableLeverage(_vault);
        IVault(_vault).liquidatePosition(_account, _collateralToken, _indexToken, _isLong, _feeReceiver);
        ITimelock(timelock).disableLeverage(_vault);
    }

    function liquidatePositions(
        address[] calldata _accounts,
        address[] calldata _collateralTokens,
        address[] calldata _indexTokens,
        bool[] calldata isLongs,
        address _feeReceiver
    ) external onlyLiquidator {
        require(
            _accounts.length == _collateralTokens.length &&
                _accounts.length == _indexTokens.length &&
                _accounts.length == isLongs.length,
            "PositionRouter: liquidatePositions arrays must have the same length"
        );
        for (uint256 i = 0; i < _accounts.length; i++) {
            try this.liquidatePosition(_accounts[i], _collateralTokens[i], _indexTokens[i], isLongs[i], _feeReceiver) {
                // try-catch to prevent reverts from stopping the loop
            } catch Error(string memory reason) {
                emit LiquidationError(_accounts[i], _indexTokens[i], reason);
            } catch {
                emit LiquidationError(_accounts[i], _indexTokens[i], "");
            }
        }
    }

    function executeSwapOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        IOrderBook(orderBook).executeSwapOrder(_account, _orderIndex, _feeReceiver);
    }

    function executeSwapOrders(
        address[] calldata _accounts,
        uint256[] calldata _orderIndexes,
        address payable _feeReceiver
    ) public onlyOrderKeeper {
        require(
            _accounts.length == _orderIndexes.length,
            "PositionRouter: executeSwapOrders arrays must have the same length"
        );
        for (uint256 i = 0; i < _accounts.length; i++) {
            try this.executeSwapOrder(_accounts[i], _orderIndexes[i], _feeReceiver) {
                // try-catch to prevent revert a revert from blocking the loop
            } catch Error(string memory reason) {
                emit ExecuteSwapOrderError(_accounts[i], _orderIndexes[i], reason);
            } catch {
                emit ExecuteSwapOrderError(_accounts[i], _orderIndexes[i], "");
            }
        }
    }

    function executeIncreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        uint256 sizeDelta = _validateIncreaseOrder(_account, _orderIndex);

        address _vault = vault;
        address timelock = IVault(_vault).gov();

        ITimelock(timelock).enableLeverage(_vault);
        IOrderBook(orderBook).executeIncreaseOrder(_account, _orderIndex, _feeReceiver);
        ITimelock(timelock).disableLeverage(_vault);

        _emitIncreasePositionReferral(_account, sizeDelta);
    }

    function executeIncreaseOrders(
        address[] calldata _accounts,
        uint256[] calldata _orderIndexes,
        address payable _feeReceiver
    ) public onlyOrderKeeper {
        require(
            _accounts.length == _orderIndexes.length,
            "PositionRouter: executeIncreaseOrders arrays must have the same length"
        );
        for (uint256 i = 0; i < _accounts.length; i++) {
            try this.executeIncreaseOrder(_accounts[i], _orderIndexes[i], _feeReceiver) {
                // try-catch to prevent revert a revert from blocking the loop
            } catch Error(string memory reason) {
                emit ExecuteIncreaseOrderError(_accounts[i], _orderIndexes[i], reason);
            } catch {
                emit ExecuteIncreaseOrderError(_accounts[i], _orderIndexes[i], "Unknown error");
            }
        }
    }

    function executeDecreaseOrder(
        address _account,
        uint256 _orderIndex,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        address _vault = vault;
        address timelock = IVault(_vault).gov();

        (
            ,
            ,
            ,
            // _collateralToken
            // _collateralDelta
            // _indexToken
            uint256 _sizeDelta, // _isLong // triggerPrice // triggerAboveThreshold // executionFee
            ,
            ,
            ,

        ) = IOrderBook(orderBook).getDecreaseOrder(_account, _orderIndex);

        ITimelock(timelock).enableLeverage(_vault);
        IOrderBook(orderBook).executeDecreaseOrder(_account, _orderIndex, _feeReceiver);
        ITimelock(timelock).disableLeverage(_vault);

        _emitDecreasePositionReferral(_account, _sizeDelta);
    }

    function executeDecreaseOrders(
        address[] calldata _accounts,
        uint256[] calldata _orderIndexes,
        address payable _feeReceiver
    ) public onlyOrderKeeper {
        require(
            _accounts.length == _orderIndexes.length,
            "PositionRouter: executeDecreaseOrders arrays must have the same length"
        );
        for (uint256 i = 0; i < _accounts.length; i++) {
            try this.executeDecreaseOrder(_accounts[i], _orderIndexes[i], _feeReceiver) {
                // try-catch to prevent revert a revert from blocking the loop
            } catch Error(string memory reason) {
                emit ExecuteDecreaseOrderError(_accounts[i], _orderIndexes[i], reason);
            } catch {
                emit ExecuteDecreaseOrderError(_accounts[i], _orderIndexes[i], "Unknown error");
            }
        }
    }

    function executeMany(
        address[] calldata _increaseOrderAccounts,
        uint256[] calldata _increaseOrderIndexes,
        address[] calldata _decreaseOrderAccounts,
        uint256[] calldata _decreaseOrderIndexes,
        address[] calldata _swapOrderAccounts,
        uint256[] calldata _swapOrderIndexes,
        address payable _feeReceiver
    ) external onlyOrderKeeper {
        executeIncreaseOrders(_increaseOrderAccounts, _increaseOrderIndexes, _feeReceiver);
        executeDecreaseOrders(_decreaseOrderAccounts, _decreaseOrderIndexes, _feeReceiver);
        executeSwapOrders(_swapOrderAccounts, _swapOrderIndexes, _feeReceiver);
    }

    function _validateIncreaseOrder(address _account, uint256 _orderIndex) internal view returns (uint256) {
        (
            address _purchaseToken,
            uint256 _purchaseTokenAmount,
            address _collateralToken,
            address _indexToken,
            uint256 _sizeDelta,
            bool _isLong, // triggerPrice // triggerAboveThreshold // executionFee
            ,
            ,

        ) = IOrderBook(orderBook).getIncreaseOrder(_account, _orderIndex);

        if (!shouldValidateIncreaseOrder) {
            return _sizeDelta;
        }

        // shorts are okay
        if (!_isLong) {
            return _sizeDelta;
        }

        // if the position size is not increasing, this is a collateral deposit
        require(_sizeDelta > 0, "PositionManager: long deposit");

        IVault _vault = IVault(vault);
        (uint256 size, uint256 collateral, , , , , , ) = _vault.getPosition(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        );

        // if there is no existing position, do not charge a fee
        if (size == 0) {
            return _sizeDelta;
        }

        uint256 nextSize = size.add(_sizeDelta);
        uint256 collateralDelta = _vault.tokenToUsdMin(_purchaseToken, _purchaseTokenAmount);
        uint256 nextCollateral = collateral.add(collateralDelta);

        uint256 prevLeverage = size.mul(BASIS_POINTS_DIVISOR).div(collateral);
        // allow for a maximum of a increasePositionBufferBps decrease since there might be some swap fees taken from the collateral
        uint256 nextLeverageWithBuffer = nextSize.mul(BASIS_POINTS_DIVISOR + increasePositionBufferBps).div(
            nextCollateral
        );

        require(nextLeverageWithBuffer >= prevLeverage, "PositionManager: long leverage decrease");

        return _sizeDelta;
    }
}

