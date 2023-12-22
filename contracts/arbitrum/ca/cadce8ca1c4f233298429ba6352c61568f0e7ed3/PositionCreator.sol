// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./IPositionRouter.sol";
import "./IOrderBook.sol";
import "./ReentrancyGuard.sol";

/**
 * @title PositionCreator
 * @notice This contract is responsible for making complex sets of orders and positions in a single transaction.
 */

contract PositionCreator is ReentrancyGuard {
    address public orderBook;
    address public positionRouter;

    address public admin;
    address public pendingAdmin;

    uint8 public constant INCREASE_POSITION = 0;
    uint8 public constant INCREASE_ORDER = 1;
    uint8 public constant DECREASE_ORDER = 2;

    constructor(address _orderBook, address _positionRouter) public {
        admin = msg.sender;
        orderBook = _orderBook;
        positionRouter = _positionRouter;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "PositionCreator: forbidden");
        _;
    }

    function setOrderBook(address _orderBook) external onlyAdmin {
        orderBook = _orderBook;
    }

    function setPositionRouter(address _positionRouter) external onlyAdmin {
        positionRouter = _positionRouter;
    }

    function setPendingAdmin(address _pendingAdmin) external onlyAdmin {
        pendingAdmin = _pendingAdmin;
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "PositionCreator: forbidden");
        admin = pendingAdmin;
        pendingAdmin = address(0);
    }

    function executeMultiple(
        uint8[] memory _actions,
        bytes[] memory _args,
        uint256[] memory _msgValues
    ) external payable nonReentrant {
        require(
            _actions.length == _args.length && _actions.length == _msgValues.length,
            "PositionCreator: invalid array lengths"
        );

        for (uint256 i = 0; i < _actions.length; i++) {
            if (_actions[i] == INCREASE_POSITION) {
                _createIncreasePosition(_args[i], _msgValues[i]);
            } else if (_actions[i] == INCREASE_ORDER) {
                _createIncreaseOrder(_args[i], _msgValues[i]);
            } else if (_actions[i] == DECREASE_ORDER) {
                _createDecreaseOrder(_args[i], _msgValues[i]);
            } else {
                revert("PositionCreator: invalid action");
            }
        }
    }

    function _createIncreasePosition(bytes memory _args, uint256 _msgValue) internal {
        (
            address[] memory _path,
            address _indexToken,
            uint256 _amountIn,
            uint256 _minOut,
            uint256 _sizeDelta,
            bool _isLong,
            uint256 _acceptablePrice,
            uint256 _executionFee,
            bytes32 _referralCode,
            bool _wrap
        ) = abi.decode(_args, (address[], address, uint256, uint256, uint256, bool, uint256, uint256, bytes32, bool));
        IPositionRouter(positionRouter).createIncreasePositionForUser{value: _msgValue}(
            msg.sender,
            _path,
            _indexToken,
            _amountIn,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            _referralCode,
            _wrap
        );
    }

    function _createIncreaseOrder(bytes memory _args, uint256 _msgValue) internal {
        (
            address[] memory _path,
            uint256 _amountIn,
            address _indexToken,
            uint256 _minOut,
            uint256 _sizeDelta,
            address _collateralToken,
            bool _isLong,
            uint256 _triggerPrice,
            bool _triggerAboveThreshold,
            uint256 _executionFee,
            bool _shouldWrap
        ) = abi.decode(
                _args,
                (address[], uint256, address, uint256, uint256, address, bool, uint256, bool, uint256, bool)
            );
        IOrderBook(orderBook).createIncreaseOrderForUser{value: _msgValue}(
            msg.sender,
            _path,
            _amountIn,
            _indexToken,
            _minOut,
            _sizeDelta,
            _collateralToken,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            _executionFee,
            _shouldWrap
        );
    }

    function _createDecreaseOrder(bytes memory _args, uint256 _msgValue) internal {
        (
            address _indexToken,
            uint256 _sizeDelta,
            address _collateralToken,
            uint256 _collateralDelta,
            bool _isLong,
            uint256 _triggerPrice,
            bool _triggerAboveThreshold
        ) = abi.decode(_args, (address, uint256, address, uint256, bool, uint256, bool));
        IOrderBook(orderBook).createDecreaseOrderForUser{value: _msgValue}(
            msg.sender,
            _indexToken,
            _sizeDelta,
            _collateralToken,
            _collateralDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }
}

