// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.23;

import "./ChainlinkLowLatencyOracleBase.sol";

abstract contract LowLatencyRequestFulfiller is ChainlinkLowLatencyOracleBase {
    struct RequestData {
        uint8 requestType;
        uint256 requestId;
        address requester;
        uint256 executionFee;
    }

    bytes4 public constant actionRequest = bytes4(keccak256("ActionRequest(uint8,uint256,address,uint256,bytes)"));

    uint256 public currentRequestId;
    mapping(uint256 => bool) public pendingRequests;
    uint256 public expirationPeriodSec;
    bool public catchErrors;

    uint256 public pendingExecutionFees;
    uint256 public requiredExecutionFee;

    event ActionRequest(uint8 indexed requestType, uint256 indexed requestId, address indexed requester, uint256 executionFee, bytes eventData);
    event ActionSuccess(uint8 indexed requestType, uint256 indexed requestId, address indexed requester, uint256 executionFee);
    event ActionFailure(uint8 indexed requestType, uint256 indexed requestId, address indexed requester, uint256 refundedExecutionFee, string reason, bytes data);

    function __LowLatencyRequestFulfiller_init(address _owner, OracleLookupData calldata _oracleLookupData, IVerifierProxy _verifier, uint256 _expirationPeriodSec) internal onlyInitializing {
        
        require(_expirationPeriodSec > 0, "expirationPeriodSec must be > 0");
        
        ChainlinkLowLatencyOracleBase.__ChainlinkLowLatencyOracleBase_init(_owner, _oracleLookupData, _verifier);

        expirationPeriodSec = _expirationPeriodSec;
        catchErrors = true;
        requiredExecutionFee = 1e14;
    }

    function setRequiredExecutionFee(uint256 _newRequiredExecutionFee) external onlyOwner {
        requiredExecutionFee = _newRequiredExecutionFee;
    }

    function setCatchErrors(bool _catchErrors) external onlyOwner {
        catchErrors = _catchErrors;
    }

    function setExpirationPeriodSec(uint256 _expirationPeriodSec) external onlyOwner {
        require(_expirationPeriodSec > 0, "expirationPeriodSec must be > 0");
        
        expirationPeriodSec = _expirationPeriodSec;
    }

    function getNextRequest() internal returns (uint256 requestId, address requester, uint256 executionFee) {
        require(msg.value == requiredExecutionFee, 'Execution Fee');

        pendingExecutionFees += msg.value;
        currentRequestId += 1;
        pendingRequests[currentRequestId] = true;
        return (currentRequestId, msg.sender, msg.value);
    }

    function createActionRequest(uint8 _requestType, bytes memory _eventData) internal {
        (uint256 requestId, address requester, uint256 executionFee) = getNextRequest();
        emit ActionRequest(_requestType, requestId, requester, executionFee, _eventData);
    }

    function refundExecutionFee(address _requester, uint256 _executionFee) internal {
        if (_executionFee > 0) {
            pendingExecutionFees -= _executionFee;
            (bool sent,) = payable(_requester).call{value: _executionFee}("");
            require(sent, "Failed to send refund");
        }
    }

    function withdrawExecutionFees() external onlyRole(EXECUTOR_ROLE) {
        uint256 availableToWithdraw = address(this).balance - pendingExecutionFees;
        require(availableToWithdraw > 0, "Nothing to withdraw");
        (bool sent,) = payable(msg.sender).call{value: availableToWithdraw}("");
        require(sent, "Failed to withdraw");
    }

    function performEventMatch(bytes4 _eventType, bytes memory _eventData) internal view override returns (bool, bytes memory) {
        bool isEventMatch = false;
        if (_eventType == actionRequest) { 
            (uint8 requestType, uint256 requestId,,,) = abi.decode(_eventData, (uint8, uint256, address, uint256, bytes));
            if (requestType != 0) {
                bool isPending = pendingRequests[requestId];
                if (isPending) {
                    isEventMatch = true;
                }
            }
        }

        return (isEventMatch, _eventData);
    }

    function execute(bytes memory _verifierResponse, bytes[] memory _chainlinkReports, bytes memory _data) internal override {
        ReportsData memory reportsData;

        reportsData.cviValue = abi.decode(_verifierResponse, (int256));
        reportsData.eventTimestamp = abi.decode(_chainlinkReports[1], (uint256));

        RequestData memory requestData;
        bytes memory requestDataEncoded;
        (requestData.requestType, requestData.requestId, requestData.requester, requestData.executionFee, requestDataEncoded) = abi.decode(_data, (uint8, uint256, address, uint256, bytes));
        require(pendingRequests[requestData.requestId], 'Request not pending');

        if (block.timestamp - reportsData.eventTimestamp >= expirationPeriodSec) {
            executionFailure(requestData, "RequestTimeout", "0x");
        } else {
            executeEvent(requestData, requestDataEncoded, reportsData.cviValue);
        }

        delete pendingRequests[requestData.requestId];
    }

    function executionSuccess(RequestData memory _requestData) internal {
        pendingExecutionFees -= _requestData.executionFee;
        emit ActionSuccess(_requestData.requestType, _requestData.requestId, _requestData.requester, _requestData.executionFee);
    }

    function executionFailure(RequestData memory _requestData, string memory reason, bytes memory lowLevelData) internal {
        refundExecutionFee(_requestData.requester, _requestData.executionFee);
        emit ActionFailure(_requestData.requestType, _requestData.requestId, _requestData.requester, _requestData.executionFee, reason, lowLevelData);
    }

    function executeEvent(RequestData memory _requestData, bytes memory _requestDataEncoded, int256 _cviValue) internal virtual;
}



