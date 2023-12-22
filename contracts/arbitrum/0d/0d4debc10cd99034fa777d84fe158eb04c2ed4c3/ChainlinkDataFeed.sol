// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ArcBase} from "./ArcBase.sol";
import {IChainlinkDataFeed} from "./IChainlinkDataFeed.sol";

// ChainlinkDataFeed hold the information from data feeds to be consumed
contract ChainlinkDataFeed is ArcBase, IChainlinkDataFeed
{
    string public description;
    uint8 public decimals;
    uint80 public lastRoundId;
    uint256 public version;
     
    bool public checkAccess;
    bool public chargeAccessFee;
    uint256 public accessFee;
    
    address public authorized;
    mapping(uint80 => bytes) public rounds;
    mapping(address => bool) public accessList;

    event ChainlinkDataFeedUpdated(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    
    constructor(address _owner, address _authorized, string memory _description, uint8 _decimals, uint256 _version)
    {
        require(_owner != address(0), 'Owner address cannot be zero address');
        require(_authorized != address(0), 'Authorized address cannot be zero address');
        
        checkAccess = false;
        chargeAccessFee = false;
        accessFee = 1000e18;
        
        authorized = _authorized;
        description = _description;
        decimals = _decimals;
        version = _version;
        
        accessList[_owner] = true;
        
        _transferOwnership(_owner);
    }
    
    function enableCheckAccess() external onlyOwner
    {
        require(!checkAccess, 'Check access is enabled');
        checkAccess = true;
    }
    
    function disableCheckAccess() external onlyOwner
    {
        require(checkAccess, 'Check access is disabled');
        checkAccess = false;
    }
    
    function enableAccessFeeCharge() external onlyOwner
    {
        require(!chargeAccessFee, 'Access fee is enabled');
        chargeAccessFee = true;
    }
    
    function disableAccessFeeCharge() external onlyOwner
    {
        require(chargeAccessFee, 'Access fee is disabled');
        chargeAccessFee = false;
    }
    
    function enableAccess(address account) external onlyOwner
    {
        require(account != address(0), 'Account cannot be zero address');
        require(!accessList[account], 'Account access already enabled');
        
        accessList[account] = true;
    }
    
    function disableAccess(address account) external onlyOwner
    {
        require(account != address(0), 'Account cannot be zero address');
        require(accessList[account], 'Account access already disabled');
        
        accessList[account] = false;
    }
    
    function setAccessFee(uint256 _accessFee) external onlyOwner
    {
        accessFee = _accessFee;
    }
    
    function setAuthorized(address _authorizedAccount) external onlyOwner
    {
        require(_authorizedAccount != address(0), 'Authorized account cannot be zero address');
        authorized = _authorizedAccount;
    }
    
    function addRound(uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound) external onlyAuthorized
    {
        lastRoundId = _roundId;
        rounds[_roundId] = abi.encode(_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
        emit ChainlinkDataFeedUpdated(_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
    
    function getRoundData(uint80 _roundId) external view enforceAccessCheck returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        require(_roundId <= lastRoundId, 'Round Id not available');
        
        bytes memory roundData = rounds[_roundId];
        require(roundData.length != 0, 'No data for round Id');
        
        return abi.decode(roundData, (uint80, int256, uint256, uint256, uint80));
    }

    function latestRoundData() external view enforceAccessCheck returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return abi.decode(rounds[lastRoundId], (uint80, int256, uint256, uint256, uint80));
    }
    
    /// @dev Only calls from the valid callers are accepted when checking for access.
    modifier enforceAccessCheck() 
    {
        if(checkAccess) {
            require(accessList[msg.sender], "Access denied");
        }
        _;
    }
    
    /// @dev Only calls from the authorized are accepted.
    modifier onlyAuthorized() 
    {
        require(authorized == msg.sender, "Not authorized");
        _;
    }
}
