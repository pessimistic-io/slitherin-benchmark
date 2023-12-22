// SPDX-License-Identifier: MIT
// Metaline Contracts (Random.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Context.sol";

import "./IRandom.sol";

/**
 * @dev A random source contract provids `seedRand`, `sealedRand` and `oracleRand` methods
 */
contract RandomEvm is Context, AccessControl, IRandom {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // an auto increased number by each _seedRand call
    uint32 _nonce;

    // an auto increased number by each setSealed call
    uint32 _sealedNonce;

    // an random seed set by manager
    uint256 _randomSeed;

    // an auto increased number by each oracleRand call
    uint256 _orcacleReqIDSeed;

    // sealed random seed data structure
    struct RandomSeed {
        uint32 sealedNonce;
        uint256 sealedNumber;
        uint256 seed;
        uint256 h1;
    }

    mapping(uint256 => RandomSeed) _sealedRandom; // _encodeSealedKey(addr) => sealed random seed data structure
    mapping(uint256 => address) _oracleRandRequests; // oracle rand request id => caller address

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(ORACLE_ROLE, _msgSender());
    }

    /**
    * @dev check address is sealed, usually call by contract to check user seal status
    *
    * @param addr user addr
    * @return ture if user is sealed
    */
    function isSealed(address addr) external view returns (bool) {
        return _isSealedDirect(_encodeSealedKey(addr));
    }

    /**
    * @dev set random seed
    *
    * Requirements:
    * - caller must have `MANAGER_ROLE`
    *
    * @param s random seed
    */
    function setRandomSeed(uint256 s) external {
        require(hasRole(MANAGER_ROLE, _msgSender()),"not manager");

        _randomSeed = s;
    }

    /**
    * @dev set user sealed, usually call by contract to seal a user
    * this function will `_encodeSealedKey` by tx.orgin and `_msgSender`
    * if success call this function, then user can call `sealedRand`
    */
    function setSealed() external {

        require(block.number >= 100,"block is too small");
        
        uint256 sealedKey = _encodeSealedKey(tx.origin);
       
        require(!_isSealedDirect(sealedKey),"should not sealed");

        _sealedNonce++;

        RandomSeed storage rs = _sealedRandom[sealedKey];

        rs.sealedNumber = block.number + 1;
        rs.sealedNonce = _sealedNonce;
        rs.seed = _randomSeed;

        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(block.number, block.timestamp, _sealedNonce)
            )
        );
        uint32 n1 = uint32(seed % 100);
        rs.h1 = uint256(blockhash(block.number - n1));
    }

    /**
    * @dev seal rand and get a random number
    *
    * Requirements:
    * - caller must call `setSealed` first
    *
    * @return ret random number
    */
    function sealedRand() external returns (uint256 ret) {
        return _sealedRand();
    }

    /**
    * @dev input a seed and get a random number depends on seed
    *
    * @param inputSeed random seed
    * @return ret random number depends on seed
    */
    function seedRand(uint256 inputSeed) external returns (uint256 ret) {
        return _seedRand(inputSeed);
    }

    /**
    * @dev start an oracle rand, emit {OracleRandRequest}, call by contract
    * oracle service wait on {OracleRandRequest} event and call `fulfillOracleRand`
    *
    * Requirements:
    * - caller must implements `oracleRandResponse` of {IOracleRandComsumer}
    *
    * @return reqid is request id of oracle rand request
    */
    function oracleRand() external returns (uint256) {
        _orcacleReqIDSeed = _orcacleReqIDSeed + 1;
        uint256 reqid = _orcacleReqIDSeed;
        //console.log("[sol]reqid=",reqid);
        _oracleRandRequests[reqid] = _msgSender();

        emit OracleRandRequest(reqid, _msgSender());

        return reqid;
    }

    /**
    * @dev fulfill an oracle rand, emit {OracleRandResponse}
    * call by oracle when it get {OracleRandRequest}, feed with an random number
    *
    * Requirements:
    * - caller must have `ORACLE_ROLE`
    *
    * @param reqid request id of oracle rand request
    * @param randnum random number feed by oracle
    * @return rand number
    */
    function fulfillOracleRand(uint256 reqid, uint256 randnum) external returns (uint256 rand) {
        require(hasRole(ORACLE_ROLE, _msgSender()),"need oracle role");
        require(_oracleRandRequests[reqid] != address(0),"reqid not exist");

        rand = _seedRand(randnum);
        IOracleRandComsumer comsumer = IOracleRandComsumer(_oracleRandRequests[reqid]);
        comsumer.oracleRandResponse(reqid, rand);

        delete _oracleRandRequests[reqid];

        emit OracleRandResponse(reqid, rand, address(comsumer));

        return rand;
    }

    /**
    * @dev input index and random number, return with new random number depends on input
    * use chain blockhash as random array, we can fetch many random number with a seed in one transaction
    *
    * @param index a number increased by caller, make sure that we don't get same outcome
    * @param randomNum random number as seed
    * @return ret is new rand number
    */
    function nextRand(uint32 index, uint256 randomNum) external view returns(uint256 ret){
        uint256 n1 = (randomNum + index) % block.number;
        uint256 h1 = uint256(blockhash(n1));

        return uint256(
            keccak256(
                abi.encodePacked(index, n1, h1)
            )
        );
    }

    function _seedRand(uint256 inputSeed) internal returns (uint256 ret) {
        require(block.number >= 1000,"block.number need >=1000");

        uint256 seed = uint256(
            keccak256(abi.encodePacked(block.number, block.timestamp, inputSeed))
        );

        uint32 n1 = uint32(seed % 100);
            
        uint32 n2 = uint32(seed % 1000);

        uint256 h1 = uint256(blockhash(block.number - n1));
  
        uint256 h2 = uint256(blockhash(block.number - n2));

        _nonce++;
        uint256 v = uint256(
            keccak256(abi.encodePacked(_randomSeed, h1, h2, _nonce))
        );

        return v;
    }

    // addr usually be tx.origin
    function _encodeSealedKey(address addr) internal view returns (uint256 key) {
        return uint256(
            keccak256(
                abi.encodePacked(addr, _msgSender())
            )
        );
    }

    function _sealedRand() internal returns (uint256 ret) {
    
        uint256 sealedKey = _encodeSealedKey(tx.origin);
        bool v = _isSealedDirect(sealedKey);
        require(v == true,"should sealed");

        RandomSeed storage rs = _sealedRandom[sealedKey];

        uint256 h2 = uint256(blockhash(rs.sealedNumber));
        ret = uint256(
            keccak256(
                abi.encodePacked(
                    rs.seed,
                    rs.h1,
                    h2,
                    block.difficulty,
                    rs.sealedNonce
                )
            )
        );

        delete _sealedRandom[sealedKey];

        return ret;
    }

    function _isSealedDirect(uint256 sealedKey) internal view returns (bool){
        return _sealedRandom[sealedKey].sealedNumber != 0;
    }

}

