// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "./Initializable.sol";

import {IERC20} from "./IERC20.sol";
import {IPyth} from "./IPyth.sol";
import {PythStructs} from "./PythStructs.sol";

import {IGambitTradingStorageV1} from "./IGambitTradingStorageV1.sol";
import {IGambitPairsStorageV1} from "./IGambitPairsStorageV1.sol";

import {IGambitCNGCollateral} from "./IGambitCNGCollateral.sol";

import "./GambitErrorsV1.sol";

/**
 * @notice This contract holds CNG as collateral to provide optimistic pyth price.
 *         "Optimistic" means that the price is not verified by pyth contract when consume.
 *
 *          1. price feeder "reports" optimistic price to process orders.
 *          2. anyone can "challenges" to the price with valid price update data.
 *          3. price feeder re-challenges (or "resolves") to the challenge with his own price update data.
 *              - if there is no valid re-challenge, challenger gets all CNG as reward.
 *              - if re-challenge is successful, the challanger gets no reward.
 *
 */
contract GambitCNGCollateral is Initializable, IGambitCNGCollateral {
    // Contracts (constant)
    IPyth public pyth;
    IGambitTradingStorageV1 public storageT;
    IERC20 public CNG;

    // Contracts (adjustable)
    // NOTHING

    // Params (constant)
    uint256 public constant MIN_THRESHOLD = 1000e18; // 1000 CNG
    uint256 public constant DURATION = 3 days; // duration to challenge, re-challenge, claim

    // Params (adjustable)
    uint256 public threshold;

    struct ReportedPrice {
        bytes32 priceId;
        address challenger; // address of the challenger
        uint64 challengedAt; // timestamp when the challenge is initiated
        bool resolved; // whether the re-challenge is successful or not
        bool finalized; // whether the challenge is finalized or not
        bool slashed; // whether the challenge is valid and collateral is slashed or not
        PythStructs.Price price; // reported price by price feeder
    }

    // orderId => ReportedPrice
    mapping(uint256 => ReportedPrice) public reportedPriceOf;

    uint256 public nReportedPrices;
    uint256[] public challengedOrderIds; // a list of all challenged orders. only push new id when challenged.
    uint256 public nFinalizedChallenges; // increased when re-challenge is successful.

    struct ClaimRequest {
        uint256 amount;
        uint256 requestedAt;
        uint256 nFinalizedChallenges;
        bool claimed;
    }
    ClaimRequest[] public claimRequests;

    modifier onlyGov() {
        if (msg.sender != storageT.gov()) {
            revert GambitErrorsV1.NotGov();
        }
        _;
    }

    modifier onlyPriceAggregator() {
        if (msg.sender != address(storageT.priceAggregator())) {
            revert GambitErrorsV1.NotAggregator();
        }
        _;
    }

    event ThresholdUpdated(uint256 threshold);

    event PriceReported(
        uint256 indexed orderId,
        bytes32 indexed priceId,
        PythStructs.Price price
    );

    event ChallengeInitiated(
        uint256 indexed orderId,
        bytes32 indexed priceId,
        address indexed challenger,
        PythStructs.Price price,
        uint256 challengedAt
    );

    event ChallengeFinalized(
        uint256 indexed orderId,
        address indexed challenger,
        bool slashed,
        uint256 reward
    );

    event ChallengeResolved(
        uint256 indexed orderId,
        bytes32 indexed priceId,
        address indexed resolver,
        PythStructs.Price price
    );

    event Pause(bool paused);
    event Done(bool done);

    event ClaimRequested(
        uint256 amount,
        uint256 nFinalizedChallenges,
        uint256 requestedAt
    );
    event Claimed(uint256 amount);

    function initialize(
        IPyth _pyth,
        IGambitTradingStorageV1 _storageT,
        IERC20 _CNG,
        uint256 _threshold
    ) external initializer {
        if (
            address(_pyth) == address(0) ||
            address(_storageT) == address(0) ||
            address(_CNG) == address(0)
        ) {
            revert GambitErrorsV1.ZeroAddress();
        }

        if (_threshold < MIN_THRESHOLD) {
            revert GambitErrorsV1.WrongParams();
        }

        pyth = _pyth;
        storageT = _storageT;
        CNG = _CNG;
        threshold = _threshold;
    }

    function updateThreshold(uint256 newThreshold) external onlyGov {
        if (newThreshold < MIN_THRESHOLD) revert GambitErrorsV1.WrongParams();

        threshold = newThreshold;

        emit ThresholdUpdated(newThreshold);
    }

    function nChallenges() external view returns (uint256) {
        return challengedOrderIds.length;
    }

    function active() public view returns (bool) {
        return CNG.balanceOf(address(this)) >= threshold;
    }

    function isReported(uint256 orderId) public view returns (bool) {
        return reportedPriceOf[orderId].price.publishTime != 0;
    }

    function reportPrice(
        uint256 orderId,
        uint256 pairIndex,
        PythStructs.Price memory price
    ) external onlyPriceAggregator {
        // throw if not enough CNG
        if (!active()) {
            revert GambitErrorsV1.InsufficientCNG();
        }

        if (isReported(orderId)) {
            revert GambitErrorsV1.AlreadyReported();
        }

        IGambitPairsStorageV1.Feed memory f = storageT
            .priceAggregator()
            .pairsStorage()
            .pairFeed(pairIndex);

        if (
            price.price <= 0 ||
            price.conf == 0 ||
            price.publishTime == 0 ||
            price.expo > 0
        ) {
            revert GambitErrorsV1.WrongParams();
        }

        // check priceId is valid
        PythStructs.Price memory unsafePrice = pyth.getPriceUnsafe(f.priceId1);
        require(unsafePrice.price != 0, "Invalid priceId");

        require(
            price.publishTime + DURATION > block.timestamp,
            "Unchallengable price"
        );

        ReportedPrice storage report = reportedPriceOf[orderId];
        report.priceId = f.priceId1;
        report.price = price;
        nReportedPrices++;

        emit PriceReported(orderId, f.priceId1, price);
    }

    function isChallenged(uint256 orderId) public view returns (bool) {
        return reportedPriceOf[orderId].challengedAt != 0;
    }

    function challengable(uint256 orderId) public view returns (bool) {
        return
            !isChallenged(orderId) &&
            reportedPriceOf[orderId].price.publishTime + DURATION >
            block.timestamp;
    }

    function challenge(
        uint256 orderId,
        bytes calldata priceUpdateData
    ) external payable {
        require(challengable(orderId), "Not challengable");

        ReportedPrice storage report = reportedPriceOf[orderId];

        PythStructs.PriceFeed[] memory priceFeeds = _parsePriceFeedUpdates(
            report,
            priceUpdateData
        );

        // check reported price data is different with given update data
        bool valid = false;
        PythStructs.Price memory challengedPrice;
        for (uint i = 0; i < priceFeeds.length && !valid; i++) {
            PythStructs.PriceFeed memory priceFeed = priceFeeds[i];
            if (priceFeed.price.publishTime == report.price.publishTime) {
                if (
                    priceFeed.price.price != report.price.price ||
                    priceFeed.price.conf != report.price.conf ||
                    priceFeed.price.expo != report.price.expo
                ) {
                    valid = true;
                    challengedPrice = priceFeed.price;
                }
            }
        }

        require(valid, "Invalid update data");

        if (valid) {
            report.challenger = msg.sender;
            report.challengedAt = uint64(block.timestamp);
            challengedOrderIds.push(orderId);

            emit ChallengeInitiated(
                orderId,
                report.priceId,
                msg.sender,
                challengedPrice,
                block.timestamp
            );
        }
    }

    function isResolved(uint256 orderId) public view returns (bool) {
        return reportedPriceOf[orderId].resolved;
    }

    function resolvable(uint256 orderId) public view returns (bool) {
        return
            !isResolved(orderId) &&
            isChallenged(orderId) &&
            reportedPriceOf[orderId].challengedAt + DURATION > block.timestamp;
    }

    function resolve(
        uint256 orderId,
        bytes calldata priceUpdateData
    ) external payable {
        require(resolvable(orderId), "Not resolvable");

        ReportedPrice storage report = reportedPriceOf[orderId];

        PythStructs.PriceFeed[] memory priceFeeds = _parsePriceFeedUpdates(
            report,
            priceUpdateData
        );

        bool valid = false;
        for (uint i = 0; i < priceFeeds.length && !valid; i++) {
            PythStructs.PriceFeed memory priceFeed = priceFeeds[i];
            if (priceFeed.price.publishTime == report.price.publishTime) {
                if (
                    priceFeed.price.price == report.price.price ||
                    priceFeed.price.conf == report.price.conf ||
                    priceFeed.price.expo == report.price.expo
                ) {
                    valid = true;
                }
            }
        }

        require(valid, "Invalid update data");

        report.resolved = true;
        emit ChallengeResolved(
            orderId,
            report.priceId,
            msg.sender,
            report.price
        );

        // also finalize the challenge
        finalize(orderId);
    }

    function isFinalized(uint256 orderId) public view returns (bool) {
        return reportedPriceOf[orderId].finalized;
    }

    function finalizable(uint256 orderId) public view returns (bool) {
        return
            !isFinalized(orderId) &&
            isChallenged(orderId) &&
            (isResolved(orderId) ||
                reportedPriceOf[orderId].challengedAt + DURATION <
                block.timestamp);
    }

    /**
     * @dev finalize challenge and slash collateral if the challenge is valid.
     */
    function finalize(uint256 orderId) public {
        require(finalizable(orderId), "Not finalizable");

        ReportedPrice storage report = reportedPriceOf[orderId];

        uint256 reward;
        if (!isResolved(orderId)) {
            // transfer all CNG to the challanger
            reward = CNG.balanceOf(address(this));
            report.slashed = true;
            CNG.transfer(report.challenger, reward);
        }

        report.finalized = true;
        nFinalizedChallenges++;

        emit ChallengeFinalized(
            orderId,
            report.challenger,
            report.slashed,
            reward
        );
    }

    function makeClaimRequest(uint256 amount) external onlyGov {
        if (amount > CNG.balanceOf(address(this))) {
            revert GambitErrorsV1.InsufficientCNG();
        }

        require(
            challengedOrderIds.length == nFinalizedChallenges,
            "Remaining challenges"
        );

        ClaimRequest memory request = ClaimRequest({
            amount: amount,
            requestedAt: block.timestamp,
            nFinalizedChallenges: nFinalizedChallenges,
            claimed: false
        });

        claimRequests.push(request);

        emit ClaimRequested(amount, nFinalizedChallenges, block.timestamp);
    }

    function claim(uint256 requestId) external onlyGov {
        require(
            challengedOrderIds.length == nFinalizedChallenges,
            "Remaining challenges"
        );

        ClaimRequest memory request = claimRequests[requestId];
        require(!request.claimed, "Already claimed");
        require(
            request.requestedAt + DURATION < block.timestamp,
            "Too early to claim"
        );
        require(
            request.nFinalizedChallenges == nFinalizedChallenges,
            "New challenge exists"
        );

        if (request.amount > CNG.balanceOf(address(this))) {
            revert GambitErrorsV1.InsufficientCNG();
        }

        request.claimed = true;

        emit Claimed(request.amount);

        CNG.transfer(storageT.gov(), request.amount);
    }

    function _parsePriceFeedUpdates(
        ReportedPrice storage report,
        bytes calldata priceUpdateData
    ) internal returns (PythStructs.PriceFeed[] memory priceFeeds) {
        bytes[] memory updateData = new bytes[](1);
        bytes32[] memory priceIds = new bytes32[](1);
        updateData[0] = priceUpdateData;
        priceIds[0] = report.priceId;

        uint256 updateFee = pyth.getUpdateFee(updateData);
        if (msg.value < updateFee) {
            revert GambitErrorsV1.InsufficientPythFee();
        }

        priceFeeds = pyth.parsePriceFeedUpdates{value: updateFee}(
            updateData,
            priceIds,
            uint64(report.price.publishTime - 1),
            uint64(report.price.publishTime + 1)
        );
    }
}

// Testing 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43 at 1701681420
// [2023-12-04T09:23:58.483Z] price=41638.30365211      , conf=16.10365211         , publishTime=1701681420
// [2023-12-04T09:27:32.119Z] price=41635.01            , conf=13.03213661         , publishTime=1701681420
// Price mismatch
// Conf mismatch

// Testing 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace at 1701687600
// [2023-12-04T11:06:55.791Z] on-chain price=2261.09909198  , conf=0.96038948, publishTime=1701687600 off-chain price=2261.09909198  , conf=0.96038948 1701687600
// [2023-12-04T11:13:24.677Z] on-chain price=2260.97634172  , conf=0.82404356, publishTime=1701687600 off-chain price=2260.97634172  , conf=0.82404356 1701687600

// Testing 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43 at 1701812760
// [2023-12-05T21:46:57.834Z] on-chain price=43951.73058056 , conf=16.83608787, publishTime=1701812760 off-chain price=43951.73058056 , conf=16.83608787 1701812760
// [2023-12-05T21:52:55.558Z] on-chain price=43951.81294029 , conf=18.41165225, publishTime=1701812760 off-chain price=43952.62       , conf=17.60459254 1701812760

// Testing 0x3fa4252848f9f0a1480be62745a4629d9eb1322aebab8a791e344b3b9c1adcf5 at 1701739440
// [2023-12-05T01:26:11.913Z] on-chain price=1.0905         , conf=0.000718  , publishTime=1701739440 off-chain price=1.0905         , conf=0.000718   1701739440
// [2023-12-05T01:30:58.529Z] on-chain price=1.09049164     , conf=0.00065523, publishTime=1701739440 off-chain price=1.0905         , conf=0.000718   1701739440

// Testing 0x3fa4252848f9f0a1480be62745a4629d9eb1322aebab8a791e344b3b9c1adcf5 at 1701738780
// [2023-12-05T01:16:54.161Z] on-chain price=1.1001615      , conf=0.0006614 , publishTime=1701738780 off-chain price=1.1001615      , conf=0.0006614  1701738780
// [2023-12-05T01:19:56.520Z] on-chain price=1.10023185     , conf=0.00056815, publishTime=1701738780 off-chain price=1.10023185     , conf=0.00056815 1701738780

// Testing 0x78d185a741d07edb3412b09008b7c5cfb9bbbd7d568bf00ba737b456ba171501 at 1701850200
// [2023-12-06T08:16:55.160Z] on-chain price=6.11584882     , conf=0.00596481, publishTime=1701850200 off-chain price=6.11584882     , conf=0.00596481 1701850200
// [2023-12-06T12:45:13.573Z] on-chain price=6.11587743     , conf=0.00665291, publishTime=1701850200 off-chain price=6.11587743     , conf=0.00665291 1701850200

