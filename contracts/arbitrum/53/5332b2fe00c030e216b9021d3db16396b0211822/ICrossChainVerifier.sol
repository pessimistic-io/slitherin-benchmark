/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity >=0.8;

interface ICrossChainVerifier {
    /**
     * Decode and verify event information. Use require to fail the transaction
     * if any of the information is invalid.
     *
     * @param _blockchainId The blockchain that emitted the event. This could be
     *    used to determine which sets of signing keys are valid.
     * @param _eventSig The event function selector. This will be for a Start event,
     *    a Segment event, or a Root event. Not all implementations will need to
     *    use this value. Others may need this to allow then to find the event in a
     *    transaction receipt.
     * @param _signedEventInfo The abi.encodePacked of the blockchain id, the Crosschain
     *    Control contract's address, the event function selector, and the event data.
     * @param _signature Signatures or proof information that an implementation can
     *    use to check that _signedEventInfo is valid.
     * @return bool which is always true. This return value is so that Web3J generates wrappers correctly.
     */
    function decodeAndVerifyEvent(
        uint256 _blockchainId,
        bytes32 _eventSig,
        bytes calldata _signedEventInfo,
        bytes calldata _signature
    ) external view returns (bool);

    /**
     * Return the list of signers for a blockchain.
     * Implementation of this function is optional.
     *
     * @param _blockchainId The blockchain that the signers are valid for.
     * @return list of addresses that are the signers for events from a blockchain.
     */
    function getSigners(uint256 _blockchainId)
        external
        view
        returns (address[] memory);

    /**
     * Return the signing algorithm supported by signers of events from a blockchain.
     *
     * @param _blockchainId The blockchain that is the source of events being validated.
     * @return Signature algorithm identifier.
     */
    function supportedSigningAlgorithm(uint256 _blockchainId)
        external
        view
        returns (uint256);
}

