// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IArc} from "./IArc.sol";
import {IChainlinkDataFeed} from "./IChainlinkDataFeed.sol";
import {IChainlinkDataFeedFactory} from "./IChainlinkDataFeedFactory.sol";
import {IChainlinkDataFeedHandler} from "./IChainlinkDataFeedHandler.sol";

/**
 * Chainlink Data Feed Handler
 */
contract ChainlinkDataFeedHandler is ArcBaseWithRainbowRoad, IChainlinkDataFeedHandler
{   
    uint256 public whitelistingFee;
    bool public chargeWhitelistingFee;
    bool public burnWhitelistingFee;
    bool public openWhitelisting;
    
    IChainlinkDataFeedFactory public chainlinkDataFeedFactory;
    mapping(string => address) public dataFeedSources;
    mapping(string => address) public chainlinkDataFeeds;
    
    event DataFeedSourceWhitelisted(string dataFeedName, address dataFeedSourceAddress, uint256 timestamp);
    event ChainlinkDataFeedUpdatedSucccessfully(string dataFeedName, uint80 roundId, uint256 timestamp);
    event ChainlinkDataFeedUpdateSent(string dataFeedName, uint256 version, uint8 decimals, uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound, uint256 timestamp);
    
    constructor(address _rainbowRoad, address _chainlinkDataFeedFactory) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        whitelistingFee = 10000e18;
        chargeWhitelistingFee = true;
        burnWhitelistingFee = true;
        openWhitelisting = false;
        chainlinkDataFeedFactory = IChainlinkDataFeedFactory(_chainlinkDataFeedFactory);
    }
    
    function setChainlinkDataFeedFactory(address _chainlinkDataFeedFactory) external onlyOwner
    {
        require(_chainlinkDataFeedFactory != address(0), 'Chainlink Data Feed Factory cannot be zero address');
        chainlinkDataFeedFactory = IChainlinkDataFeedFactory(_chainlinkDataFeedFactory);
    }
    
    function setDataFeedSource(string calldata dataFeedName, address dataFeedSourceAddress) external onlyOwner
    {
        dataFeedSources[dataFeedName] = dataFeedSourceAddress;
    }
    
    function setChainlinkDataFeed(string calldata dataFeedName, address chainlinkDataFeedAddress) external onlyOwner
    {
        chainlinkDataFeeds[dataFeedName] = chainlinkDataFeedAddress;
    }
    
    function setWhitelistingFee(uint256 _fee) external onlyOwner
    {
        require(_fee > 0, 'Fee must be greater than zero');
        whitelistingFee = _fee;
    }
    
    function enableWhitelistingFeeCharge() external onlyOwner
    {
        require(!chargeWhitelistingFee, 'Charge whitelisting fee is enabled');
        chargeWhitelistingFee = true;
    }
    
    function disableWhitelistingFeeCharge() external onlyOwner
    {
        require(chargeWhitelistingFee, 'Charge whitelisting fee is disabled');
        chargeWhitelistingFee = false;
    }
    
    function enableOpenWhitelisting() external onlyOwner
    {
        require(!openWhitelisting, 'Open whitelisting is enabled');
        openWhitelisting = true;
    }
    
    function disableOpenWhitelisting() external onlyOwner
    {
        require(openWhitelisting, 'Open whitelisting is disabled');
        openWhitelisting = false;
    }
    
    function enableWhitelistingFeeBurn() external onlyOwner
    {
        require(!burnWhitelistingFee, 'Burn whitelisting fee is enabled');
        burnWhitelistingFee = true;
    }
    
    function disableWhitelistingFeeBurn() external onlyOwner
    {
        require(burnWhitelistingFee, 'Burn whitelisting fee is disabled');
        burnWhitelistingFee = false;
    }
    
    function whitelistDataFeedSource(string calldata dataFeedName, address dataFeedSourceAddress) external
    {
        require(openWhitelisting, 'Open whitelisting is disabled');
        require(dataFeedSourceAddress != address(0), 'Data Feed source address cannot be zero address');
        require(dataFeedSources[dataFeedName] == address(0), 'Data Feed name is already enabled');
        
        if(chargeWhitelistingFee) {
            IArc(rainbowRoad.arc()).transferFrom(msg.sender, address(this), whitelistingFee);
            
            uint256 teamFee = (rainbowRoad.teamRate() * whitelistingFee) / 1000;
            require(IArc(rainbowRoad.arc()).transfer(rainbowRoad.team(), teamFee));
            
            if(burnWhitelistingFee) {
                IArc(rainbowRoad.arc()).burn(whitelistingFee - teamFee);
            }
        }
        
        dataFeedSources[dataFeedName] = dataFeedSourceAddress;
        emit DataFeedSourceWhitelisted(dataFeedName, dataFeedSourceAddress, block.timestamp);
    }
    
    function encodePayload(string calldata dataFeedName) view external returns (bytes memory payload)
    {
        address dataFeedSourceAddress = dataFeedSources[dataFeedName];
        require(dataFeedSourceAddress != address(0), 'Data Feed source not found');
        
        AggregatorV3Interface dataFeed = AggregatorV3Interface(dataFeedSourceAddress);
        
        (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound) = dataFeed.latestRoundData();
        
        uint256 version = dataFeed.version();
        uint8 decimals = dataFeed.decimals();
        
        return abi.encode(dataFeedName, version, decimals, roundId, answer, startedAt, updatedAt, answeredInRound);
    }
    
    function handleSend(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused
    {
        require(target != address(0), 'Target cannot be zero address');
        require(payload.length != 0, 'Invalid payload');
        (string memory dataFeedName, uint256 version, uint8 decimals, uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound) = abi.decode(payload, (string, uint256, uint8, uint80, int, uint, uint, uint80));
        emit ChainlinkDataFeedUpdateSent(dataFeedName, version, decimals, roundId, answer, startedAt, updatedAt, answeredInRound, block.timestamp);
    }
    
    function handleReceive(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused
    {
        require(target != address(0), 'Target cannot be zero address');
        require(payload.length != 0, 'Invalid payload');
        
        (string memory dataFeedName, uint256 version, uint8 decimals, uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound) = abi.decode(payload, (string, uint256, uint8, uint80, int, uint, uint, uint80));
        
        if(chainlinkDataFeeds[dataFeedName] == address(0)) {
            chainlinkDataFeeds[dataFeedName] = chainlinkDataFeedFactory.createChainlinkDataFeed(owner(), address(this), dataFeedName, decimals, version);
        }
        
        IChainlinkDataFeed(chainlinkDataFeeds[dataFeedName]).addRound(roundId, answer, startedAt, updatedAt, answeredInRound);
        
        emit ChainlinkDataFeedUpdatedSucccessfully(dataFeedName, roundId, block.timestamp);
    }
}
