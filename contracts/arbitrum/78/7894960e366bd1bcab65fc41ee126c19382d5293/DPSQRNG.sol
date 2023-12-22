//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./RrpRequesterV0.sol";
import "./AccessControlEnumerable.sol";

/// @title Example contract that uses Airnode RRP to receive QRNG services
/// @notice This contract is not secure. Do not use it in production. Refer to
/// the contract for more information.
/// @dev See README.md for more information.
contract DPSQRNG is RrpRequesterV0, AccessControlEnumerable {
    bytes32 public constant REQUEST_ROLE = keccak256("REQUEST_ROLE");

    // These variables can also be declared as `constant`/`immutable`.
    // However, this would mean that they would not be updatable.
    // Since it is impossible to ensure that a particular Airnode will be
    // indefinitely available, you are recommended to always implement a way
    // to update these parameters.
    address public airnode;
    bytes32 public endpointIdUint256;
    bytes32 public endpointIdUint256Array;
    address public sponsorWallet;

    mapping(bytes32 => bool) public expectingRequestWithIdToBeFulfilled;

    uint256 public lastRequestedSingle;
    uint256[] public lastRequestedArray;

    /// @notice requestId=>result
    mapping(bytes => uint256) public resultsByUserSingle;
    mapping(bytes => uint256[]) public resultsByUserArray;
    /// @notice requestId =>abi.encode(owner,target,index)
    mapping(bytes32 => bytes) public usersByRequestId;

    bytes32[] public requestIdsSingles;
    bytes32[] public requestIdsArrays;

    error NotFulfilled();

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(bytes32 indexed requestId, uint256 response);
    event RequestedUint256Array(bytes32 indexed requestId, uint256 size);
    event ReceivedUint256Array(bytes32 indexed requestId, uint256[] response);

    /// @dev RrpRequester sponsors itself, meaning that it can make requests
    /// that will be fulfilled by its sponsor wallet. See the Airnode protocol
    /// docs about sponsorship for more information.
    /// @param _airnodeRrp Airnode RRP contract address
    constructor(address _airnodeRrp) RrpRequesterV0(_airnodeRrp) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(REQUEST_ROLE, _msgSender());
    }

    /// @notice Sets parameters used in requesting QRNG services
    /// @dev No access control is implemented here for convenience. This is not
    /// secure because it allows the contract to be pointed to an arbitrary
    /// Airnode. Normally, this function should only be callable by the "owner"
    /// or not exist in the first place.
    /// @param _airnode Airnode address
    /// @param _endpointIdUint256 Endpoint ID used to request a `uint256`
    /// @param _endpointIdUint256Array Endpoint ID used to request a `uint256[]`
    /// @param _sponsorWallet Sponsor wallet address
    function setRequestParameters(
        address _airnode,
        bytes32 _endpointIdUint256,
        bytes32 _endpointIdUint256Array,
        address _sponsorWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        airnode = _airnode;
        endpointIdUint256 = _endpointIdUint256;
        endpointIdUint256Array = _endpointIdUint256Array;
        sponsorWallet = _sponsorWallet;
    }

    /// @notice Requests a `uint256`
    /// @dev This request will be fulfilled by the contract's sponsor wallet,
    /// which means spamming it may drain the sponsor wallet. Implement
    /// necessary requirements to prevent this, e.g., you can require the user
    /// to pitch in by sending some ETH to the sponsor wallet, you can have
    /// the user use their own sponsor wallet, you can rate-limit users.
    function makeRequestUint256(bytes calldata _uniqueId) external onlyRole(REQUEST_ROLE) {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );
        expectingRequestWithIdToBeFulfilled[requestId] = true;
        usersByRequestId[requestId] = _uniqueId;

        emit RequestedUint256(requestId);
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @dev Note the `onlyAirnodeRrp` modifier. You should only accept RRP
    /// fulfillments from this protocol contract. Also note that only
    /// fulfillments for the requests made by this contract are accepted, and
    /// a request cannot be responded to multiple times.
    /// @param _requestId Request ID
    /// @param _data ABI-encoded response
    function fulfillUint256(bytes32 _requestId, bytes calldata _data) external onlyAirnodeRrp {
        require(expectingRequestWithIdToBeFulfilled[_requestId], "Request ID not known");
        expectingRequestWithIdToBeFulfilled[_requestId] = false;
        uint256 qrngUint256 = abi.decode(_data, (uint256));

        resultsByUserSingle[usersByRequestId[_requestId]] = qrngUint256;

        emit ReceivedUint256(_requestId, qrngUint256);
    }

    /// @notice Requests a `uint256[]`
    /// @param _size Size of the requested array
    function makeRequestUint256Array(uint256 _size, bytes calldata _uniqueId) external onlyRole(REQUEST_ROLE) {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256Array,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256Array.selector,
            // Using Airnode ABI to encode the parameters
            abi.encode(bytes32("1u"), bytes32("size"), _size)
        );
        expectingRequestWithIdToBeFulfilled[requestId] = true;
        usersByRequestId[requestId] = _uniqueId;
        emit RequestedUint256Array(requestId, _size);
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @param _requestId Request ID
    /// @param _data ABI-encoded response
    function fulfillUint256Array(bytes32 _requestId, bytes calldata _data) external onlyAirnodeRrp {
        require(expectingRequestWithIdToBeFulfilled[_requestId], "Request ID not known");
        expectingRequestWithIdToBeFulfilled[_requestId] = false;
        uint256[] memory qrngUint256Array = abi.decode(_data, (uint256[]));

        resultsByUserArray[usersByRequestId[_requestId]] = qrngUint256Array;

        emit ReceivedUint256Array(_requestId, qrngUint256Array);
    }

    function requestsSingleLength() external view returns (uint256) {
        return requestIdsSingles.length;
    }

    function requestsArraysLength() external view returns (uint256) {
        return requestIdsArrays.length;
    }

    function getRandomResult(bytes calldata _uniqueId) external view returns (uint256) {
        uint256 result = resultsByUserSingle[_uniqueId];
        if (result == 0) {
            revert NotFulfilled();
        }
        return result;
    }

    function getRandomResultArray(bytes calldata _uniqueId) external view returns (uint256[] memory) {
        uint256[] memory result = resultsByUserArray[_uniqueId];
        if (result.length == 0) {
            revert NotFulfilled();
        }
        return result;
    }

    function getRandomNumber(
        uint256 _randomNumber,
        uint256 _blockNumber,
        string calldata _entropy,
        uint256 _min,
        uint256 _max
    ) external view returns (uint256) {
        require(_min <= _max, "Min has to be smaller than max");
        unchecked {
            return
                (uint256(keccak256(abi.encode(_randomNumber, _blockNumber, block.chainid, _entropy, _min, _max))) %
                    (_max - _min + 1)) + _min;
        }
    }
}

