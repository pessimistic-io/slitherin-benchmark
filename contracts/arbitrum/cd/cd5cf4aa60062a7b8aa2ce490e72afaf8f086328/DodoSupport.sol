//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./BaseSupport.sol";
import "./IProtocolSupport.sol";
import { IDodoV2Proxy02, IDodoFactory, IDodoPool, IDodoApporveProxy } from "./IDodo.sol";

contract DodoSupport is BaseSupport, IProtocolSupport {
    struct DodoSwapData {
        address _pool;
        address _from;
        address _to;
        uint256 _directions;
        uint256 _minReturn;
    }

    struct QuoteData {
        address _from;
        address _to;
        uint256 _amount;
    }

    struct QuoteReturnData {
        address _pool;
        uint256 _directions;
    }

    struct TokensQuoteData {
        address _from;
        address[] _tos;
        uint256 _amount;
    }

    struct TokensQuoteReturnData {
        address _pool;
        address _to;
        uint256 _directions;
    }

    IDodoV2Proxy02 public immutable v2Proxy02;
    address public immutable spFactory;

    constructor(address _v2Proxy02, address _spFactory) {
        v2Proxy02 = IDodoV2Proxy02(_v2Proxy02);
        spFactory = _spFactory;
    }

    function quote(bytes memory _inputData) external view override returns (uint256, bytes memory) {
        QuoteData memory _data = abi.decode(_inputData, (QuoteData));

        (address _pool, uint256 _returns, uint256 _directions) = _quote(_data._from, _data._to, _data._amount);
        return (_returns, abi.encode(QuoteReturnData({ _pool: _pool, _directions: _directions })));
    }

    function tokensQuote(bytes memory _inputData) external view override returns (uint256 _returns, bytes memory _returnData) {
        TokensQuoteData memory _data = abi.decode(_inputData, (TokensQuoteData));
        TokensQuoteReturnData memory _quoteReturnData;

        uint256 _lastHandleAmount;
        for (uint256 i = 0; i < _data._tos.length; i++) {
            address _to1 = _data._tos[i];

            (address _pool, uint256 _returns1, uint256 _directions) = _quote(_data._from, _to1, _data._amount);
            uint256 _handleAmount = _handleDecimals(_to1, _returns1);
            if (_handleAmount > _lastHandleAmount) {
                _quoteReturnData._pool = _pool;
                _quoteReturnData._to = _to1;
                _returns = _returns1;
                _lastHandleAmount = _handleAmount;
                _quoteReturnData._directions = _directions;
            }
        }
        _returnData = abi.encode(_quoteReturnData);
    }

    function swap(uint256 _amount, bytes memory _inputData) external payable override returns (uint256 _returns) {
        DodoSwapData memory _data = abi.decode(_inputData, (DodoSwapData));
        _safeApprove(IERC20(_data._from), _apporveAddress(), _amount);
        address[] memory _pools = new address[](1);
        _pools[0] = _data._pool;
        return v2Proxy02.dodoSwapV2TokenToToken(_data._from, _data._to, _amount, _data._minReturn, _pools, _data._directions, true, block.timestamp);
    }

    function _quote(
        address _from,
        address _to,
        uint256 _amount
    )
        private
        view
        returns (
            address _pool,
            uint256 _returns,
            uint256 _directions
        )
    {
        (address _pool0, uint256 _returns0, uint256 _directions0) = _getPoolAmount(vMFactory(), _from, _to, _amount);
        (address _pool1, uint256 _returns1, uint256 _directions1) = _getPoolAmount(spFactory, _from, _to, _amount);

        if (_handleDecimals(_to, _returns0) > _handleDecimals(_to, _returns1)) {
            return (_pool0, _returns0, _directions0);
        } else {
            return (_pool1, _returns1, _directions1);
        }
    }

    function _getPoolAmount(
        address _factory,
        address _from,
        address _to,
        uint256 _amount
    )
        private
        view
        returns (
            address _pool,
            uint256 _returns,
            uint256 _directions
        )
    {
        (address _pool0, address _pool1) = _getPools(_factory, _from, _to);
        uint256 _returns0;
        bool _order0;

        if (_pool0 != address(0)) {
            _order0 = IDodoPool(_pool0)._BASE_TOKEN_() == _from;
            if (_order0) {
                (bool _success, bytes memory _data) = _pool0.staticcall(abi.encodeWithSelector(IDodoPool(_pool0).querySellBase.selector, address(this), _amount));
                if (_success && _data.length > 0) {
                    _returns0 = abi.decode(_data, (uint256));
                }
            } else {
                (bool _success, bytes memory _data) = _pool0.staticcall(abi.encodeWithSelector(IDodoPool(_pool0).querySellQuote.selector, address(this), _amount));
                if (_success && _data.length > 0) {
                    _returns0 = abi.decode(_data, (uint256));
                }
            }
        }

        uint256 _returns1;
        bool _order1;
        if (address(_pool1) != address(0)) {
            _order1 = IDodoPool(_pool1)._BASE_TOKEN_() == _from;
            if (_order1) {
                (bool _success, bytes memory _data) = _pool1.staticcall(abi.encodeWithSelector(IDodoPool(_pool1).querySellBase.selector, address(this), _amount));
                if (_success && _data.length > 1) {
                    _returns1 = abi.decode(_data, (uint256));
                }
            } else {
                (bool _success, bytes memory _data) = _pool1.staticcall(abi.encodeWithSelector(IDodoPool(_pool1).querySellQuote.selector, address(this), _amount));
                if (_success && _data.length > 1) {
                    _returns1 = abi.decode(_data, (uint256));
                }
            }
        }

        _pool = _returns0 > _returns1 ? _pool0 : _pool1;
        _returns = _returns0 > _returns1 ? _returns0 : _returns1;
        _directions = _returns0 > _returns1 ? (_order0 ? 0 : 1) : (_order1 ? 0 : 1);
    }

    function _getPools(
        address _factory,
        address _token0,
        address _token1
    ) private view returns (address, address) {
        (address[] memory _pools0, address[] memory _pool1) = IDodoFactory(_factory).getDODOPoolBidirection(_token0, _token1);
        return (_pools0.length == 0 ? address(0) : _pools0[0], _pool1.length == 0 ? address(0) : _pool1[0]);
    }

    function _apporveAddress() private view returns (address) {
        return IDodoApporveProxy(v2Proxy02._DODO_APPROVE_PROXY_())._DODO_APPROVE_();
    }

    //Stable Pool Factory
    function vMFactory() public view returns (address) {
        return v2Proxy02._DVM_FACTORY_();
    }
}

