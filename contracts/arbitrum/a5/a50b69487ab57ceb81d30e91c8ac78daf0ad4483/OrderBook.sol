// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./IVaultPriceFeed.sol";
import "./IPythPriceFeed.sol";
import "./IOrderBook.sol";
import "./IRouter.sol";
import "./IDipxStorage.sol";
import "./TransferHelper.sol";
import "./EnumerableSet.sol";

contract OrderBook is IOrderBook,Initializable,OwnableUpgradeable,ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 public constant PRICE_PRECISION = 1e10;

    mapping (address => mapping(uint256 => Order)) public increaseOrders;
    mapping (address => uint256) public increaseOrdersIndex;

    mapping (address => mapping(uint256 => Order)) public decreaseOrders;
    mapping (address => uint256) public decreaseOrdersIndex;
    
    address public dipxStorage;
    uint256 public minExecutionFee;

    mapping (address => EnumerableSet.UintSet) private accountIncreaseOrdersIndex;
    mapping (address => EnumerableSet.UintSet) private accountDecreaseOrdersIndex;

    event CreateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        uint256 executionFee,
        bool triggerAboveThreshold
    );
    event CancelIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        uint256 executionFee,
        bool triggerAboveThreshold
    );
    event ExecuteIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        uint256 executionFee,
        uint256 executionPrice,
        bool triggerAboveThreshold,
        uint256 liqFee
    );
    event UpdateIncreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 sizeDelta,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );
    event CreateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        uint256 executionFee,
        bool triggerAboveThreshold
    );
    event CancelDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        uint256 executionFee,
        bool triggerAboveThreshold
    );
    event ExecuteDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        uint256 executionFee,
        uint256 executionPrice,
        bool triggerAboveThreshold,
        uint256 liqFee
    );
    event UpdateDecreaseOrder(
        address indexed account,
        uint256 orderIndex,
        address collateralToken,
        uint256 collateralDelta,
        address indexToken,
        uint256 sizeDelta,
        bool isLong,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );

    event UpdateMinExecutionFee(uint256 minExecutionFee);

    function initialize(address _dipxStorage,uint256 _minExecutionFee) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        dipxStorage = _dipxStorage;
        minExecutionFee = _minExecutionFee;
    }

    receive() external payable {
    }

    function setDipxStorage(address _dipxStorage) external override onlyOwner {
        dipxStorage = _dipxStorage;
    }
    function priceFeed() public view returns(address){
        return IDipxStorage(dipxStorage).priceFeed();
    }
    function router() public view returns(address){
        return IDipxStorage(dipxStorage).router();
    }

    function setMinExecutionFee(uint256 _minExecutionFee) external onlyOwner {
        minExecutionFee = _minExecutionFee;

        emit UpdateMinExecutionFee(_minExecutionFee);
    }

    function cancelMultiple(
        uint256[] memory _increaseOrderIndexes,
        uint256[] memory _decreaseOrderIndexes
    ) external {
        for (uint256 i = 0; i < _increaseOrderIndexes.length; i++) {
            cancelIncreaseOrder(_increaseOrderIndexes[i]);
        }
        for (uint256 i = 0; i < _decreaseOrderIndexes.length; i++) {
            cancelDecreaseOrder(_decreaseOrderIndexes[i]);
        }
    }

    function validatePositionOrderPrice(
        bool _triggerAboveThreshold,
        uint256 _triggerPrice,
        address _indexToken,
        bool _maximizePrice,
        bool _raise
    ) public view returns (uint256, bool) {
        uint256 currentPrice = IVaultPriceFeed(priceFeed()).getPrice(_indexToken,_maximizePrice);
        bool isPriceValid = _triggerAboveThreshold ? currentPrice > _triggerPrice : currentPrice < _triggerPrice;
        if (_raise) {
            require(isPriceValid, "OrderBook: invalid price for execution");
        }
        return (currentPrice, isPriceValid);
    }
    
    function getIncreaseOrdersLength(address _account) public view returns (uint256) {
        return accountIncreaseOrdersIndex[_account].length();
    }
    function getIncreaseOrderIndexAt(address _account,uint256 _at) public view returns (uint256) {
        return accountIncreaseOrdersIndex[_account].at(_at);
    }

    function getDecreaseOrdersLength(address _account) public view returns (uint256) {
        return accountDecreaseOrdersIndex[_account].length();
    }
    function getDecreaseOrderIndexAt(address _account, uint256 _at) public view returns (uint256) {
        return accountDecreaseOrdersIndex[_account].at(_at);
    }

    function getIncreaseOrders(address _account) public view returns (Order[] memory) {
        uint256 len = accountIncreaseOrdersIndex[_account].length();

        Order[] memory orders = new Order[](len);
        for (uint256 i = 0; i < len; i++) {
            uint256 orderIndex = accountIncreaseOrdersIndex[_account].at(i);
            orders[i] = increaseOrders[_account][orderIndex];
        }
        return orders;
    }
    function getDecreaseOrders(address _account) public view returns (Order[] memory) {
        uint256 len = accountDecreaseOrdersIndex[_account].length();

        Order[] memory orders = new Order[](len);
        for (uint256 i = 0; i < len; i++) {
            uint256 orderIndex = accountDecreaseOrdersIndex[_account].at(i);
            orders[i] = decreaseOrders[_account][orderIndex];
        }
        return orders;
    }

    function getDecreaseOrder(address _account, uint256 _orderIndex) override public view returns (Order memory) {
        return decreaseOrders[_account][_orderIndex];
    }

    function getIncreaseOrder(address _account, uint256 _orderIndex) override public view returns (Order memory) {
        return increaseOrders[_account][_orderIndex];
    }

    function _addAccountOrder(address _account, uint256 _orderIndex, bool _isIncrease) private{
        if(_isIncrease){
            EnumerableSet.UintSet storage accountOrders = accountIncreaseOrdersIndex[_account];
            accountOrders.add(_orderIndex);
        }else{
            EnumerableSet.UintSet storage accountOrders = accountDecreaseOrdersIndex[_account];
            accountOrders.add(_orderIndex);
        }
    }
    function _removeAccountOrder(address _account, uint256 _orderIndex, bool _isIncrease) private{
        if(_isIncrease){
            EnumerableSet.UintSet storage accountOrders = accountIncreaseOrdersIndex[_account];
            accountOrders.remove(_orderIndex);
        }else{
            EnumerableSet.UintSet storage accountOrders = accountDecreaseOrdersIndex[_account];
            accountOrders.remove(_orderIndex);
        }
    }

    function createIncreaseOrder(
        uint256 _amountIn,
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        bool _isLong,
        uint256 _triggerPrice,
        uint256 _executionFee,
        bool _triggerAboveThreshold
    ) external payable nonReentrant {
        uint256 liqFee = IRouter(router()).getPoolLiqFee(_collateralToken);
        require(_executionFee >= minExecutionFee+liqFee, "OrderBook: insufficient execution fee");
        require(msg.value >= _executionFee, "OrderBook: incorrect execution fee transferred");
        TransferHelper.safeTransferFrom(_collateralToken,msg.sender,address(this),_amountIn);

        _createIncreaseOrder(
            msg.sender,
            _collateralToken,
            _indexToken,
            _amountIn,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            msg.value,
            _triggerAboveThreshold
        );
    }

    function _createIncreaseOrder(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _triggerPrice,
        uint256 _executionFee,
        bool _triggerAboveThreshold
    ) private {
        uint256 _orderIndex = increaseOrdersIndex[msg.sender];
        Order memory order = Order(
            _orderIndex,
            true,
            _account,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _executionFee,
            _triggerAboveThreshold
        );
        increaseOrdersIndex[_account] = _orderIndex + 1;
        increaseOrders[_account][_orderIndex] = order;
        _addAccountOrder(_account,_orderIndex,true);

        emit CreateIncreaseOrder(
            _account,
            _orderIndex,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _executionFee,
            _triggerAboveThreshold
        );
    }

    function updateIncreaseOrder(uint256 _orderIndex, uint256 _sizeDelta, uint256 _triggerPrice,bool _triggerAboveThreshold) external nonReentrant {
        Order storage order = increaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        order.triggerPrice = _triggerPrice;
        order.sizeDelta = _sizeDelta;
        order.triggerAboveThreshold = _triggerAboveThreshold;

        emit UpdateIncreaseOrder(
            msg.sender,
            _orderIndex,
            order.collateralToken,
            order.indexToken,
            order.isLong,
            _sizeDelta,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function cancelIncreaseOrder(uint256 _orderIndex) public nonReentrant {
        Order memory order = increaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        delete increaseOrders[msg.sender][_orderIndex];
        _removeAccountOrder(msg.sender,_orderIndex,true);

        TransferHelper.safeTransfer(order.collateralToken,msg.sender,order.collateralDelta);
        _transferOutETH(order.executionFee, msg.sender);

        emit CancelIncreaseOrder(
            order.account,
            _orderIndex,
            order.collateralToken,
            order.indexToken,
            order.collateralDelta,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.executionFee,
            order.triggerAboveThreshold
        );
    }

    function _updatePrice(bytes[] memory _priceUpdateData) private{
        if(_priceUpdateData.length == 0){
            return;
        }

        IVaultPriceFeed pricefeed = IVaultPriceFeed(IDipxStorage(dipxStorage).priceFeed());
        IPythPriceFeed pythPricefeed = IPythPriceFeed(pricefeed.pythPriceFeed());
        pythPricefeed.updatePriceFeeds(_priceUpdateData);
    }

    function executeOrders(address[] memory _addressArray, uint256[] memory _orderIndexArray, bool[] memory _orderTypes, address _feeReceiver, bool _raise,bytes[] memory _priceUpdateData) external nonReentrant{
        require(_addressArray.length == _orderIndexArray.length && _addressArray.length == _orderTypes.length);
        _updatePrice(_priceUpdateData);
        for (uint256 i = 0; i < _addressArray.length; i++) {
            if(_orderTypes[i]){
                _executeIncreaseOrder(_addressArray[i], _orderIndexArray[i], _feeReceiver, _raise);
            }else{
                _executeDecreaseOrder(_addressArray[i], _orderIndexArray[i], _feeReceiver, _raise);
            }
            
        }
    }

    function executeIncreaseOrders(address[] memory _addressArray, uint256[] memory _orderIndexArray, address _feeReceiver, bool _raise, bytes[] memory _priceUpdateData) external nonReentrant{
        require(_addressArray.length == _orderIndexArray.length);
        _updatePrice(_priceUpdateData);
        for (uint256 i = 0; i < _addressArray.length; i++) {
            _executeIncreaseOrder(_addressArray[i], _orderIndexArray[i], _feeReceiver, _raise);
        }
    }

    function executeIncreaseOrder(address _address, uint256 _orderIndex, address _feeReceiver, bool _raise, bytes[] memory _priceUpdateData) external nonReentrant {
        _updatePrice(_priceUpdateData);
        _executeIncreaseOrder(_address, _orderIndex, _feeReceiver, _raise);
    }

    function _executeIncreaseOrder(address _address, uint256 _orderIndex, address _feeReceiver, bool _raise) private{
        Order memory order = increaseOrders[_address][_orderIndex];
        if(order.account == address(0)){
            require(!_raise, "OrderBook: non-existent order");
            return;
        }

        (uint256 currentPrice, bool isPriceValid) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            order.isLong,
            _raise
        );
        if(!isPriceValid){
            return;
        }
        
        address routerAddr = router();
        uint256 liqFee = IRouter(routerAddr).getPoolLiqFee(order.collateralToken);
        TransferHelper.safeTransfer(order.collateralToken,routerAddr,order.collateralDelta);
        IRouter(routerAddr).pluginIncreasePosition{value:liqFee}(
            order.account, 
            order.indexToken, 
            order.collateralToken, 
            order.collateralDelta, 
            order.sizeDelta, 
            order.isLong
        );

        // pay executor
        _transferOutETH(order.executionFee-liqFee, _feeReceiver);
        delete increaseOrders[_address][_orderIndex];
        _removeAccountOrder(_address,_orderIndex,true);
        emit ExecuteIncreaseOrder(
            order.account,
            _orderIndex,
            order.collateralToken,
            order.indexToken,
            order.collateralDelta,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.executionFee,
            currentPrice,
            order.triggerAboveThreshold,
            liqFee
        );
    }

    function createDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external payable nonReentrant {
        uint256 liqFee = IRouter(router()).getPoolLiqFee(_collateralToken);
        require(msg.value >= minExecutionFee+liqFee, "OrderBook: insufficient execution fee");

        _createDecreaseOrder(
            msg.sender,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function _createDecreaseOrder(
        address _account,
        address _collateralToken,
        uint256 _collateralDelta,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) private {
        uint256 _orderIndex = decreaseOrdersIndex[_account];
        Order memory order = Order(
            _orderIndex,
            false,
            _account,
            _collateralToken,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            msg.value,
            _triggerAboveThreshold
        );
        decreaseOrdersIndex[_account] = _orderIndex + 1;
        decreaseOrders[_account][_orderIndex] = order;
        _addAccountOrder(_account,_orderIndex,false);

        emit CreateDecreaseOrder(
            _account,
            _orderIndex,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            msg.value,
            _triggerAboveThreshold
        );
    }

    function executeDecreaseOrders(address[] memory _addressArray, uint256[] memory _orderIndexArray, address _feeReceiver, bool _raise, bytes[] memory _priceUpdateData) external nonReentrant {
        require(_addressArray.length == _orderIndexArray.length);
        _updatePrice(_priceUpdateData);
        for (uint256 i = 0; i < _addressArray.length; i++) {
            _executeDecreaseOrder(_addressArray[i], _orderIndexArray[i], _feeReceiver,_raise);
        }
    }

    function executeDecreaseOrder(address _address, uint256 _orderIndex, address _feeReceiver, bool _raise, bytes[] memory _priceUpdateData) external nonReentrant {
        _updatePrice(_priceUpdateData);
        _executeDecreaseOrder(_address, _orderIndex, _feeReceiver,_raise);
    }

    function _executeDecreaseOrder(address _address, uint256 _orderIndex, address _feeReceiver, bool _raise) private {
        Order memory order = decreaseOrders[_address][_orderIndex];
        if(order.account == address(0)){
            require(!_raise, "OrderBook: non-existent order");
            return;
        }

        (uint256 currentPrice,bool isPriceValid) = validatePositionOrderPrice(
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            !order.isLong,
            _raise
        );
        if(!isPriceValid){
            return;
        }

        address routerAddr = router();
        uint256 liqFee = IRouter(routerAddr).getPoolLiqFee(order.collateralToken);
        try IRouter(routerAddr).pluginDecreasePosition{value:liqFee}(
            order.account, 
            order.indexToken, 
            order.collateralToken, 
            order.sizeDelta,
            order.collateralDelta, 
            order.isLong, 
            order.account
        ){}catch Error(string memory _err) {
            if(_raise){
                revert(_err);
            }
            return;
        }catch{
            if(_raise){
                revert("OrderBook: DecreasePosition error");
            }
            return;
        }

        // pay executor
        _transferOutETH(order.executionFee-liqFee, _feeReceiver);
        delete decreaseOrders[_address][_orderIndex];
        _removeAccountOrder(_address,_orderIndex,false);

        emit ExecuteDecreaseOrder(
            order.account,
            _orderIndex,
            order.collateralToken,
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.executionFee,
            currentPrice,
            order.triggerAboveThreshold,
            liqFee
        );
    }

    function cancelDecreaseOrder(uint256 _orderIndex) public nonReentrant {
        Order memory order = decreaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        delete decreaseOrders[msg.sender][_orderIndex];
        _removeAccountOrder(msg.sender,_orderIndex,false);
        _transferOutETH(order.executionFee, msg.sender);

        emit CancelDecreaseOrder(
            order.account,
            _orderIndex,
            order.collateralToken,
            order.collateralDelta,
            order.indexToken,
            order.sizeDelta,
            order.isLong,
            order.triggerPrice,
            order.executionFee,
            order.triggerAboveThreshold
        );
    }

    function updateDecreaseOrder(
        uint256 _orderIndex,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external nonReentrant {
        Order storage order = decreaseOrders[msg.sender][_orderIndex];
        require(order.account != address(0), "OrderBook: non-existent order");

        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
        order.collateralDelta = _collateralDelta;

        emit UpdateDecreaseOrder(
            msg.sender,
            _orderIndex,
            order.collateralToken,
            _collateralDelta,
            order.indexToken,
            _sizeDelta,
            order.isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function transferOutETH(uint256 _amountOut, address _receiver) external onlyOwner {
        _transferOutETH(_amountOut, _receiver);
    }

    function _transferOutETH(uint256 _amountOut, address _receiver) private {
        TransferHelper.safeTransferETH(_receiver, _amountOut);
    }
}

