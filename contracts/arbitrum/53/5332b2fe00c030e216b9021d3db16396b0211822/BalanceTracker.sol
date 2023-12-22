/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity >=0.8;

import "./SafeERC20Upgradeable.sol";

abstract contract BalanceTracker {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function availableBalance(
        address _token
    ) public view virtual returns (uint256);

    function _transferIn(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        if (_isNativeCoin(_token)) {
            return;
        }
        IERC20Upgradeable(_token).safeTransferFrom(
            _spender,
            address(this),
            _amount
        );
    }

    function _transferOut(
        address _token,
        address _recipient,
        uint256 _amount
    ) internal {
        require(availableBalance(_token) >= _amount, "Insufficient balance");
        _out(_token, _recipient, _amount);
    }

    function _withdraw(
        address _token,
        address _recipient,
        uint256 _amount
    ) internal {
        _out(_token, _recipient, _amount);
    }

    function _out(
        address _token,
        address _recipient,
        uint256 _amount
    ) internal {
        require(availableBalance(_token) >= _amount, "Insufficient balance");
        if (_isNativeCoin(_token)) {
            (bool sent, ) = payable(_recipient).call{value: _amount}("");
            require(sent, "Transfer native coin failed");
            return;
        }
        IERC20Upgradeable(_token).safeTransfer(_recipient, _amount);
    }

    function _isNativeCoin(address _token) internal pure returns (bool) {
        return _token == 0x0000000000000000000000000000000000000001;
    }
}

