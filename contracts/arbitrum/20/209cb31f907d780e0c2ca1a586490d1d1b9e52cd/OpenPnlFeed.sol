// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ChainlinkClient.sol";
import "./IERC20.sol";
import "./IWorkPool.sol";
import "./IOpenPnlFeed.sol";


contract OpenPnlFeed is ChainlinkClient, IOpenPnlFeed{
    using Chainlink for Chainlink.Request;

    uint256 constant MIN_ANSWERS = 0;
    uint256 constant MIN_REQUESTS_START = 1 hours;
    uint256 constant MAX_REQUESTS_START = 1 weeks;
    uint256 constant MIN_REQUESTS_EVERY = 1 hours;
    uint256 constant MAX_REQUESTS_EVERY = 1 days;
    uint256 constant MIN_REQUESTS_COUNT = 3;
    uint256 constant MAX_REQUESTS_COUNT = 10;

    struct Request{
        bool initiated;
        bool active;
        uint256 linkFeePerNode;
    }

    IWorkPool public immutable workPool;
    IAddOpenPnlFeedFund public orderTokenManagement;

    uint256 public requestsStart = 2 days;
    uint256 public requestsEvery = 6 hours;
    uint256 public requestsCount = 4;

    address[] public oracles;
    bytes32 public job;
    uint256 public minAnswers;
    uint256 public linkFee;

    int256[] public nextEpochValues;
    uint256 public nextEpochValuesRequestCount;
    uint256 public nextEpochValuesLastRequest;

    uint public lastRequestId;
    mapping(bytes32 => uint256) public requestIds;   // chainlink request id => requestId
    mapping(address => mapping(uint256 => bytes32)) public requestByAddressId;
    mapping(uint256 => Request) public requests;     // requestId => request
    mapping(uint256 => int256[]) public requestAnswers; // requestId => open pnl

    event NumberParamUpdated(string name, uint256 newValue);
    event OracleUpdated(uint256 index, address newValue);
    event OraclesUpdated(address[] newValues);
    event JobUpdated(bytes32 newValue);
    event OrderTokenManagementUpdated(address newValue);

    event NextEpochValuesReset(
        uint256 indexed currEpoch,
        uint256 requestsResetCount
    );

    event NewEpochForced(uint256 indexed newEpoch);

    event NextEpochValueRequested(
        uint256 indexed currEpoch,
        uint256 indexed requestId,
        bytes32 job,
        uint256 oraclesCount,
        uint256 linkFeePerNode
    );

    event NewEpoch(
        uint256 indexed newEpoch,
        uint256 indexed requestId,
        int256[] epochMedianValues,
        int256 epochAverageValue,
        uint256 newEpochPositiveOpenPnl
    );

    event RequestValueReceived(
        bool isLate,
        uint256 indexed currEpoch,
        uint256 indexed requestId,
        bytes32 oracleRequestId,
        address indexed oracle,
        int256 requestValue,
        uint256 linkFee
    );

    event RequestMedianValueSet(
        uint256 indexed currEpoch,
        uint256 indexed requestId,
        int256[] requestValues,
        int256 medianValue
    );

    error OpenPnlFeedWrongParameters();
    error OpenPnlFeedWrongIndex();
    error OpenPnlFeedInvalidMainPoolOwnerAddress(address account);
    error OpenPnlFeedInvalidAddress(address account);
    error OpenPnlFeedInsufficientNoRequestToReset();
    error OpenPnlFeedInvalidTime();

    modifier onlyMainPoolOwner() {
        if (msg.sender != workPool.mainPoolOwner()) {
            revert OpenPnlFeedInvalidMainPoolOwnerAddress(msg.sender);
        }
        _;
    }


    constructor(
        address _linkToken,
        IWorkPool _workPool,
        address[] memory _oracles,
        bytes32 _job,
        uint256 _minAnswers
    ) {
        if (_linkToken == address(0) ||
            address(_workPool) == address(0) ||
            _oracles.length == 0 ||
            _job == bytes32(0)) {
            revert OpenPnlFeedWrongParameters();
        }

        setChainlinkToken(_linkToken);
        workPool = _workPool;
        oracles = _oracles;
        job = _job;
        minAnswers = _minAnswers;
    }

    function updateMinAnswers(uint256 newValue) external onlyMainPoolOwner{
        minAnswers = newValue;
        emit NumberParamUpdated("minAnswers", newValue);
    }

    function updateOracle(uint256 _index, address newValue) external onlyMainPoolOwner{
        if (_index >= oracles.length) {
            revert OpenPnlFeedWrongIndex();
        }
        if (newValue == address(0)) {
            revert OpenPnlFeedInvalidAddress(address(0));
        }
        oracles[_index] = newValue;
        emit OracleUpdated(_index, newValue);
    }

    function updateOracles(address[] memory newValues) external onlyMainPoolOwner{
        if (newValues.length < minAnswers * 2) {
            revert OpenPnlFeedWrongParameters();
        }
        oracles = newValues;
        emit OraclesUpdated(newValues);
    }

    function setOrderTokenManagement(address newValue) external onlyMainPoolOwner{
        if (newValue == address(0)) {
            revert OpenPnlFeedInvalidAddress(address(0));
        }
        orderTokenManagement = IAddOpenPnlFeedFund(newValue);
        emit OrderTokenManagementUpdated(newValue);
    }

    function updateJob(bytes32 newValue) external onlyMainPoolOwner{
        if (newValue == bytes32(0)) {
            revert OpenPnlFeedWrongParameters();
        }
        job = newValue;
        emit JobUpdated(newValue);
    }

    function setLinkFee(uint256 _fee) external onlyMainPoolOwner{
        linkFee = _fee;
    }

    // Emergency function in case of oracle manipulation
    function resetNextEpochValueRequests() external onlyMainPoolOwner{
        uint256 reqToResetCount = nextEpochValuesRequestCount;
        if (reqToResetCount == 0) {
            revert OpenPnlFeedInsufficientNoRequestToReset();
        }

        delete nextEpochValues;

        nextEpochValuesRequestCount = 0;
        nextEpochValuesLastRequest = 0;

        for(uint256 i; i < reqToResetCount; i++){
            requests[lastRequestId - i].active = false;
        }

        emit NextEpochValuesReset(
            workPool.currentEpoch(),
            reqToResetCount
        );
    }

    // Safety function that anyone can call in case the function above is used in an abusive manner,
    // which could theoretically delay withdrawals indefinitely since it prevents new epochs
    function forceNewEpoch() external{
        if (block.timestamp - workPool.currentEpochStart() < requestsStart + requestsEvery * requestsCount) {
            revert OpenPnlFeedInvalidTime();
        }
        uint256 newEpoch = startNewEpoch();
        emit NewEpochForced(newEpoch);
    }

    function newOpenPnlRequestOrEpoch() external{
        bool firstRequest = nextEpochValuesLastRequest == 0;

        if(firstRequest
            && block.timestamp - workPool.currentEpochStart() >= requestsStart){
            orderTokenManagement.addOpenPnlFeedFund();
            makeOpenPnlRequest();

        }else if(!firstRequest
            && block.timestamp - nextEpochValuesLastRequest >= requestsEvery){
            if(nextEpochValuesRequestCount < requestsCount){
                orderTokenManagement.addOpenPnlFeedFund();
                makeOpenPnlRequest();

            }else if(nextEpochValues.length >= requestsCount){
                startNewEpoch();
            }
        }
    }

    function fulfill(
        bytes32 requestId,
        int256 value
    ) external recordChainlinkFulfillment(requestId){

        uint256 reqId = requestIds[requestId];
        delete requestIds[requestId];

        Request memory r = requests[reqId];
        uint256 currentEpoch = workPool.currentEpoch();

        emit RequestValueReceived(
            !r.active,
            currentEpoch,
            reqId,
            requestId,
            msg.sender,
            value,
            r.linkFeePerNode
        );

        if(!r.active){
            return;
        }

        int256[] storage answers = requestAnswers[reqId];
        answers.push(value);

        if(answers.length == minAnswers){
            int256 medianValue = median(answers);
            nextEpochValues.push(medianValue);

            emit RequestMedianValueSet(
                currentEpoch,
                reqId,
                answers,
                medianValue
            );

            requests[reqId].active = false;
            delete requestAnswers[reqId];
        }
    }

    function updateRequestsInfoBatch(
        uint256 newRequestsStart,
        uint256 newRequestsEvery,
        uint256 newRequestsCount
    ) external onlyMainPoolOwner{
        updateRequestsStart(newRequestsStart);
        updateRequestsEvery(newRequestsEvery);
        updateRequestsCount(newRequestsCount);
    }

    function updateRequestsStart(uint256 newValue) public onlyMainPoolOwner{
        if (newValue < MIN_REQUESTS_START || newValue > MAX_REQUESTS_START) {
            revert OpenPnlFeedWrongParameters();
        }
        requestsStart = newValue;
        emit NumberParamUpdated("requestsStart", newValue);
    }

    function updateRequestsEvery(uint256 newValue) public onlyMainPoolOwner{
        if (newValue < MIN_REQUESTS_EVERY || newValue > MAX_REQUESTS_EVERY) {
            revert OpenPnlFeedWrongParameters();
        }
        requestsEvery = newValue;
        emit NumberParamUpdated("requestsEvery", newValue);
    }

    function updateRequestsCount(uint256 newValue) public onlyMainPoolOwner{
        if (newValue < MIN_REQUESTS_COUNT || newValue > MAX_REQUESTS_COUNT) {
            revert OpenPnlFeedWrongParameters();
        }
        requestsCount = newValue;
        emit NumberParamUpdated("requestsCount", newValue);
    }

    function makeOpenPnlRequest() private{
        Chainlink.Request memory linkRequest = buildChainlinkRequest(
            job,
            address(this),
            this.fulfill.selector
        );

        uint256 linkFeePerNode = linkFee / oracles.length;

        requests[++lastRequestId] = Request({
            initiated: true,
            active: true,
            linkFeePerNode: linkFeePerNode
        });

        nextEpochValuesRequestCount++;
        nextEpochValuesLastRequest = block.timestamp;

        for(uint256 i; i < oracles.length; i ++){
             bytes32 request = sendChainlinkRequestTo(
                oracles[i],
                linkRequest,
                linkFeePerNode
            );

            requestIds[request] = lastRequestId;
            requestByAddressId[oracles[i]][lastRequestId] = request;

        }

        emit NextEpochValueRequested(
            workPool.currentEpoch(),
            lastRequestId,
            job,
            oracles.length,
            linkFeePerNode
        );
    }

    // Increment epoch and update feed value
    function startNewEpoch() private returns(uint256 newEpoch){
        nextEpochValuesRequestCount = 0;
        nextEpochValuesLastRequest = 0;

        uint256 currentEpochPositiveOpenPnl = workPool.currentEpochPositiveOpenPnl();

        int256 newEpochOpenPnl = nextEpochValues.length >= requestsCount ?
            average(nextEpochValues) : int256(currentEpochPositiveOpenPnl);

        uint256 finalNewEpochPositiveOpenPnl = workPool.updateAccPnlPerTokenUsed(
            currentEpochPositiveOpenPnl,
            newEpochOpenPnl > 0 ? uint256(newEpochOpenPnl) : 0
        );

        newEpoch = workPool.currentEpoch();

        emit NewEpoch(
            newEpoch,
            lastRequestId,
            nextEpochValues,
            newEpochOpenPnl,
            finalNewEpochPositiveOpenPnl
        );

        delete nextEpochValues;
    }

    function swap(int256[] memory array, uint256 i, uint256 j) private pure{
        (array[i], array[j]) = (array[j], array[i]);
    }

    function sort(int256[] memory array, uint256 begin, uint256 end) private pure{
        if (begin >= end) { return; }

        uint256 j = begin;
        int256 pivot = array[j];

        for (uint256 i = begin + 1; i < end; ++i) {
            if (array[i] < pivot) {
                swap(array, i, ++j);
            }
        }

        swap(array, begin, j);
        sort(array, begin, j);
        sort(array, j + 1, end);
    }

    function median(int256[] memory array) private pure returns(int256){
        sort(array, 0, array.length);

        return array.length % 2 == 0 ?
            (array[array.length / 2 - 1] + array[array.length / 2]) / 2 :
            array[array.length / 2];
    }

    // Average function
    function average(int256[] memory array) private pure returns(int256){
        int256 sum;
        for(uint256 i; i < array.length; i++){
            sum += array[i];
        }

        return sum / int256(array.length);
    }
}

