// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AbstractMarket.sol";
import "./PriceFeeder.sol";
import "./PythiaFactory.sol";


contract PriceFeedsMarket is AbstractMarket{

    uint256[5] outcomes;

    address priceFeedAddress;
    PriceFeeder priceFeeder;
    PythiaFactory pythiaFactory;

    constructor(
        address _factoryContractAddress,
        string memory _question,
        uint256[5] memory _outcomes,
        uint256 _numberOfOutcomes,
        uint256 _wageDeadline,
        uint256 _resolutionDate,
        address _priceFeedAddress,
        address _priceFeederAddress
    ) AbstractMarket(
        _question,
        _numberOfOutcomes,
        _wageDeadline,
        _resolutionDate
    )
    {
        outcomes = _outcomes;
        priceFeeder = PriceFeeder(_priceFeederAddress);
        pythiaFactory = PythiaFactory(_factoryContractAddress);
        priceFeedAddress = _priceFeedAddress;
    }

    function predict(bytes32 _encodedPrediction) external override{
        require(
            block.timestamp <= wageDeadline,
            "market is no longer active"
        );
        require(pythiaFactory.isUser(msg.sender), "user is not registered");
        require(
            predictions[msg.sender].predicted == false,
            "user has already predicted"
        );
        predictions[msg.sender].encodedPrediction = _encodedPrediction;
        predictions[msg.sender].predictionTimestamp = block.timestamp;
        predictions[msg.sender].predicted = true;
        //log prediction event
        pythiaFactory.logNewPrediction(
            msg.sender,
            address(this),
            _encodedPrediction,
            block.timestamp
        );
    }

    function resolve() external override returns(bool){
        require(
            block.timestamp > resolutionDate,
            "resolution date has not arrived yet"
        );
        answer = _getMarketOutcome();
        resolved = true;
        pythiaFactory.logMarketResolved(
            address(this)
        );
    }

    function _getMarketOutcome() public view override returns(uint256){
        unchecked {
            uint256 price = priceFeeder.getLatestPrice(priceFeedAddress);
            for(uint256 i = 0; i < numberOfOutcomes - 1; i++){
                if(price < outcomes[i]){
                    return i;
                }
            }
            return numberOfOutcomes - 1;
        }
    }
}
