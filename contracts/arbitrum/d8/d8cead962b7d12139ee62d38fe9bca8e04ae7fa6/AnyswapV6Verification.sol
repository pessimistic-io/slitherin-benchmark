// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "./BaseVerification.sol";

contract AnyswapV6Verification is BaseVerifier {
    function bridgeERC20To(
        uint256 amount,
        uint256 toChainId,
        bytes32 metadata,
        address receiverAddress,
        address token,
        address wrapperTokenAddress,
        bool isEvm
    ) external payable returns (SocketRequest memory) {
         return SocketRequest(amount, receiverAddress, toChainId, token, msg.sig);
    }

    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}

