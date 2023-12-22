// SPDX-License-Identifier: MIT LICENSE
pragma solidity 0.8.15;
import "./SafeERC20.sol";
import "./ISwapPair.sol";
import "./IWETH.sol";

contract CheeseTool {
  using SafeERC20 for IERC20;

  function removeLiquidity(address weth, ISwapPair LPToken, uint256 amount, uint256 amountToken0Min, uint256 amountToken1Min, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    address addressThis = address(this);
    LPToken.permit(msg.sender, addressThis, amount, deadline, v, r, s);
    LPToken.transferFrom(msg.sender, address(LPToken), amount);
    LPToken.burn(addressThis);
    IERC20 token0 = IERC20(LPToken.token0());
    IERC20 token1 = IERC20(LPToken.token1());

    uint256 amunt0 = token0.balanceOf(addressThis);
    require(amunt0 >= amountToken0Min, 'Insufficient amountToken0Min');
    if (address(token0) == weth) {
      IWETH(address(token0)).withdraw(amunt0);
      safeTransferETH(msg.sender, amunt0);
    } else {
      token0.safeTransfer(msg.sender, amunt0);
    }

    uint256 amunt1 = token1.balanceOf(addressThis);
    require(amunt1 >= amountToken1Min, 'Insufficient amountToken1Min');
    if (address(token1) == weth) {
      IWETH(address(token1)).withdraw(amunt1);
      safeTransferETH(msg.sender, amunt1);
    } else {
      token1.safeTransfer(msg.sender, amunt1);
    }
  }

  function safeTransferETH(address to, uint256 value) internal {
    (bool success, ) = to.call{ value: value }(new bytes(0));
    require(success, 'safeTransferETH: ETH transfer failed');
  }

  receive() external payable {}
}

