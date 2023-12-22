//  SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./multicall.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function balanceOf(address) external returns (uint256);
}

interface IWrapToken {
    function depositFrom(address from, address to, uint256 amount) external returns(uint256 actualAmount);
    function withdraw(address to, uint256 amount) external returns(uint256 actualAmount);
    function balanceOf(address) external returns (uint256);
}

contract SwapProxy is Multicall {

    using SafeERC20 for IERC20;
    receive() external payable {}

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }

    function depositWETH(address weth) external payable {
        IWETH(weth).deposit{value: msg.value}();
    }

    function unwrapWETH(address weth, address recipient) external {
        uint256 all = IWETH(weth).balanceOf(address(this));
        IWETH(weth).withdraw(all);
        safeTransferETH(recipient, all);
    }

    function refundETH() external payable {
        if (address(this).balance > 0) safeTransferETH(msg.sender, address(this).balance);
    }

    function depositWrapToken(address wrapToken, uint256 value) external {
        IWrapToken(wrapToken).depositFrom(msg.sender, address(this), value);
    }

    function withdrawWrapToken(address wrapToken, address recipient) external {
        uint256 value = IWrapToken(wrapToken).balanceOf(address(this));
        if (value > 0) {
            IWrapToken(wrapToken).withdraw(recipient, value);
        }
    }

    function depositToken(address token, uint256 value) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), value);
    }
    
    function sweepToken(
        address token,
        address recipient
    ) external {
        uint256 all = IERC20(token).balanceOf(address(this));
        if (all > 0) {
            IERC20(token).safeTransfer(recipient, all);
        }
    }

    function approveToken(address token, address spender) external {
        bool ok = IERC20(token).approve(spender, type(uint256).max);
        require(ok, 'approve fail');
    }

    function proxy(address targetContract, bytes calldata data, uint256 msgValue) external payable returns (bytes memory res){
        require(address(this).balance >= msgValue, "ETH NOT ENOUGH!");
        (bool success, bytes memory result) = targetContract.call{value: msgValue}(data);
        
        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (result.length < 68) revert();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }
        return result;
    }

}
