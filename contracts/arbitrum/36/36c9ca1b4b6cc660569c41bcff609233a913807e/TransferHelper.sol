// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IERC20.sol";
import "./Decimal.sol";

contract TransferHelper {
    using Decimal for Decimal.decimal;

    mapping(address => uint256) private _decimalMap;

    function _transfer(
        IERC20 _token,
        address _to,
        Decimal.decimal memory _amount
    ) internal {
        uint256 transferValue = _toUint(address(_token), _amount);
        _token.transfer(_to, transferValue);
    }

    function _transferFrom(
        IERC20 _token,
        address _from,
        address _to,
        Decimal.decimal memory _amount
    ) internal {
        uint256 transferValue = _toUint(address(_token), _amount);
        _token.transferFrom(_from, _to, transferValue);
    }

    function _toUint(address _token, Decimal.decimal memory _amount) internal returns (uint256) {
        uint256 decimals = _getDecimals(_token);
        if (decimals >= 18) {
            return _amount.toUint() * (10**(decimals - 18));
        }
        return _amount.toUint() / (10**(18 - decimals));
    }

    function _toDecimal(address _token, uint256 _amount) internal returns (Decimal.decimal memory) {
        uint256 decimals = _getDecimals(_token);
        if (decimals >= 18) {
            return Decimal.decimal(_amount * (10**(decimals - 18)));
        }
        return Decimal.decimal(_amount * (10**(18 - decimals)));
    }

    function _getDecimals(address _token) private returns (uint256 decimals) {
        decimals = _decimalMap[_token];
        if (decimals == 0) {
            (bool success, bytes memory data) = _token.call(abi.encodeWithSignature("decimals()"));
            require(success && data.length != 0, "TransferHelper: get decimals failed");
            decimals = abi.decode(data, (uint256));
            _decimalMap[_token] = decimals;
        }
    }

    function _balanceOf(IERC20 _token, address _whom) internal returns (Decimal.decimal memory) {
        uint256 balance = _token.balanceOf(_whom);
        return _toDecimal(address(_token), balance);
    }
}

