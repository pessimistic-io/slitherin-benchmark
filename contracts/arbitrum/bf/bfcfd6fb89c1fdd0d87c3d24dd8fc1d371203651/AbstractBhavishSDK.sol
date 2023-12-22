// SPDX-License-Identifier: BSD-4-Clause

pragma solidity ^0.8.13;

import { IBhavishSDK } from "./IBhavishSDK.sol";
import { IBhavishPrediction } from "./IBhavishPrediction.sol";
import { Address } from "./Address.sol";
import { AccessControl } from "./AccessControl.sol";
import { BaseRelayRecipient } from "./BaseRelayRecipient.sol";
import { DateTimeLibrary } from "./DateTimeLibrary.sol";

abstract contract AbstractBhavishSDK is IBhavishSDK, BaseRelayRecipient, AccessControl {
    using Address for address;

    mapping(bytes32 => mapping(bytes32 => IBhavishPrediction)) public predictionMap;
    mapping(IBhavishPrediction => bool) public activePredictionMap;
    uint256 public decimals = 3;
    mapping(bytes32 => bool) public usersForTheMonth;
    // Month -> Amount
    mapping(uint256 => uint256) public totalWeeklyPremiumCollected;
    mapping(uint256 => uint256) public totalMonthlyPremiumCollected;
    mapping(uint256 => uint256) public totalYearlyPremiumCollected;
    mapping(uint256 => uint256) public totalBhavishAllocated;
    // Address -> Month -> Amount
    mapping(address => mapping(uint256 => uint256)) public premiumCollected;
    mapping(address => bool) public validContracts;

    /**
     * @dev minimum gasless bet amount
     */
    uint256 public override minimumGaslessBetAmount = 0.1 ether;

    modifier onlyAdmin(address _address) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _address), "SDK: caller has no access to the method");
        _;
    }

    /**
     * @notice Add funds
     */
    receive() external payable {}

    function addPredictionMarket(
        IBhavishPrediction[] memory _bhavishPrediction,
        bytes32[] memory _underlying,
        bytes32[] memory _strike
    ) external onlyAdmin(msg.sender) {
        require(_bhavishPrediction.length == _underlying.length, "Invalid array arguments passed");
        require(_strike.length == _underlying.length, "Invalid array arguments passed");
        for (uint256 i = 0; i < _bhavishPrediction.length; i++) {
            predictionMap[_underlying[i]][_strike[i]] = _bhavishPrediction[i];
            require(!activePredictionMap[_bhavishPrediction[i]], "Prediction Market is already active");
            activePredictionMap[_bhavishPrediction[i]] = true;
        }
    }

    function updatePredictionMarket(
        IBhavishPrediction _bhavishPrediction,
        bytes32 _underlying,
        bytes32 _strike
    ) external onlyAdmin(msg.sender) {
        require(address(predictionMap[_underlying][_strike]) != address(0), "Prediction market doesn't exist");
        predictionMap[_underlying][_strike] = _bhavishPrediction;
        activePredictionMap[_bhavishPrediction] = true;
    }

    function removePredictionMarket(IBhavishPrediction _bhavishPrediction) external onlyAdmin(msg.sender) {
        require(activePredictionMap[_bhavishPrediction], "Prediction market is not in active state");
        activePredictionMap[_bhavishPrediction] = false;
    }

    function setTrustedForwarder(address forwarderAddress) public onlyAdmin(msg.sender) {
        require(forwarderAddress != address(0), "SDK: Forwarder Address cannot be 0");
        trustedForwarder.push(forwarderAddress);
    }

    function removeTrustedForwarder(address forwarderAddress) public onlyAdmin(msg.sender) {
        bool found = false;
        uint256 i;
        for (i = 0; i < trustedForwarder.length; i++) {
            if (trustedForwarder[i] == forwarderAddress) {
                found = true;
                break;
            }
        }
        if (found) {
            trustedForwarder[i] = trustedForwarder[trustedForwarder.length - 1];
            trustedForwarder.pop();
        }
    }

    function versionRecipient() external view virtual override returns (string memory) {
        return "1";
    }

    function _populateProviderInfo(address _provider, uint256 _predAmt) internal {
        (, uint256 month, uint256 year, uint256 week) = DateTimeLibrary.getAll(block.timestamp);

        if (!usersForTheMonth[keccak256(abi.encode(_provider, month))]) {
            usersForTheMonth[keccak256(abi.encode(_provider, month))] = true;
            emit PredictionMarketProvider(month, _provider);
        }
        premiumCollected[_provider][month] += _predAmt;
        totalMonthlyPremiumCollected[month] += _predAmt;
        totalYearlyPremiumCollected[year] += _predAmt;
        totalWeeklyPremiumCollected[week] += _predAmt;
    }

    function setMinimumGaslessBetAmount(uint256 _amount) external onlyAdmin(msg.sender) {
        require(_amount >= 0.1 ether && _amount < 100 ether, "invalid minimum gasless premium");
        minimumGaslessBetAmount = _amount;
    }

    function _refundUsers(
        IBhavishPrediction bhavishPredict,
        uint256 roundId,
        address userAddress
    ) internal {
        bhavishPredict.refundUsers(roundId, userAddress);
    }

    function refundUsers(PredictionStruct memory _predStruct, uint256 roundId) external {
        _refundUsers(predictionMap[_predStruct.underlying][_predStruct.strike], roundId, msg.sender);
    }

    function refundUsersWithGasless(PredictionStruct memory _predStruct, uint256 roundId) external {
        IBhavishPrediction bhavishPrediction = predictionMap[_predStruct.underlying][_predStruct.strike];
        uint256[] memory roundArr = new uint256[](1);
        roundArr[0] = roundId;
        uint256 avgBetAmount = bhavishPrediction.getAverageBetAmount(roundArr, msgSender());

        require(avgBetAmount > minimumGaslessBetAmount, "Not eligible for gasless");

        _refundUsers(bhavishPrediction, roundId, msgSender());
    }

    function addContract(address _contract) external onlyAdmin(msg.sender) {
        require(_contract.isContract(), "invalid address");
        validContracts[_contract] = true;
    }

    function removeContract(address _contract) external onlyAdmin(msg.sender) {
        validContracts[_contract] = false;
    }
}

