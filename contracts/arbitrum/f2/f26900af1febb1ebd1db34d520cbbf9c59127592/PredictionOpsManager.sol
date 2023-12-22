// SPDX-License-Identifier: BSD-4-Clause

pragma solidity ^0.8.13;

import "./IBhavishPrediction.sol";

import "./Ownable.sol";

contract PredictionOpsManager is Ownable {
    IBhavishPrediction[] public predictionMarkets;

    constructor(IBhavishPrediction[] memory _bhavishPrediction) {
        for (uint256 i = 0; i < _bhavishPrediction.length; i++) {
            setPredicitionMarket(_bhavishPrediction[i]);
        }
    }

    function setPredicitionMarket(IBhavishPrediction _bhavishPredicition) public onlyOwner {
        require(address(_bhavishPredicition) != address(0), "Invalid predicitions");

        predictionMarkets.push(_bhavishPredicition);
    }

    function removePredictionMarket(IBhavishPrediction _bhavishPrediction) public onlyOwner {
        require(address(_bhavishPrediction) != address(0), "Invalid predicitions");

        for (uint256 i = 0; i < predictionMarkets.length; i++) {
            if (predictionMarkets[i] == _bhavishPrediction) {
                predictionMarkets[i] = predictionMarkets[predictionMarkets.length - 1];
                predictionMarkets.pop();
                break;
            }
        }
    }

    /**
     * perform  task execution
     */
    function execute() public {
        for (uint256 i = 0; i < predictionMarkets.length; i++) {
            IBhavishPrediction.Round memory round = predictionMarkets[i].getCurrentRoundDetails();
            //We highly recommend revalidating the upkeep in the performUpkeep function
            if (block.timestamp > round.roundEndTimestamp && round.roundState != IBhavishPrediction.RoundState.ENDED) {
                predictionMarkets[i].executeRound();
            }
        }
    }

    /**
     *checks the pre condition before executing op task
     */
    function canPerformTask(uint256 _delay) external view returns (bool canPerform) {
        for (uint256 i = 0; i < predictionMarkets.length; i++) {
            IBhavishPrediction.Round memory round = predictionMarkets[i].getCurrentRoundDetails();

            canPerform =
                block.timestamp > round.roundEndTimestamp + _delay &&
                round.roundState != IBhavishPrediction.RoundState.ENDED;

            if (canPerform) break;
        }
    }
}

