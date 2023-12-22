// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

/**AnirudhTodo
 * LogX pool parameters in this file
 * what should be our PRICE_PRECISION?
 * CUMULATIVE_DELTA_PRECISION
 * MAX_PRICE_DURATION
 * minBlockInterval - 0s
 * maxTimeDeviation - 3600s
 * maxPriceUpdateDelay - 3600s
 * spreadBasisPointsIfChainError - 500 => 5%
 * spreadBasisPointsIfInactive - 20 => 0.2%
 * maxDeviationBasisPoints - 1000 => 10%
 * priceDuration - 300
 * priceDataInterval - 60s*/
 

import "./IPriceFeed.sol";
import "./Governable.sol";
import "./IPositionRouter.sol";
import "./IPriceEvents.sol";
import "./IPyth.sol";
import "./PythStructs.sol";
import "./console.sol";


contract PriceFeed is IPriceFeed, Governable {

    uint256 maxAllowedDelay;
    address updater; 
    address pythContract;

    mapping(address => bytes32) tokenPriceIdMapping;
    mapping(bytes32 => PythStructs.Price) tokenPrices;
    address[] supportedTokens;

    constructor(uint _maxAllowedDelay, address _pythContract, address _updater){
        maxAllowedDelay = _maxAllowedDelay;
        pythContract = _pythContract;
        updater = _updater;
    }

    function getPriceOfToken(address _token) external override view returns(uint256){
        bytes32 priceId = tokenPriceIdMapping[_token];
        PythStructs.Price memory priceData = tokenPrices[priceId];
        validateData(priceData);
        return getFinalPrice(uint64(priceData.price), priceData.expo);
    }

    function getMaxAllowedDelat() external view returns(uint256){
        return maxAllowedDelay;
    }

    function getPriceId(address _token) external view returns(bytes32){
        return tokenPriceIdMapping[_token];
    }

    function getMaxPriceOfToken(address _token) external override view returns(uint256){
        bytes32 priceId = tokenPriceIdMapping[_token];
        PythStructs.Price memory priceData = tokenPrices[priceId];
        validateData(priceData);
        return getFinalPrice(uint64(priceData.price) + priceData.conf, priceData.expo);
    }

    function getMinPriceOfToken(address _token) external override view returns(uint256){
        bytes32 priceId = tokenPriceIdMapping[_token];
        PythStructs.Price memory priceData = tokenPrices[priceId];
        validateData(priceData);
        return getFinalPrice(uint64(priceData.price) - priceData.conf, priceData.expo); 
    }

    function validateData(PythStructs.Price memory _priceData) internal view {
        console.log(_priceData.publishTime);
        console.log(maxAllowedDelay);
        console.log(block.timestamp);
        require(_priceData.publishTime + maxAllowedDelay > block.timestamp , "PriceFeed: current price data not available!");
    }

    function setUpdater(address _updater) external onlyGov{
        updater = _updater;
    }

    function setPythContract(address _pythContract) external onlyGov{
        pythContract = _pythContract;
    }

    function setMaxAllowedDelay(uint256 _maxAllowedDelay) external onlyGov{
        maxAllowedDelay = _maxAllowedDelay;
    }

    function updateTokenIdMapping(address _token, bytes32 _priceId) external onlyGov{
        if(tokenPriceIdMapping[_token] != bytes32(0)){
            tokenPriceIdMapping[_token] = _priceId;
        }
        else{
            tokenPriceIdMapping[_token] = _priceId;
            supportedTokens.push(_token);
        }
    }

    modifier onlyUpdater(){
        require(msg.sender == updater, "PriceFeed: sender does not have entitlements to update price");
        _;
    }

    function getFinalPrice(uint64 price, int32 expo) internal pure returns(uint256){
        if(expo > 0){
            return price*(10 ** uint32(expo));
        }
        else{
            return price/(10 ** uint32(-1 * expo));
        }
    }

    function setPricesAndExecute(
        bytes[] calldata priceUpdateData,
        address _positionRouter,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions
    ) external payable onlyUpdater {
        uint fee = IPyth(pythContract).getUpdateFee(priceUpdateData);
        IPyth(pythContract).updatePriceFeeds{value: fee}(priceUpdateData);
        uint numPriceIds = supportedTokens.length;
        for(uint i=0;i<numPriceIds;i++){
            address currToken = supportedTokens[i];
            bytes32 currPriceId = tokenPriceIdMapping[currToken];
            PythStructs.Price memory price = IPyth(pythContract).getPrice(currPriceId);
            tokenPrices[currPriceId] = price;
        }
        IPositionRouter positionRouter = IPositionRouter(_positionRouter);

        positionRouter.executeIncreasePositions(_endIndexForIncreasePositions, payable(msg.sender));
        positionRouter.executeDecreasePositions(_endIndexForDecreasePositions, payable(msg.sender));
    }
}

