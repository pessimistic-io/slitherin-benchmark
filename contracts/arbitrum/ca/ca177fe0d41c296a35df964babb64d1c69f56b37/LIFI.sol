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

    // /**
    //  * @param encodedOffchainValidation - OffchainValidation, encoded
    //  * @return isValid - Whether it is a valid offchain command or not
    //  */
    // For now simply verify receiver is correct (The msg.sender - i.e the vault)
    function validateLifiswapCalldata(
        bytes calldata encodedOffchainValidation
    ) external view returns (bool isValid) {
        {
            address receiver = getSwapData(encodedOffchainValidation);
            if (receiver == msg.sender) isValid = true;
        }
    }

    function getSwapData(
        bytes memory encodedOffchainValidation
    ) internal pure returns (address) {
        OffchainCommandValidation memory validationData = abi.decode(
            encodedOffchainValidation,
            (OffchainCommandValidation)
        );

        return extractReceiver(validationData);
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

