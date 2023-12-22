// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./extensions_IERC20Metadata.sol";
import "./SafeERC20.sol";

import "./IWETH.sol";

contract TransferHelper {
    using SafeERC20 for IERC20;

    IWETH internal immutable WETH;

    constructor(IWETH _WETH) {
        WETH = _WETH;
    }

    function _safeTransferFrom(
        address _token,
        address _sender,
        uint256 _amount
    ) internal {
        require(_amount > 0, "TransferHelper: amount must be > 0");
        IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
    }

    function _safeTransfer(
        address _token,
        address _recipient,
        uint256 _amount
    ) internal {
        require(_amount > 0, "TransferHelper: amount must be > 0");
        IERC20(_token).safeTransfer(_recipient, _amount);
    }

    function _wethWithdrawTo(address _to, uint256 _amount) internal {
        require(_amount > 0, "TransferHelper: amount must be > 0");
        require(_to != address(0), "TransferHelper: invalid recipient");

        WETH.withdraw(_amount);
        (bool success, ) = _to.call{value: _amount}(new bytes(0));
        require(success, "TransferHelper: ETH transfer failed");
    }

    function _depositWeth() internal {
        require(msg.value > 0, "TransferHelper: amount must be > 0");
        WETH.deposit{value: msg.value}();
    }
}

