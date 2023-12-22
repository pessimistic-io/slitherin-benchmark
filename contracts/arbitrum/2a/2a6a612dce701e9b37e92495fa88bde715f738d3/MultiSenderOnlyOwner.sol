// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IERC20.sol";

contract MultiSenderV2 is Ownable {
    constructor () {
    }

    receive() external payable {}

    function _withdrawERC20(address _token) private {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        TransferHelper.safeTransfer(_token, msg.sender, balance);
    }

    function _withdrawETH() private {
        payable(msg.sender).transfer(address(this).balance);
    }

    function sendETH(address[] calldata _account, uint256 _quantity) external payable onlyOwner {
        require(_quantity != 0 && _account.length != 0, 'err1');
        require(address(this).balance >= _quantity * _account.length, 'err2');

        for (uint256 i = 0; i < _account.length; i++) {
            payable(_account[i]).transfer(_quantity);
        }
        if (address(this).balance != 0) {
            _withdrawETH();
        }
    }

    function sendToken(address[] calldata _account, uint256[] calldata _postion, address _tokenAddress) external onlyOwner {
        require(IERC20(_tokenAddress).balanceOf(msg.sender) != 0 && _postion.length != 0 && _account.length != 0, 'err1');
        uint256 _quantity = IERC20(_tokenAddress).balanceOf(msg.sender);

        TransferHelper.safeTransferFrom(_tokenAddress, msg.sender, address(this), _quantity);
        
        uint256 totalPostion = 0;
        for (uint256 i = 0; i < _postion.length; i++) {
            totalPostion += _postion[i];
        }
        for (uint256 i = 0; i < _account.length; i++) {
            TransferHelper.safeTransfer(_tokenAddress, _account[i], (_quantity * _postion[i] / totalPostion));
        }
        if (IERC20(_tokenAddress).balanceOf(address(this)) != 0) {
            _withdrawERC20(_tokenAddress);
        }
    }
}

library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}
