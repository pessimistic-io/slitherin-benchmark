// SPDX-License-Identifier: MIT
// Mateline Contracts (MBRandomSourceBase.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Context.sol";

import "./Random.sol";
import "./RandomPoolLib.sol";

struct MBContentMinter1155Info {
    address addr;
    uint256[] tokenIds;
    uint256[] tokenValues;
}
struct MBContentMinterNftInfo {
    address addr;
    uint256[] tokenIds;
}

abstract contract MBRandomSourceBase is 
    Context, 
    AccessControl
{
    using RandomPoolLib for RandomPoolLib.RandomPool;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant RANDOM_ROLE = keccak256("RANDOM_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct NFTRandPool{
        bool exist;
        RandomPoolLib.RandomPool randPool;
    }

    Random _rand;
    mapping(uint32 => NFTRandPool)    _randPools; // poolID => nft data random pools
    mapping(uint32 => uint32[])       _mbRandomSets; // mystery type => poolID array

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(RANDOM_ROLE, _msgSender());
    }

    function setRandSource(address randAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()));

        _rand = Random(randAddr);
    }

    function getRandSource() external view returns(address) {
        // require(hasRole(MANAGER_ROLE, _msgSender()));
        return address(_rand);
    }
    function _addPool(uint32 poolID, RandomPoolLib.RandomSet[] memory randSetArray) internal {
        NFTRandPool storage rp = _randPools[poolID];

        rp.exist = true;
        for(uint i=0; i<randSetArray.length; ++i){
            rp.randPool.pool.push(randSetArray[i]);
        }

        rp.randPool.initRandomPool();
    }

    function addPool(uint32 poolID, RandomPoolLib.RandomSet[] memory randSetArray) external {
        require(hasRole(MANAGER_ROLE, _msgSender()),"not a manager");
        require(!_randPools[poolID].exist,"rand pool already exist");

        _addPool(poolID, randSetArray);
    }

    function modifyPool(uint32 poolID, RandomPoolLib.RandomSet[] memory randSetArray) external {
        require(hasRole(MANAGER_ROLE, _msgSender()),"not a manager");
        require(_randPools[poolID].exist,"rand pool not exist");

        NFTRandPool storage rp = _randPools[poolID];

        delete rp.randPool.pool;

        for(uint i=0; i<randSetArray.length; ++i){
            rp.randPool.pool.push(randSetArray[i]);
        }

        rp.randPool.initRandomPool();
    }

    function removePool(uint32 poolID) external {
        require(hasRole(MANAGER_ROLE, _msgSender()),"not a manager");
        require(_randPools[poolID].exist, "rand pool not exist");

        delete _randPools[poolID];
    }

    function getPool(uint32 poolID) public view returns(NFTRandPool memory) {
        require(_randPools[poolID].exist, "rand pool not exist");

        return _randPools[poolID];
    }

    function hasPool(uint32 poolID) external view returns(bool){
          return (_randPools[poolID].exist);
    }

    function setRandomSet(uint32 mbTypeID, uint32[] calldata poolIds) external {
        require(hasRole(MANAGER_ROLE, _msgSender()),"not a manager");
        delete _mbRandomSets[mbTypeID];
        uint32[] storage poolIDArray = _mbRandomSets[mbTypeID];
        for(uint i=0; i< poolIds.length; ++i){
            poolIDArray.push(poolIds[i]);
        }
    }
    function unsetRandomSet(uint32 mysteryTp) external {
        require(hasRole(MANAGER_ROLE, _msgSender()),"not a manager");

        delete _mbRandomSets[mysteryTp];
    }
    function getRandomSet(uint32 mysteryTp) external view returns(uint32[] memory poolIds) {
        return _mbRandomSets[mysteryTp];
    }
    
    function randomAndMint(uint256 r, uint32 mysteryTp, address to) virtual external 
        returns(MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts);

    function batchRandomAndMint(uint256 r, uint32 mysteryTp, address to, uint8 batchCount) virtual external 
        returns(MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts);
}
