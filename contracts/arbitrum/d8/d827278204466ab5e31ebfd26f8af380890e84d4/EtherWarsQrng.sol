// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./RrpRequesterV0.sol";
import "./Ownable.sol";

interface IEtherWars {
    function beginCombat(
        address _attacker,
        string memory _username,
        uint256 _faction,
        uint256[] calldata _randomWords
    ) external;
}

contract EtherWarsQrng is RrpRequesterV0, Ownable {
    struct RequestStatus {
        bool exists;
        bool fulfilled;
        address attacker;
        string name;
        uint256 faction;
    }

    IEtherWars public etherWarsContract;
    address public airnode;
    address public sponsorWallet;
    bytes32 public endpointIdUint256Array;

    mapping(bytes32 => RequestStatus) public expectingRequestWithIdToBeFulfilled;

    event RequestedUint256Array(bytes32 indexed requestId, uint256 size);
    event ReceivedUint256Array(bytes32 indexed requestId, uint256[] response);

    error NotEtherWarsContract();
    error ZeroAddressNotAllowed();
    error BadEndpoint();

    /// @dev RrpRequester sponsors itself, meaning that it can make requests
    /// that will be fulfilled by its sponsor wallet. See the Airnode protocol
    /// docs about sponsorship for more information.
    /// @param _airnodeRrp Airnode RRP contract address
    constructor(address _airnodeRrp) RrpRequesterV0(_airnodeRrp) {}

    modifier onlyEtherWars() {
        if (IEtherWars(msg.sender) != etherWarsContract) revert NotEtherWarsContract();
        _;
    }

    /// @notice Requests a `uint256[]`
    /// @param _size Size of the requested array
    function makeRequestUint256Array(
        uint256 _size,
        address _attacker,
        string memory _name,
        uint256 _faction
    ) external onlyEtherWars {
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
        expectingRequestWithIdToBeFulfilled[requestId].exists = true;
        expectingRequestWithIdToBeFulfilled[requestId].attacker = _attacker;
        expectingRequestWithIdToBeFulfilled[requestId].name = _name;
        expectingRequestWithIdToBeFulfilled[requestId].faction = _faction;

        emit RequestedUint256Array(requestId, _size);
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @param _requestId Request ID
    /// @param _data ABI-encoded response
    function fulfillUint256Array(bytes32 _requestId, bytes calldata _data) external onlyAirnodeRrp {
        require(
            expectingRequestWithIdToBeFulfilled[_requestId].exists &&
                !expectingRequestWithIdToBeFulfilled[_requestId].fulfilled,
            "Request ID not known"
        );
        expectingRequestWithIdToBeFulfilled[_requestId].fulfilled = true;
        uint256[] memory qrngUint256Array = abi.decode(_data, (uint256[]));
        etherWarsContract.beginCombat(
            expectingRequestWithIdToBeFulfilled[_requestId].attacker,
            expectingRequestWithIdToBeFulfilled[_requestId].name,
            expectingRequestWithIdToBeFulfilled[_requestId].faction,
            qrngUint256Array
        );
        emit ReceivedUint256Array(_requestId, qrngUint256Array);
    }

    /// @notice Sets parameters used in requesting QRNG services
    /// @param _airnode Airnode address
    /// @param _endpointIdUint256Array Endpoint ID used to request a `uint256[]`
    /// @param _sponsorWallet Sponsor wallet address
    function setRequestParameters(
        address _airnode,
        bytes32 _endpointIdUint256Array,
        address _sponsorWallet
    ) external onlyOwner {
        if (_airnode == address(0)) revert ZeroAddressNotAllowed();
        if (_sponsorWallet == address(0)) revert ZeroAddressNotAllowed();
        if (_endpointIdUint256Array == 0) revert BadEndpoint();

        airnode = _airnode;
        endpointIdUint256Array = _endpointIdUint256Array;
        sponsorWallet = _sponsorWallet;
    }

    function setEtherWarsAddress(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddressNotAllowed();
        etherWarsContract = IEtherWars(_address);
    }

    function setAirnodeAddress(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddressNotAllowed();
        airnode = _address;
    }

    function setSponsorWalletAddress(address _address) external onlyOwner {
        if (_address == address(0)) revert ZeroAddressNotAllowed();
        sponsorWallet = _address;
    }

    function setAirnodeAddress(bytes32 _endpoint) external onlyOwner {
        if (_endpoint == 0) revert BadEndpoint();
        endpointIdUint256Array = _endpoint;
    }
}

