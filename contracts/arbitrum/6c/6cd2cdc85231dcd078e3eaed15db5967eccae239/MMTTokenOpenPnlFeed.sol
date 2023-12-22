// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "./ChainlinkClient.sol";
import "./IERC20.sol";

import "./IVault.sol";
import "./IOwnable.sol";
import "./IOpenTradesPnlFeed.sol";

contract MMTTokenOpenPnlFeed is ChainlinkClient, IOpenTradesPnlFeed {
    using Chainlink for Chainlink.Request;

    // Constants
    uint256 constant LINK_FEE_BALANCE_DIVIDER = 1000;
    //thangtest
    uint256 constant MIN_ANSWERS = 1;
    //uint256 constant MIN_ANSWERS = 3;
    uint256 constant MIN_REQUESTS_START = 1 hours;
    uint256 constant MAX_REQUESTS_START = 1 weeks;
    uint256 constant MIN_REQUESTS_EVERY = 1 hours;
    uint256 constant MAX_REQUESTS_EVERY = 1 days;
    uint256 constant MIN_REQUESTS_COUNT = 3;
    uint256 constant MAX_REQUESTS_COUNT = 10;

    // Params
    IVault public immutable gToken;

    uint256 public requestsStart = 2 days;
    uint256 public requestsEvery = 6 hours;
    uint256 public requestsCount = 4;

    address[] public oracles;
    bytes32 public job;
    uint256 public minAnswers;

    // State
    int256[] public nextEpochValues;
    uint256 public nextEpochValuesRequestCount;
    uint256 public nextEpochValuesLastRequest;

    uint256 public lastRequestId;
    mapping(bytes32 => uint256) public requestIds; // chainlink request id => requestId
    mapping(uint256 => Request) public requests; // requestId => request
    mapping(uint256 => int256[]) public requestAnswers; // requestId => open pnl (1e18)

    struct Request {
        bool initiated;
        bool active;
        uint256 linkFeePerNode;
    }

    // Events
    event NumberParamUpdated(string name, uint256 newValue);
    event OracleUpdated(uint256 index, address newValue);
    event OraclesUpdated(address[] newValues);
    event JobUpdated(bytes32 newValue);

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

    constructor(
        address _linkToken,
        IVault _gToken,
        address[] memory _oracles,
        bytes32 _job,
        uint256 _minAnswers
    ) {
        require(
            _linkToken != address(0) &&
                address(_gToken) != address(0) &&
                _oracles.length > 0 &&
                _job != bytes32(0) &&
                _minAnswers >= MIN_ANSWERS &&
                _minAnswers % 2 == 1 &&
                _minAnswers <= _oracles.length / 2,
            "WRONG_PARAMS"
        );

        setChainlinkToken(_linkToken);

        gToken = _gToken;
        oracles = _oracles;
        job = _job;
        minAnswers = _minAnswers;
    }

    // Modifiers
    modifier onlyGTokenOwner() {
        // 2-week timelock
        require(msg.sender == IOwnable(address(gToken)).owner(), "ONLY_OWNER");
        _;
    }

    modifier onlyGTokenManager() {
        // 3-day timelock
        require(msg.sender == gToken.manager(), "ONLY_MANAGER");
        _;
    }

    modifier onlyGTokenAdmin() {
        // bypasses timelock, emergency functions only
        require(msg.sender == gToken.admin(), "ONLY_ADMIN");
        _;
    }

    // Manage parameters
    function updateRequestsStart(uint256 newValue) public onlyGTokenOwner {
        require(newValue >= MIN_REQUESTS_START, "BELOW_MIN");
        require(newValue <= MAX_REQUESTS_START, "ABOVE_MAX");
        requestsStart = newValue;
        emit NumberParamUpdated("requestsStart", newValue);
    }

    function updateRequestsEvery(uint256 newValue) public onlyGTokenOwner {
        require(newValue >= MIN_REQUESTS_EVERY, "BELOW_MIN");
        require(newValue <= MAX_REQUESTS_EVERY, "ABOVE_MAX");
        requestsEvery = newValue;
        emit NumberParamUpdated("requestsEvery", newValue);
    }

    function updateRequestsCount(uint256 newValue) public onlyGTokenOwner {
        require(newValue >= MIN_REQUESTS_COUNT, "BELOW_MIN");
        require(newValue <= MAX_REQUESTS_COUNT, "ABOVE_MAX");
        requestsCount = newValue;
        emit NumberParamUpdated("requestsCount", newValue);
    }

    function updateRequestsInfoBatch(
        uint256 newRequestsStart,
        uint256 newRequestsEvery,
        uint256 newRequestsCount
    ) external onlyGTokenOwner {
        updateRequestsStart(newRequestsStart);
        updateRequestsEvery(newRequestsEvery);
        updateRequestsCount(newRequestsCount);
    }

    function updateMinAnswers(uint256 newValue) external onlyGTokenManager {
        require(newValue >= MIN_ANSWERS, "BELOW_MIN");
        require(newValue % 2 == 1, "EVEN");
        require(newValue <= oracles.length / 2, "ABOVE_MAX");
        minAnswers = newValue;
        emit NumberParamUpdated("minAnswers", newValue);
    }

    function updateOracle(uint256 _index, address newValue)
        external
        onlyGTokenOwner
    {
        require(_index < oracles.length, "INDEX_TOO_BIG");
        require(newValue != address(0), "VALUE_0");
        oracles[_index] = newValue;
        emit OracleUpdated(_index, newValue);
    }

    function updateOracles(address[] memory newValues)
        external
        onlyGTokenOwner
    {
        require(newValues.length >= minAnswers * 2, "ARRAY_TOO_SMALL");
        oracles = newValues;
        emit OraclesUpdated(newValues);
    }

    function updateJob(bytes32 newValue) external onlyGTokenManager {
        require(newValue != bytes32(0), "VALUE_0");
        job = newValue;
        emit JobUpdated(newValue);
    }

    // Emergency function in case of oracle manipulation
    function resetNextEpochValueRequests() external onlyGTokenAdmin {
        uint256 reqToResetCount = nextEpochValuesRequestCount;
        require(reqToResetCount > 0, "NO_REQUEST_TO_RESET");

        delete nextEpochValues;

        nextEpochValuesRequestCount = 0;
        nextEpochValuesLastRequest = 0;

        for (uint256 i; i < reqToResetCount; i++) {
            requests[lastRequestId - i].active = false;
        }

        emit NextEpochValuesReset(gToken.currentEpoch(), reqToResetCount);
    }

    // Safety function that anyone can call in case the function above is used in an abusive manner,
    // which could theoretically delay withdrawals indefinitely since it prevents new epochs
    function forceNewEpoch() external {
        require(
            block.timestamp - gToken.currentEpochStart() >=
                requestsStart + requestsEvery * requestsCount,
            "TOO_EARLY"
        );
        uint256 newEpoch = startNewEpoch();
        emit NewEpochForced(newEpoch);
    }

    // Called by gToken contract
    function newOpenPnlRequestOrEpoch() external {
        bool firstRequest = nextEpochValuesLastRequest == 0;

        if (
            firstRequest &&
            block.timestamp - gToken.currentEpochStart() >= requestsStart
        ) {
            makeOpenPnlRequest();
        } else if (
            !firstRequest &&
            block.timestamp - nextEpochValuesLastRequest >= requestsEvery
        ) {
            if (nextEpochValuesRequestCount < requestsCount) {
                makeOpenPnlRequest();
            } else if (nextEpochValues.length >= requestsCount) {
                startNewEpoch();
            }
        }
    }

    // Create requests
    function makeOpenPnlRequest() private {
        Chainlink.Request memory linkRequest = buildChainlinkRequest(
            job,
            address(this),
            this.fulfill.selector
        );

        uint256 linkFeePerNode = IERC20(chainlinkTokenAddress()).balanceOf(
            address(this)
        ) /
            LINK_FEE_BALANCE_DIVIDER /
            oracles.length;

        requests[++lastRequestId] = Request({
            initiated: true,
            active: true,
            linkFeePerNode: linkFeePerNode
        });

        nextEpochValuesRequestCount++;
        nextEpochValuesLastRequest = block.timestamp;

        for (uint256 i; i < oracles.length; i++) {
            requestIds[
                sendChainlinkRequestTo(oracles[i], linkRequest, linkFeePerNode)
            ] = lastRequestId;
        }

        emit NextEpochValueRequested(
            gToken.currentEpoch(),
            lastRequestId,
            job,
            oracles.length,
            linkFeePerNode
        );
    }

    // Handle answers
    function fulfill(
        bytes32 requestId,
        int256 value // 1e18
    ) external recordChainlinkFulfillment(requestId) {
        uint256 reqId = requestIds[requestId];
        delete requestIds[requestId];

        Request memory r = requests[reqId];
        uint256 currentEpoch = gToken.currentEpoch();

        emit RequestValueReceived(
            !r.active,
            currentEpoch,
            reqId,
            requestId,
            msg.sender,
            value,
            r.linkFeePerNode
        );

        if (!r.active) {
            return;
        }

        int256[] storage answers = requestAnswers[reqId];
        answers.push(value);

        if (answers.length == minAnswers) {
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

    // Increment epoch and update feed value
    function startNewEpoch() private returns (uint256 newEpoch) {
        nextEpochValuesRequestCount = 0;
        nextEpochValuesLastRequest = 0;

        uint256 currentEpochPositiveOpenPnl = gToken
            .currentEpochPositiveOpenPnl();

        // If all responses arrived, use mean, otherwise it means we forced a new epoch,
        // so as a safety we use the last epoch value
        int256 newEpochOpenPnl = nextEpochValues.length >= requestsCount
            ? average(nextEpochValues)
            : int256(currentEpochPositiveOpenPnl);

        uint256 finalNewEpochPositiveOpenPnl = gToken.updateAccPnlPerTokenUsed(
            currentEpochPositiveOpenPnl,
            newEpochOpenPnl > 0 ? uint256(newEpochOpenPnl) : 0
        );

        newEpoch = gToken.currentEpoch();

        emit NewEpoch(
            newEpoch,
            lastRequestId,
            nextEpochValues,
            newEpochOpenPnl,
            finalNewEpochPositiveOpenPnl
        );

        delete nextEpochValues;
    }

    // Median function
    function swap(
        int256[] memory array,
        uint256 i,
        uint256 j
    ) private pure {
        (array[i], array[j]) = (array[j], array[i]);
    }

    function sort(
        int256[] memory array,
        uint256 begin,
        uint256 end
    ) private pure {
        if (begin >= end) {
            return;
        }

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

    function median(int256[] memory array) private pure returns (int256) {
        sort(array, 0, array.length);

        return
            array.length % 2 == 0
                ? (array[array.length / 2 - 1] + array[array.length / 2]) / 2
                : array[array.length / 2];
    }

    // Average function
    function average(int256[] memory array) private pure returns (int256) {
        int256 sum;
        for (uint256 i; i < array.length; i++) {
            sum += array[i];
        }

        return sum / int256(array.length);
    }
}

