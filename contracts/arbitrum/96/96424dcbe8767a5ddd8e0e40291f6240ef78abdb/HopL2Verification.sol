// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "./BaseVerification.sol";

contract HopL2Verifier is BaseVerifier{
    struct HopBridgeRequestData {
        // fees passed to relayer
        uint256 bonderFee;
        // The minimum amount received after attempting to swap in the destination AMM market. 0 if no swap is intended.
        uint256 amountOutMin;
        // The deadline for swapping in the destination AMM market. 0 if no swap is intended.
        uint256 deadline;
        // Minimum amount expected to be received or bridged to destination
        uint256 amountOutMinDestination;
        // deadline for bridging to destination
        uint256 deadlineDestination;
        // socket offchain created hash
        bytes32 metadata;
    }

    function bridgeERC20To(
        address receiverAddress,
        address token,
        address hopAMM,
        uint256 amount,
        uint256 toChainId,
        HopBridgeRequestData calldata hopBridgeRequestData
    ) external returns (SocketRequest memory) {
        return SocketRequest(amount, receiverAddress, toChainId, token, msg.sig);
    }

    receive() external payable {}

    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
}

