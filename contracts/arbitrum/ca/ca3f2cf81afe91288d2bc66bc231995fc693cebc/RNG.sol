/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.9;

import "./RrpRequesterV0.sol";
import "./IRNG.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IConsole.sol";
import "./Types.sol";
import "./ICaller.sol";

contract RNG is RrpRequesterV0, IRNG, Ownable, ReentrancyGuard {
    error UnauthorizedCaller(address _caller);
    error UnknownRequestId(bytes32 _requestId);

    address public airnode;
    bytes32 public endpointIdUint256;
    bytes32 public endpointIdUint256Array;
    address public sponsorWallet;

    mapping (bytes32 => bool) public expectingRequestWithIdToBeFulfilled;
    mapping (bytes32 => address) public callers;
    mapping (address => bool) public callerWhitelist;

    IConsole public immutable console;

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(bytes32 indexed requestId, uint256 response);
    event RequestedUint256Array(bytes32 indexed requestId, uint256 size);
    event ReceivedUint256Array(bytes32 indexed requestId, uint256[] response);

    modifier onlyCaller() {
        if (!callerWhitelist[msg.sender]) {
            Types.Game memory _Game = console.getGameByImpl(msg.sender);
            if (address(0) == _Game.impl || !_Game.live || _Game.date == 0) {
                revert UnauthorizedCaller(msg.sender);
            }
        }
        _;
    }

    constructor(address _airnodeRrp, address _console) RrpRequesterV0(_airnodeRrp) {
        console = IConsole(_console);
    }

    function makeRequestUint256() external onlyCaller returns (bytes32) {
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
        callers[requestId] = msg.sender;
        emit RequestedUint256(requestId);
        return requestId;
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @dev Note the `onlyAirnodeRrp` modifier. You should only accept RRP
    /// fulfillments from this protocol contract. Also note that only
    /// fulfillments for the requests made by this contract are accepted, and
    /// a request cannot be responded to multiple times.
    /// @param requestId Request ID
    /// @param data ABI-encoded response
    function fulfillUint256(bytes32 requestId, bytes calldata data) external onlyAirnodeRrp {
        if (!expectingRequestWithIdToBeFulfilled[requestId]) {
            revert UnknownRequestId(requestId);
        }
        expectingRequestWithIdToBeFulfilled[requestId] = false;
        uint256 qrngUint256 = abi.decode(data, (uint256));
        // Do what you want with `qrngUint256` here...
        emit ReceivedUint256(requestId, qrngUint256);
    }

    /// @notice Requests a `uint256[]`
    /// @param size Size of the requested array
    function makeRequestUint256Array(uint256 size) external onlyCaller returns (bytes32) {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256Array,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256Array.selector,
            // Using Airnode ABI to encode the parameters
            abi.encode(bytes32("1u"), bytes32("size"), size)
        );
        expectingRequestWithIdToBeFulfilled[requestId] = true;
        callers[requestId] = msg.sender;
        emit RequestedUint256Array(requestId, size);
        return requestId;
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @param requestId Request ID
    /// @param data ABI-encoded response
    function fulfillUint256Array(bytes32 requestId, bytes calldata data) external onlyAirnodeRrp {
        if (!expectingRequestWithIdToBeFulfilled[requestId]) {
            revert UnknownRequestId(requestId);
        }
        expectingRequestWithIdToBeFulfilled[requestId] = false;
        uint256[] memory qrngUint256Array = abi.decode(data, (uint256[]));
        ICaller(callers[requestId]).fulfillRNG(requestId, qrngUint256Array);
        emit ReceivedUint256Array(requestId, qrngUint256Array);
    }

    function setRequestParameters(address _airnode, bytes32 _endpointIdUint256, bytes32 _endpointIdUint256Array, address _sponsorWallet) external nonReentrant onlyOwner {
        airnode = _airnode;
        endpointIdUint256 = _endpointIdUint256;
        endpointIdUint256Array = _endpointIdUint256Array;
        sponsorWallet = _sponsorWallet;
    }

    function setCallerWhitelist(address _caller, bool _isWhitelisted) external nonReentrant onlyOwner {
        callerWhitelist[_caller] = _isWhitelisted;
    }

    function getSponsorWallet() external view returns (address) {
        return sponsorWallet;
    }
}

