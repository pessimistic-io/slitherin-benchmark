// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./CrosschainFunctionCallInterface.sol";
import "./CbcDecVer.sol";
import "./NonAtomicHiddenAuthParameters.sol";
import "./ResponseProcessUtil.sol";
import "./IFuturesGateway.sol";

contract FuturesAdapter is
    CrosschainFunctionCallInterface,
    CbcDecVer,
    NonAtomicHiddenAuthParameters,
    ResponseProcessUtil,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    // 	0x77dab611
    bytes32 internal constant CROSS_CALL_EVENT_SIGNATURE =
        keccak256("CrossCall(bytes32,uint256,address,uint256,address,bytes)");

    event CrossCallHandler(
        bytes32 txId,
        uint256 timestamp,
        address caller,
        uint256 destBcId,
        address destContract,
        bytes functionCall
    );

    IFuturesGateway public futuresGateway;

    // How old events can be before they are not accepted.
    // Also used as a time after which crosschain transaction ids can be purged from the
    // replayProvention map, thus reducing the cost of the crosschain transaction.
    // Measured in seconds.
    uint256 public timeHorizon;

    // Used to prevent replay attacks in transaction.
    // Mapping of txId to transaction expiry time.
    mapping(bytes32 => uint256) public replayPrevention;

    uint256 public myBlockchainId;

    // Use to determine different transactions but have same calldata, block timestamp
    uint256 txIndex;

    /**
     * Crosschain Transaction event.
     *
     * @param _txId Crosschain Transaction id.
     * @param _timestamp The time when the event was generated.
     * @param _caller Contract or EOA that submitted the crosschain call on the source blockchain.
     * @param _destBcId Destination blockchain Id.
     * @param _destContract Contract to be called on the destination blockchain.
     * @param _destFunctionCall The function selector and parameters in ABI packed format.
     */
    event CrossCall(
        bytes32 _txId,
        uint256 _timestamp,
        address _caller,
        uint256 _destBcId,
        address _destContract,
        uint8 _destMethodID,
        bytes _destFunctionCall
    );

    event CallFailure(string _revertReason);

    event TransactionRelayed(uint256 sourceChainId, bytes32 sourceTxHash);

    /**
     * @param _myBlockchainId Blockchain identifier of this blockchain.
     * @param _timeHorizon How old crosschain events can be before they are
     *     deemed to be invalid. Measured in seconds.
     */
    function initialize(
        uint256 _myBlockchainId,
        uint256 _timeHorizon
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __Pausable_init();

        myBlockchainId = _myBlockchainId;
        timeHorizon = _timeHorizon;
    }

    function crossBlockchainCall(
        // NOTE: can keep using _destBcId and _destContract to determine which blockchain is calling
        uint256 _destBcId,
        address _destContract,
        uint8 _destMethodID,
        bytes calldata _destData
    ) external override {
        txIndex++;
        bytes32 txId = keccak256(
            abi.encodePacked(
                block.timestamp,
                myBlockchainId,
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
            _destMethodID,
            _destData
        );
    }

    struct DecodedEventData {
        bytes32 txId;
        uint256 timestamp;
        address caller;
        uint256 destBcId;
        address destContract;
    }

    // For relayer
    function crossCallHandler(
        uint256 _sourceBcId,
        address _cbcAddress,
        bytes calldata _eventData,
        bytes calldata _signature,
        bytes32 _sourceTxHash
    ) public {
        address relayer = msg.sender;
        require(whitelistRelayers[relayer], "invalid relayer");
        //        decodeAndVerifyEvent(
        //            _sourceBcId,
        //            _cbcAddress,
        //            CROSS_CALL_EVENT_SIGNATURE,
        //            _eventData,
        //            _signature,
        //            relayer
        //        );

        // Decode _eventData
        // Recall that the cross call event is:
        // event CrossCall(
        //     bytes32 _txId,
        //     uint256 _timestamp,
        //     address _caller,
        //     uint256 _destBcId,
        //     address _destContract,
        //     uint8 _destMethodID,
        //     bytes _destFunctionCall
        // );
        bytes memory functionCall;

        DecodedEventData memory decodedEventData;

        (
            decodedEventData.txId,
            decodedEventData.timestamp,
            decodedEventData.caller,
            decodedEventData.destBcId,
            decodedEventData.destContract,
            ,
            functionCall
        ) = abi.decode(
            _eventData,
            (bytes32, uint256, address, uint256, address, uint8, bytes)
        );

        require(
            replayPrevention[decodedEventData.txId] == 0,
            "Transaction already exists"
        );

//        require(
//            decodedEventData.timestamp <= block.timestamp,
//            "Event timestamp is in the future"
//        );
        //        require(timestamp + timeHorizon > block.timestamp, "Event is too old");
        replayPrevention[decodedEventData.txId] = decodedEventData.timestamp;

        require(
            decodedEventData.destBcId == myBlockchainId,
            "Incorrect destination blockchain id"
        );

        // Add authentication information to the function call.
        bytes memory functionCallWithAuth = encodeNonAtomicAuthParams(
            functionCall,
            _sourceBcId,
            decodedEventData.caller
        );

        bool isSuccess;
        bytes memory returnValueEncoded;
        (isSuccess, returnValueEncoded) = decodedEventData.destContract.call(
            functionCallWithAuth
        );
        require(isSuccess, getRevertMsg(returnValueEncoded));

        emit CrossCallHandler(
            decodedEventData.txId,
            decodedEventData.timestamp,
            decodedEventData.caller,
            decodedEventData.destBcId,
            decodedEventData.destContract,
            functionCall
        );
    }

    function updateFuturesGateway(address _address) external onlyOwner {
        futuresGateway = IFuturesGateway(_address);
    }

    function setMyChainID(uint256 _chainID) external onlyOwner {
        myBlockchainId = _chainID;
    }

    function updateGnosisSafeAddress(address _newAddress) external onlyOwner {
        gnosisSafe = _newAddress;
    }

    function updateRelayerStatus(address _relayer, bool _status) external onlyOwner {
        whitelistRelayers[_relayer] = _status;
    }

    function getRelayerStatus(address _relayer) external view returns (bool) {
        return whitelistRelayers[_relayer];
    }

    address gnosisSafe;
    mapping(address => bool) internal whitelistRelayers;
}

