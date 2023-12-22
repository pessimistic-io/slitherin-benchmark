

// SPDX-License-Identifier: MIT
// Metaline Contracts (IRandom.sol)

pragma solidity ^0.8.0;

interface IOracleRandComsumer {
    function oracleRandResponse(uint256 reqid, uint256 randnum) external;
}

/**
 * @dev A random source contract provids `seedRand`, `sealedRand` and `oracleRand` methods
 */
interface IRandom {
    /**
    * @dev emit when `oracleRand` called

    * @param reqid oracle rand request id
    * @param requestAddress caller address
    */
    event OracleRandRequest(uint256 reqid, address indexed requestAddress);

    /**
    * @dev emit when `fulfillOracleRand` called

    * @param reqid oracle rand request id
    * @param randnum random number feed to request caller
    * @param requestAddress `oracleRand` requrest caller address
    */
    event OracleRandResponse(uint256 reqid, uint256 randnum, address indexed requestAddress);


    /**
    * @dev check address is sealed, usually call by contract to check user seal status
    *
    * @param addr user addr
    * @return ture if user is sealed
    */
    function isSealed(address addr) external view returns (bool);

    /**
    * @dev set random seed
    *
    * Requirements:
    * - caller must have `MANAGER_ROLE`
    *
    * @param s random seed
    */
    function setRandomSeed(uint256 s) external;

    /**
    * @dev set user sealed, usually call by contract to seal a user
    * this function will `_encodeSealedKey` by tx.orgin and `_msgSender`
    * if success call this function, then user can call `sealedRand`
    */
    function setSealed() external;

    /**
    * @dev seal rand and get a random number
    *
    * Requirements:
    * - caller must call `setSealed` first
    *
    * @return ret random number
    */
    function sealedRand() external returns (uint256 ret);

    /**
    * @dev input a seed and get a random number depends on seed
    *
    * @param inputSeed random seed
    * @return ret random number depends on seed
    */
    function seedRand(uint256 inputSeed) external returns (uint256 ret);

    /**
    * @dev start an oracle rand, emit {OracleRandRequest}, call by contract
    * oracle service wait on {OracleRandRequest} event and call `fulfillOracleRand`
    *
    * Requirements:
    * - caller must implements `oracleRandResponse` of {IOracleRandComsumer}
    *
    * @return reqid is request id of oracle rand request
    */
    function oracleRand() external returns (uint256);

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
    function fulfillOracleRand(uint256 reqid, uint256 randnum) external returns (uint256 rand);

    /**
    * @dev input index and random number, return with new random number depends on input
    * use chain blockhash as random array, we can fetch many random number with a seed in one transaction
    *
    * @param index a number increased by caller, make sure that we don't get same outcome
    * @param randomNum random number as seed
    * @return ret is new rand number
    */
    function nextRand(uint32 index, uint256 randomNum) external view returns(uint256 ret);
}

