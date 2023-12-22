// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETHelper {
    function withdraw(uint256) external;
}

contract WETHelper {
    receive() external payable {}

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "!WETHelper: ETH_TRANSFER_FAILED");
    }

    function withdraw(
        address _eth,
        address _to,
        uint256 _amount
    ) public {
        IWETHelper(_eth).withdraw(_amount);
        safeTransferETH(_to, _amount);
    }
}

