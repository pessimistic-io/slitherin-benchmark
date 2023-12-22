/**
 * Facet for verifying LI.FI related offchain commands
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./Types.sol";

contract LIFIValidator {
    struct SwapData {
        address callTo;
        address approveTo;
        address sendingAssetId;
        address receivingAssetId;
        uint256 fromAmount;
        bytes callData;
        bool requiresDeposit;
    }

    // For now simply verify receiver is correct (The msg.sender - i.e the vault)
    function validateLifiswapCalldata(
        OffchainCommandValidation calldata validationData
    ) external view returns (bool isValid) {
        {
            address receiver = extractReceiver(validationData);
            if (receiver == msg.sender) isValid = true;
        }
    }

    function extractReceiver(
        OffchainCommandValidation memory validationData
    ) internal pure returns (address receiver) {
        (, , , receiver) = abi.decode(
            validationData.interpretedArgs,
            (bytes32, string, string, address)
        );
    }
}

