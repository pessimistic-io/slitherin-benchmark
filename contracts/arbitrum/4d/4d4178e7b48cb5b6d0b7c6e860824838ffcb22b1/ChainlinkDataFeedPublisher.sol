// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Strings} from "./Strings.sol";
import {ChainAutomationBase} from "./ChainAutomationBase.sol";
import {IRainbowRoad} from "./IRainbowRoad.sol";
import {IChainlinkDataFeedHandler} from "./IChainlinkDataFeedHandler.sol";

/**
 * Automation to push Chainlink Dat Feed data to other chains
 */
contract ChainlinkDataFeedPublisher is ChainAutomationBase
{
    IChainlinkDataFeedHandler chainlinkDataFeedHandler;
    mapping(uint256 => mapping(string => bool)) public isDataFeedActive;
    mapping(uint256 => string[]) public chainsDataFeeds;
    
    error ChainDataFeedDoesNotExist(uint256 chainId, string dataFeedName);
    error DuplicateChainDataFeed(uint256 chainId, string dataFeedName);
    
    constructor(address _rainbowRoad, address _chainlinkDataFeedHandler) ChainAutomationBase(_rainbowRoad)
    {
        require(_chainlinkDataFeedHandler != address(0), 'Chainlink Data Feed Handler cannot be zero address');
        chainlinkDataFeedHandler = IChainlinkDataFeedHandler(_chainlinkDataFeedHandler);
        authorized[address(this)] = true;
    }
    
    function setChainlinkDataFeedHandler(address _chainlinkDataFeedHandler) external onlyAdmins
    {
        require(_chainlinkDataFeedHandler != address(0), 'Chainlink Data Feed Handler cannot be zero address');
        chainlinkDataFeedHandler = IChainlinkDataFeedHandler(_chainlinkDataFeedHandler);
    }
    
    function addChainDataFeed(uint256 chainId, string calldata dataFeedName) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        if(this.chainDataFeedExists(chainId, dataFeedName)) {
            revert DuplicateChainDataFeed({chainId: chainId, dataFeedName: dataFeedName});
        }
        
        chainsDataFeeds[chainId].push(dataFeedName);
        isDataFeedActive[chainId][dataFeedName] = true;
    }
    
    function chainDataFeedExists(uint256 chainId, string memory dataFeedName) public view returns (bool)
    {
        string[] memory chainDataFeeds = chainsDataFeeds[chainId];
        for(uint i = 0; i < chainDataFeeds.length; i++) {
            if(Strings.equal(chainDataFeeds[i], dataFeedName)) {
                return true;
            }
        }
        
        return false;
    }
    
    function enableChainDataFeed(uint256 chainId, string calldata dataFeedName) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        if(!this.chainDataFeedExists(chainId, dataFeedName)) {
            revert ChainDataFeedDoesNotExist({chainId: chainId, dataFeedName: dataFeedName});
        }
        
        require(!isDataFeedActive[chainId][dataFeedName], 'Data Feed for chain already enabled');
        
        isDataFeedActive[chainId][dataFeedName] = true;
    }
    
    function disableChainDataFeed(uint256 chainId, string calldata dataFeedName) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        if(!this.chainDataFeedExists(chainId, dataFeedName)) {
            revert ChainDataFeedDoesNotExist({chainId: chainId, dataFeedName: dataFeedName});
        }
        
        require(isDataFeedActive[chainId][dataFeedName], 'Data Feed for chain already disabled');
        
        isDataFeedActive[chainId][dataFeedName] = false;
    }
    
    function runForChain(uint256 chainId) public override onlyAuthorized
    {
        string[] memory chainDataFeeds = chainsDataFeeds[chainId];
        for(uint256 i = 0; i < chainDataFeeds.length; i++) {
            
            if(isDataFeedActive[chainId][chainDataFeeds[i]]) {
                bytes memory payload = chainlinkDataFeedHandler.encodePayload(chainDataFeeds[i]);
                try this.run(chainId, 'chainlink_data_feed', payload) {
                    
                } catch {
                    emit ChainRunErrorProcessing(chains[i], isActive[chains[i]]);
                }
            } else {
                
            }
        }
    }
}
