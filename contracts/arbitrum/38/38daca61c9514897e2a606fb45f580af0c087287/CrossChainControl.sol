/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity ^0.8.8;

import "./OwnableUpgradeable.sol";

import "./ICrossChainFunctionCall.sol";

import "./ResponseProcessUtil.sol";
import "./NonAtomicHiddenAuthParameters.sol";
import "./CbcDecVer.sol";

contract CrossChainControl is
    ICrossChainFunctionCall,
    CbcDecVer,
    NonAtomicHiddenAuthParameters,
    ResponseProcessUtil
{
    // 	0x77dab611
    bytes32 internal constant CROSS_CALL_EVENT_SIGNATURE =
        keccak256("CrossCall(bytes32,uint256,address,uint256,address,bytes)");

    // How old events can be before they are not accepted.
    // Also used as a time after which cross-chain transaction ids can be purged from the
    // replayPrevention map, thus reducing the cost of the cross-chain transaction.
    // Measured in seconds.
    uint256 public timeHorizon;

    // Used to prevent replay attacks in transaction.
    // Mapping of txId to transaction expiry time.
    mapping(bytes32 => uint256) public replayPrevention;

    // Current blockchain ID
    uint256 public myBcId;

    // Use to determine different transactions but have same calldata, block timestamp
    uint256 private txIndex;

    /**
     * Crosschain Transaction event.
     *
     * @param txId Cross-chain Transaction id.
     * @param timestamp The time when the event was generated.
     * @param caller Contract or EOA that submitted the cross-chain call on the source blockchain.
     * @param destBcId Destination blockchain Id.
     * @param destContract Contract to be called on the destination blockchain.
     * @param destFunctionCall The function selector and parameters in ABI packed format.
     */
    event CrossCall(
        bytes32 txId,
        uint256 timestamp,
        address caller,
        uint256 destBcId,
        address destContract,
        bytes destFunctionCall
    );

    event CallSucceed(bytes32 txId, address caller);

    /**
     * @param _myBcId Blockchain identifier of this blockchain.
     * @param _timeHorizon How old cross-chain events can be before they are
     *     deemed to be invalid. Measured in seconds.
     */
    function initialize(
        uint256 _myBcId,
        uint256 _timeHorizon
    ) public initializer {
        __Ownable_init();

        myBcId = _myBcId;
        timeHorizon = _timeHorizon;
    }

    function crossBlockchainCall(
        // NOTE: can keep using _destBcId and _destContract to determine which blockchain is calling
        uint256 _destBcId,
        address _destContract,
        bytes calldata _destData
    ) external override returns (bytes32 txId) {
        txIndex++;
        txId = keccak256(
            abi.encodePacked(
                block.timestamp,
                myBcId,
                _destBcId,
                _destContract,
                _destData,
                txIndex
            )
        );
        emit CrossCall(
            txId,
            block.timestamp,
            msg.sender,
            _destBcId,
            _destContract,
            _destData
        );
    }

    /**
     * Call the crossCallHandler, but first specify a set of old transaction
     * identifiers. Releasing storage will tend to reduce the gas cost of the
     * overall transaction (15,000 gas is returned for each storage location
     * that has a non-zero value that is set to zero).
     */
    function crossCallHandlerSaveGas(
        uint256 _srcBcId,
        address _cbcAddress,
        bytes calldata _eventData,
        bytes calldata _signature,
        bytes32[] calldata _oldTxIds
    ) external {
        // Go through the array of old cross-chain transaction ids. If they
        for (uint256 i = 0; i < _oldTxIds.length; i++) {
            bytes32 oldTxId = _oldTxIds[i];
            uint256 timestamp = replayPrevention[oldTxId];
            if (timestamp + timeHorizon > block.timestamp) {
                if (timestamp != 0) {
                    replayPrevention[oldTxId] = 0;
                }
            }
        }
        crossCallHandler(_srcBcId, _cbcAddress, _eventData, _signature);
    }

    function crossCallHandler(
        uint256 _sourceBcId,
        address _cbcAddress,
        bytes calldata _eventData,
        bytes calldata _signature
    ) public {
        decodeAndVerifyEvent(
            _sourceBcId,
            _cbcAddress,
            CROSS_CALL_EVENT_SIGNATURE,
            _eventData,
            _signature
        );

        // Decode _eventData
        // Recall that the cross call event is:
        // CrossCall(bytes32 _txId, uint256 _timestamp, address _caller,
        //           uint256 _destBcId, address _destContract, bytes _destFunctionCall)
        bytes32 txId;
        uint256 timestamp;
        address caller;
        uint256 destBcId;
        address destContract;
        bytes memory functionCall;
        (txId, timestamp, caller, destBcId, destContract, functionCall) = abi
            .decode(
                _eventData,
                (bytes32, uint256, address, uint256, address, bytes)
            );

        require(replayPrevention[txId] == 0, "Transaction already exists");

        require(
            timestamp < block.timestamp,
            "Event timestamp is in the future"
        );
        require(timestamp + timeHorizon > block.timestamp, "Event is too old");
        replayPrevention[txId] = timestamp;

        require(destBcId == myBcId, "Incorrect destination blockchain id");

        // Add authentication information to the function call.
        bytes memory functionCallWithAuth = encodeNonAtomicAuthParams(
            functionCall,
            _sourceBcId,
            caller
        );

        bool isSuccess;
        bytes memory returnValueEncoded;
        (isSuccess, returnValueEncoded) = destContract.call(
            functionCallWithAuth
        );
        require(isSuccess, getRevertMsg(returnValueEncoded));
        emit CallSucceed(txId, msg.sender);
    }
}

