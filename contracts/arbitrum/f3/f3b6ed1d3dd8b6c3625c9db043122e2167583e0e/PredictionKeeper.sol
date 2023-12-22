// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";
import {Pausable} from "./Pausable.sol";
import {IERC20} from "./IERC20.sol";
import "./AutomationCompatibleInterface.sol";
import "./StreamsLookupCompatibleInterface.sol";
import "./IVerifierProxy.sol";
import "./IFeeManager.sol";
import "./IPrediction.sol";
import {Common} from "./Common.sol";

contract PredictionKeeper is AutomationCompatibleInterface, StreamsLookupCompatibleInterface, Ownable, Pausable {
    struct BasicReport {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint64 expiresAt; // Latest timestamp where the report can be verified on-chain
        int192 price; // DON consensus median price, carried to 8 decimal places
    }

    address public predictionContract;
    uint256 public maxAheadTime;
    uint256 public aheadTimeForCheckUpkeep;
    uint256 public aheadTimeForPerformUpkeep;
    string public feedID;
    address public forwarder;
    address public verifierProxy;

    event NewPredictionContract(address indexed predictionContract);
    event NewMaxAheadTime(uint256 time);
    event NewAheadTimeForCheckUpkeep(uint256 time);
    event NewAheadTimeForPerformUpkeep(uint256 time);
    event NewFeedID(string feedID);
    event NewForwarder(address indexed forwarder);
    event NewVerifierProxy(address indexed verifierProxy);

    constructor(
        address _predictionContract,
        uint256 _maxAheadTime,
        uint256 _aheadTimeForCheckUpkeep,
        uint256 _aheadTimeForPerformUpkeep,
        string memory _feedID,
        address _forwarder,
        address _verifierProxy
    ) {
        require(_predictionContract != address(0) && _verifierProxy != address(0), "Cannot be zero addresses");
        predictionContract = _predictionContract;
        maxAheadTime = _maxAheadTime;
        aheadTimeForCheckUpkeep = _aheadTimeForCheckUpkeep;
        aheadTimeForPerformUpkeep = _aheadTimeForPerformUpkeep;
        feedID = _feedID;
        forwarder = _forwarder;
        verifierProxy = _verifierProxy;
    }

    modifier onlyForwarder() {
        require(msg.sender == forwarder || forwarder == address(0), "Not forwarder");
        _;
    }

    // The logic is consistent with the following performUpkeep function, in order to make the code logic clearer.
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (!paused()) {
            // encode to send all to performUpkeep (thus on-chain)
            performData = checkData;

            bool genesisStartOnce = IPrediction(predictionContract).genesisStartOnce();
            bool genesisLockOnce = IPrediction(predictionContract).genesisLockOnce();
            bool paused = IPrediction(predictionContract).paused();
            uint256 currentEpoch = IPrediction(predictionContract).currentEpoch();
            uint256 bufferSeconds = IPrediction(predictionContract).bufferSeconds();
            IPrediction.Round memory round = IPrediction(predictionContract).rounds(currentEpoch);
            uint256 lockTimestamp = round.lockTimestamp;

            if (paused) {
                // need to unpause
                upkeepNeeded = true;
            } else {
                if (!genesisStartOnce) {
                    upkeepNeeded = true;
                } else if (!genesisLockOnce) {
                    // Too early for locking of round, skip current job (also means previous lockRound was successful)
                    if (lockTimestamp == 0 || block.timestamp + aheadTimeForCheckUpkeep < lockTimestamp) {} else if (
                        lockTimestamp != 0 && block.timestamp > (lockTimestamp + bufferSeconds)
                    ) {
                        // Too late to lock round, need to pause
                        upkeepNeeded = true;
                    } else {
                        // run genesisLockRound
                        // upkeepNeeded = true;
                        string[] memory feedIDs = new string[](1);
                        feedIDs[0] = feedID;
                        revert StreamsLookup("feedIDs", feedIDs, "timestamp", block.timestamp, checkData);
                    }
                } else {
                    if (block.timestamp + aheadTimeForCheckUpkeep > lockTimestamp) {
                        // Too early for end/lock/start of round, skip current job
                        if (
                            lockTimestamp == 0 || block.timestamp + aheadTimeForCheckUpkeep < lockTimestamp
                        ) {} else if (lockTimestamp != 0 && block.timestamp > (lockTimestamp + bufferSeconds)) {
                            // Too late to end round, need to pause
                            upkeepNeeded = true;
                        } else {
                            // run executeRound
                            // upkeepNeeded = true;
                            string[] memory feedIDs = new string[](1);
                            feedIDs[0] = feedID;
                            revert StreamsLookup("feedIDs", feedIDs, "timestamp", block.timestamp, checkData);
                        }
                    }
                }
            }
        }
    }

    function checkCallback(bytes[] memory values, bytes memory extraData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        return (true, abi.encode(values, extraData));
    }

    function performUpkeep(bytes calldata performData) external override onlyForwarder whenNotPaused {
        bool genesisStartOnce = IPrediction(predictionContract).genesisStartOnce();
        bool genesisLockOnce = IPrediction(predictionContract).genesisLockOnce();
        bool paused = IPrediction(predictionContract).paused();
        uint256 currentEpoch = IPrediction(predictionContract).currentEpoch();
        uint256 bufferSeconds = IPrediction(predictionContract).bufferSeconds();
        IPrediction.Round memory round = IPrediction(predictionContract).rounds(currentEpoch);
        uint256 lockTimestamp = round.lockTimestamp;
        if (paused) {
            // unpause operation
            IPrediction(predictionContract).unpause();
        } else {
            if (!genesisStartOnce) {
                IPrediction(predictionContract).genesisStartRound();
            } else if (!genesisLockOnce) {
                // Too early for locking of round, skip current job (also means previous lockRound was successful)
                if (lockTimestamp == 0 || block.timestamp + aheadTimeForPerformUpkeep < lockTimestamp) {} else if (
                    lockTimestamp != 0 && block.timestamp > (lockTimestamp + bufferSeconds)
                ) {
                    // Too late to lock round, need to pause
                    IPrediction(predictionContract).pause();
                } else {
                    (bytes[] memory prices, uint80 roundId) = abi.decode(performData, (bytes[], uint80));

                    int256 verifiedPrice = verify(prices, roundId);

                    // run genesisLockRound
                    IPrediction(predictionContract).genesisLockRound(roundId, verifiedPrice);
                }
            } else {
                if (block.timestamp + aheadTimeForPerformUpkeep > lockTimestamp) {
                    // Too early for end/lock/start of round, skip current job
                    if (lockTimestamp == 0 || block.timestamp + aheadTimeForPerformUpkeep < lockTimestamp) {} else if (
                        lockTimestamp != 0 && block.timestamp > (lockTimestamp + bufferSeconds)
                    ) {
                        // Too late to end round, need to pause
                        IPrediction(predictionContract).pause();
                    } else {
                        (bytes[] memory prices, uint80 roundId) = abi.decode(performData, (bytes[], uint80));

                        int256 verifiedPrice = verify(prices, roundId);

                        // run executeRound
                        IPrediction(predictionContract).executeRound(roundId, verifiedPrice);
                    }
                }
            }
        }
    }

    function verify(bytes[] memory prices, uint80 roundId) internal returns (int256 verifiedPrice) {
        require(
            uint256(roundId) > IPrediction(predictionContract).oracleLatestRoundId(),
            "Oracle update roundId must be larger than oracleLatestRoundId"
        );

        IFeeManager feeManager = IVerifierProxy(verifierProxy).s_feeManager();
        address rewardManagerAddress = feeManager.i_rewardManager();
        address feeTokenAddress = feeManager.i_nativeAddress();

        (Common.Asset memory fee, , ) = feeManager.getFeeAndReward(address(this), prices[0], feeTokenAddress);

        IERC20(feeTokenAddress).approve(rewardManagerAddress, fee.amount);

        bytes memory verifiedReportData = IVerifierProxy(verifierProxy).verify(prices[0], abi.encode(feeTokenAddress));

        BasicReport memory verifiedReport = abi.decode(verifiedReportData, (BasicReport));

        require(
            verifiedReport.observationsTimestamp >=
                block.timestamp - IPrediction(predictionContract).oracleUpdateAllowance(),
            "Oracle update exceeded max timestamp allowance"
        );

        verifiedPrice = verifiedReport.price;
    }

    function setPredictionContract(address _predictionContract) external onlyOwner {
        require(_predictionContract != address(0), "Cannot be zero address");
        predictionContract = _predictionContract;
        emit NewPredictionContract(_predictionContract);
    }

    function setMaxAheadTime(uint256 _time) external onlyOwner {
        maxAheadTime = _time;
        emit NewMaxAheadTime(_time);
    }

    function setAheadTimeForCheckUpkeep(uint256 _time) external onlyOwner {
        require(_time <= maxAheadTime, "aheadTimeForCheckUpkeep cannot be more than MaxAheadTime");
        aheadTimeForCheckUpkeep = _time;
        emit NewAheadTimeForCheckUpkeep(_time);
    }

    function setAheadTimeForPerformUpkeep(uint256 _time) external onlyOwner {
        require(_time <= maxAheadTime, "aheadTimeForPerformUpkeep cannot be more than MaxAheadTime");
        aheadTimeForPerformUpkeep = _time;
        emit NewAheadTimeForPerformUpkeep(_time);
    }

    function setFeedID(string calldata _feedID) external onlyOwner {
        feedID = _feedID;
        emit NewFeedID(_feedID);
    }

    function setForwarder(address _forwarder) external onlyOwner {
        // When forwarder is address(0), anyone can execute performUpkeep function
        forwarder = _forwarder;
        emit NewForwarder(_forwarder);
    }

    function setVerifierProxy(address _verifierProxy) external onlyOwner {
        require(_verifierProxy != address(0), "Cannot be zero address");
        verifierProxy = _verifierProxy;
        emit NewVerifierProxy(_verifierProxy);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

