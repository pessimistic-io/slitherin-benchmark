pragma solidity ^0.8.0;

import "./BaseACL.sol";
import "./EnumerableSet.sol";

abstract contract FarmingBaseACL is BaseACL {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    //roles => pool id whitelist
    EnumerableSet.UintSet farmPoolIdWhitelist;
    EnumerableSet.AddressSet farmPoolAddressWhitelist;

    //events
    event AddPoolAddressWhitelist(address indexed _poolAddress, address indexed user);
    event RemovePoolAddressWhitelist(address indexed _poolAddress, address indexed user);
    event AddPoolIdWhitelist(uint256 indexed _poolId, address indexed user);
    event RemovePoolIdWhitelist(uint256 indexed _poolId, address indexed user);

    constructor(address _owner, address _caller) BaseACL(_owner, _caller) {}

    function addPoolIds(uint256[] calldata _poolIds) public onlyOwner {
        for (uint256 i = 0; i < _poolIds.length; i++) {
            if (farmPoolIdWhitelist.add(_poolIds[i])) {
                emit AddPoolIdWhitelist(_poolIds[i], msg.sender);
            }
        }
    }

    function removePoolIds(uint256[] calldata _poolIds) public onlyOwner {
        for (uint256 i = 0; i < _poolIds.length; i++) {
            if (farmPoolIdWhitelist.remove(_poolIds[i])) {
                emit RemovePoolIdWhitelist(_poolIds[i], msg.sender);
            }
        }
    }

    function addPoolAddresses(address[] calldata _poolAddresses) public onlyOwner {
        for (uint256 i = 0; i < _poolAddresses.length; i++) {
            if (farmPoolAddressWhitelist.add(_poolAddresses[i])) {
                emit AddPoolAddressWhitelist(_poolAddresses[i], msg.sender);
            }
        }
    }

    function removePoolAddresses(address[] calldata _poolAddresses) public onlyOwner {
        for (uint256 i = 0; i < _poolAddresses.length; i++) {
            if (farmPoolAddressWhitelist.remove(_poolAddresses[i])) {
                emit RemovePoolAddressWhitelist(_poolAddresses[i], msg.sender);
            }
        }
    }

    function getPoolIdWhiteList() public view returns (uint256[] memory) {
        return farmPoolIdWhitelist.values();
    }

    function getPoolAddressWhiteList() public view returns (address[] memory) {
        return farmPoolAddressWhitelist.values();
    }

    function checkAllowPoolId(uint256 _poolId) internal view {
        require(farmPoolIdWhitelist.contains(_poolId), "pool id not allowed");
    }

    function checkAllowPoolAddress(address _poolAddress) internal view {
        require(farmPoolAddressWhitelist.contains(_poolAddress), "pool address not allowed");
    }
}

