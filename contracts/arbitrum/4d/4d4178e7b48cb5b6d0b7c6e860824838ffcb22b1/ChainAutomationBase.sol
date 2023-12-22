// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IAdminAxelarSender} from "./IAdminAxelarSender.sol";
import {IAdminChainlinkSender} from "./IAdminChainlinkSender.sol";
import {IAdminLayerZeroSender} from "./IAdminLayerZeroSender.sol";
import {IRainbowRoad} from "./IRainbowRoad.sol";

/**
 * Base automation for executing actions on other chains
 */
abstract contract ChainAutomationBase is ArcBaseWithRainbowRoad
{
    enum Providers {
        Axelar,
        Chainlink,
        LayerZero
    }
    
    address public axelarSender;
    address public chainlinkSender;
    address public layerZeroSender;
    
    uint256[] public chains;
    mapping(address => bool) public admins;
    mapping(address => bool) public authorized;
    mapping(uint256 => bool) public isActive;
    mapping(uint256 => Providers) public providers;
    
    mapping(uint256 => address) public axelarReceiver;
    mapping(uint256 => address) public chainlinkReceiver;
    mapping(uint256 => address) public layerZeroReceiver;
    
    mapping(uint256 => string) public axelarSelectorIds;
    mapping(uint256 => uint64) public chainlinkSelectorIds;
    mapping(uint256 => uint16) public layerZeroSelectorIds;
    
    error ChainIdDoesNotExist(uint256 chainId);
    error DuplicateChainId(uint256 chainId);
    error ReceiverNotSet(uint256 chainId, Providers provider);
    
    event ChainRunErrorProcessing(uint256 chainId, bool isActive);
    event ChainNotActive(uint256 chainId, bool isActive);
    event ChainRunSuccess(uint256 chainId, bool isActive, Providers provider);
    
    constructor(address _rainbowRoad) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        admins[msg.sender] = true;
        authorized[msg.sender] = true;
        
        axelarSender = address(0);
        chainlinkSender = address(0);
        layerZeroSender = address(0);
    }
    
    function chainIdExists(uint256 chainId) public view returns (bool)
    {
        for(uint i = 0; i < chains.length; i++) {
            if(chains[i] == chainId) {
                return true;
            }
        }
        
        return false;
    }
    
    function addChain(uint256 chainId, Providers provider, string calldata axelarChainSelectorId, uint64 chainlinkChainSelectorId, uint16 layerZeroChainSelectorId) external onlyAdmins
    {
        if(this.chainIdExists(chainId)) {
            revert DuplicateChainId({chainId: chainId});
        }
        
        chains.push(chainId);
        isActive[chainId] = true;
        providers[chainId] = provider;
        axelarSelectorIds[chainId] = axelarChainSelectorId;
        chainlinkSelectorIds[chainId] = chainlinkChainSelectorId;
        layerZeroSelectorIds[chainId] = layerZeroChainSelectorId;
    }
    
    function setProviders(uint256 chainId, Providers provider) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        providers[chainId] = provider;
    }
    
    function setAxelarReceiver(uint256 chainId, address receiver) external onlyAdmins
    {
        require(receiver != address(0), 'Receiver cannot be zero address');
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        axelarReceiver[chainId] = receiver;
    }
    
    function setChainlinkReceiver(uint256 chainId, address receiver) external onlyAdmins
    {
        require(receiver != address(0), 'Receiver cannot be zero address');
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        chainlinkReceiver[chainId] = receiver;
    }
    
    function setLayerZeroReceiver(uint256 chainId, address receiver) external onlyAdmins
    {
        require(receiver != address(0), 'Receiver cannot be zero address');
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        layerZeroReceiver[chainId] = receiver;
    }
    
    function setAxelarSender(address sender) external onlyAdmins
    {
        require(sender != address(0), 'Sender cannot be zero address');
        axelarSender = sender;
    }
    
    function setChainlinkSender(address sender) external onlyAdmins
    {
        require(sender != address(0), 'Sender cannot be zero address');
        chainlinkSender = sender;
    }
    
    function setLayerZeroSender(address sender) external onlyAdmins
    {
        require(sender != address(0), 'Sender cannot be zero address');
        layerZeroSender = sender;
    }
    
    function setAxelarChainSelectorId(uint256 chainId, string calldata selectorId) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        axelarSelectorIds[chainId] = selectorId;
    }
    
    function setChainlinkChainSelectorId(uint256 chainId, uint64 selectorId) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        chainlinkSelectorIds[chainId] = selectorId;
    }
    
    function setLayerZeroChainSelectorId(uint256 chainId, uint16 selectorId) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        layerZeroSelectorIds[chainId] = selectorId;
    }
    
    function enableAdmin(address admin) external onlyOwner
    {
        require(admin != address(0), 'Admin cannot be zero address');
        require(!admins[admin], 'Admin is enabled');
        admins[admin] = true;
    }
    
    function disableAdmin(address admin) external onlyOwner
    {
        require(admin != address(0), 'Admin cannot be zero address');
        require(admins[admin], 'Admin is disabled');
        admins[admin] = false;
    }
    
    function enableAuthorized(address _authorized) external onlyOwner
    {
        require(_authorized != address(0), 'Authorized cannot be zero address');
        require(!authorized[_authorized], 'Authorized is enabled');
        authorized[_authorized] = true;
    }
    
    function disableAuthorized(address _authorized) external onlyOwner
    {
        require(_authorized != address(0), 'Authorized cannot be zero address');
        require(authorized[_authorized], 'Admin is disabled');
        authorized[_authorized] = false;
    }
    
    function enableChain(uint256 chainId) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        require(!isActive[chainId], 'Chain already enabled');
        
        isActive[chainId] = true;
    }
    
    function disableChain(uint256 chainId) external onlyAdmins
    {
        if(!this.chainIdExists(chainId)) {
            revert ChainIdDoesNotExist({chainId: chainId});
        }
        
        require(isActive[chainId], 'Chain already disabled');
        
        isActive[chainId] = false;
    }
    
    function runForChains() external virtual onlyAuthorized
    {
        for(uint256 i = 0; i < chains.length; i++) {
            try this.runForChain(chains[i]) {
                
            } catch {
                emit ChainRunErrorProcessing(chains[i], isActive[chains[i]]);
            }
        }
    }
    
    function runForChain(uint256 chainId) public virtual;
    
    function run(uint256 chainId, string memory action, bytes memory payload) public onlyAuthorized
    {
        if(isActive[chainId]) {
            
            Providers provider = providers[chainId];
            
            IERC20(address(rainbowRoad.arc())).approve(address(rainbowRoad), rainbowRoad.sendFee());
            
            address receiver;
            if(provider == Providers.Axelar) {
                
                receiver = axelarReceiver[chainId];
                if(receiver == address(0)) {
                    revert ReceiverNotSet({chainId: chainId, provider: provider});
                }
                
                IAdminAxelarSender(axelarSender).send(
                    axelarSelectorIds[chainId], 
                    receiver,
                    action, 
                    payload
                );
            } else if(provider == Providers.Chainlink) {
                
                receiver = chainlinkReceiver[chainId];
                if(receiver == address(0)) {
                    revert ReceiverNotSet({chainId: chainId, provider: provider});
                }
                
                IAdminChainlinkSender(chainlinkSender).send(
                    chainlinkSelectorIds[chainId], 
                    receiver,
                    action, 
                    payload
                );
            } else {
                
                receiver = layerZeroReceiver[chainId];
                if(receiver == address(0)) {
                    revert ReceiverNotSet({chainId: chainId, provider: provider});
                }
                
                IAdminLayerZeroSender(layerZeroSender).send(
                    layerZeroSelectorIds[chainId], 
                    receiver,
                    action, 
                    payload
                );
            }

            emit ChainRunSuccess(chainId, isActive[chainId], provider);
        } else {
            emit ChainNotActive(chainId, isActive[chainId]);
        }
    }
    
    /// @dev Only calls from the enabled admins are accepted.
    modifier onlyAdmins() 
    {
        require(admins[msg.sender], 'Invalid admin');
        _;
    }
    
    /// @dev Only calls from the authorized are accepted.
    modifier onlyAuthorized() 
    {
        require(authorized[msg.sender], "Not authorized");
        _;
    }
}
