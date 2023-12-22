//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./Structs.sol";
import "./OneinchSupport.sol";
import "./IMBusSupport.sol";
import "./I1inchSupport.sol";
import "./IProtocolSupport.sol";
import "./Address.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract DForceDexRouter is ReentrancyGuardUpgradeable, BaseSupport, OwnableUpgradeable, Structs {
    using Address for address;

    struct SwapPoolInfo {
        uint8 _poolType;
        bytes _data;
    }

    struct InchInfo {
        address _from;
        uint256 _amount;
        bool _order;
        bytes _data;
    }

    modifier onlyThis() {
        require(msg.sender == address(this), "DForceDexRouter: this func only this contract call");
        _;
    }

    uint8 public constant SWAP_TYPE_DEFAULT = 1;
    uint8 public constant SWAP_TYPE_1INCH = 2;

    event Set1inchSupport(address _old, address _new);
    event AddSupport(uint8 _type, address _support);
    event Swap(address _sender, address _from, uint256 _fromAmount, address _to, uint256 _toAmount);
    event SwapPoolType(uint8 _type);

    address public inchSupport;
    mapping(uint8 => address) public support;

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    constructor() {
        initialize();
    }

    function quote(uint8 _type, bytes memory _data) external returns (uint256, bytes memory) {
        address _support = support[_type];
        require(_support != address(0), "DForceDexRouter: not have this type");
        bytes memory _returns = _support.functionDelegateCall(abi.encodeWithSelector(IProtocolSupport.quote.selector, _data));
        return abi.decode(_returns, (uint256, bytes));
    }

    function tokensQuote(uint8 _type, bytes memory _data) external returns (uint256, bytes memory) {
        address _support = support[_type];
        require(_support != address(0), "DForceDexRouter: not have this type");
        bytes memory _returns = _support.functionDelegateCall(abi.encodeWithSelector(IProtocolSupport.tokensQuote.selector, _data));
        return abi.decode(_returns, (uint256, bytes));
    }

    function swap(
        SwapBaseInfo memory _baseInfo,
        SwapPoolInfo[] memory _swaps,
        InchInfo memory _1inchInfo
    ) external payable nonReentrant returns (uint256) {
        uint256 _amount = _baseInfo._amount;
        if (_baseInfo._from == ETH) {
            require(msg.value >= _baseInfo._amount, "DForceDexRouter: msg.value not enough");
        } else {
            SafeERC20.safeTransferFrom(IERC20(_baseInfo._from), msg.sender, address(this), _amount);
        }

        _amount = this._swap(_baseInfo, _swaps, _1inchInfo);

        if (_baseInfo._to == ETH) {
            payable(msg.sender).transfer(_amount);
        } else {
            SafeERC20.safeTransfer(IERC20(_baseInfo._to), msg.sender, _amount);
        }

        emit Swap(msg.sender, _baseInfo._from, _baseInfo._amount, _baseInfo._to, _amount);
        return _amount;
    }

    function _blendSwap(SwapBaseInfo memory _baseInfo, SwapInfo memory _swapInfo) external payable onlyThis returns (uint256 _returns) {
        if (_swapInfo._swapType == SWAP_TYPE_DEFAULT) {
            (SwapPoolInfo[] memory _swaps, InchInfo memory _1inchInfo) = abi.decode(_swapInfo._swapData, (SwapPoolInfo[], InchInfo));
            _returns = this._swap(_baseInfo, _swaps, _1inchInfo);
        } else if (_swapInfo._swapType == SWAP_TYPE_1INCH) {
            InchInfo memory _1inchInfo = abi.decode(_swapInfo._swapData, (InchInfo));
            if (_1inchInfo._amount != _baseInfo._amount) {
                _1inchInfo._data = inchSupport.functionDelegateCall(abi.encodeWithSelector(I1inchSupport.modifyOneinchAmount.selector, _1inchInfo._data, _baseInfo._amount));
                _1inchInfo._data = abi.decode(_1inchInfo._data, (bytes));
            }
            bytes memory _data = inchSupport.functionDelegateCall(abi.encodeWithSelector(I1inchSupport.inchSwapNoHandle.selector, _baseInfo._from, _baseInfo._amount, _1inchInfo._data));
            _returns = abi.decode(_data, (uint256));
            require(_returns >= _baseInfo._minReturn, string(abi.encodePacked("DForceDexRouter: _returns < _minReturn, returns: ", Strings.toString(_returns))));
        } else {
            require(false, "DForceDexRouter: wrong _swapType");
        }
    }

    function _swap(
        SwapBaseInfo memory _baseInfo,
        SwapPoolInfo[] memory _swaps,
        InchInfo memory _1inchInfo
    ) external payable onlyThis returns (uint256 _amount) {
        _amount = _baseInfo._amount;
        if (_1inchInfo._data.length != 0 && _1inchInfo._order) {
            bytes memory _data = _1inchInfo._data;
            if (_1inchInfo._amount != _amount) {
                _data = inchSupport.functionDelegateCall(abi.encodeWithSelector(I1inchSupport.modifyOneinchAmount.selector, _1inchInfo._data, _amount));
                _data = abi.decode(_data, (bytes));
            }
            bytes memory _returns = inchSupport.functionDelegateCall(abi.encodeWithSelector(I1inchSupport.inchSwapNoHandle.selector, _1inchInfo._from, _amount, _data));
            _amount = abi.decode(_returns, (uint256));
        }

        _amount = _internalSwap(_swaps, _amount);

        if (_1inchInfo._data.length != 0 && !_1inchInfo._order) {
            bytes memory _data = _1inchInfo._data;
            if (_1inchInfo._amount != _amount) {
                _data = inchSupport.functionDelegateCall(abi.encodeWithSelector(I1inchSupport.modifyOneinchAmount.selector, _1inchInfo._data, _amount));
                _data = abi.decode(_data, (bytes));
            }
            bytes memory _returns = inchSupport.functionDelegateCall(abi.encodeWithSelector(I1inchSupport.inchSwapNoHandle.selector, _1inchInfo._from, _amount, _data));
            _amount = abi.decode(_returns, (uint256));
        }

        require(_amount >= _baseInfo._minReturn, string(abi.encodePacked("DForceDexRouter: _returns < _minReturn, returns: ", Strings.toString(_amount))));
    }

    function inchSwap(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _minReturn,
        bytes memory _inData
    ) external payable returns (uint256 _returns) {
        bytes memory _data = inchSupport.functionDelegateCall(abi.encodeWithSelector(I1inchSupport.inchSwap.selector, _from, _to, _amount, _minReturn, _inData));
        _returns = abi.decode(_data, (uint256));
        emit Swap(msg.sender, _from, _amount, _to, _returns);
    }

    function set1inchSupport(address _new) external onlyOwner {
        address _old = inchSupport;
        inchSupport = _new;
        emit Set1inchSupport(_old, _new);
    }

    function addSupport(uint8 _type, address _support) external onlyOwner {
        support[_type] = _support;
        emit AddSupport(_type, _support);
    }

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes memory _data
    ) external {
        support[UNI3_TYPE].functionDelegateCall(abi.encodeWithSelector(DForceDexRouter.uniswapV3SwapCallback.selector, 0, 0, _data));
    }

    function _internalSwap(SwapPoolInfo[] memory _swaps, uint256 _amount) internal returns (uint256) {
        for (uint256 i = 0; i < _swaps.length; i++) {
            address _support = support[_swaps[i]._poolType];
            if (_support == address(0)) continue;
            bytes memory _returns = _support.functionDelegateCall(abi.encodeWithSelector(IProtocolSupport.swap.selector, _amount, _swaps[i]._data));
            _amount = abi.decode(_returns, (uint256));
        }
        return _amount;
    }
}

