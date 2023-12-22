// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

interface IWETHelper {
    function withdraw(uint) external;
}

contract WETHelper {
    receive() external payable {}

    function safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "!WETHelper: ETH_TRANSFER_FAILED");
    }

    function withdraw(address _eth, address _to, uint256 _amount) public {
        IWETHelper(_eth).withdraw(_amount);
        safeTransferETH(_to, _amount);
    }
}

