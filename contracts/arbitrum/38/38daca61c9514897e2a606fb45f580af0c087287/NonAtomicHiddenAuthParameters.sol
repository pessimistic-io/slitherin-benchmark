/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity >=0.8;

abstract contract NonAtomicHiddenAuthParameters {
    /**
     * Add authentication parameters to the end of an existing function call.
     *
     * @param _functionCall       Function selector and an arbitrary list of parameters.
     * @param _sourceBlockchainId Blockchain identifier of the blockchain that is calling the function.
     * @param _sourceContract     The address of the contract that is calling the function.
     */
    function encodeNonAtomicAuthParams(
        bytes memory _functionCall,
        uint256 _sourceBlockchainId,
        address _sourceContract
    ) internal pure returns (bytes memory) {
        return
            bytes.concat(
                _functionCall,
                abi.encodePacked(_sourceBlockchainId, _sourceContract)
            );
    }

    /**
     * Extract authentication values from the end of the call data. The parameters are expected to have been
     * added to the end of the function call using encodeNonAtomicAuthParams.
     *
     * @return _sourceBlockchainId Blockchain identifier of the blockchain that is calling the function.
     * @return _sourceContract     The address of the contract that is calling the function.
     */
    function decodeNonAtomicAuthParams()
        internal
        pure
        returns (uint256 _sourceBlockchainId, address _sourceContract)
    {
        bytes calldata allParams = msg.data;
        uint256 len = allParams.length;

        assembly {
            calldatacopy(0x0, sub(len, 52), 32)
            _sourceBlockchainId := mload(0)
            calldatacopy(12, sub(len, 20), 20)
            _sourceContract := mload(0)
        }
    }
}

