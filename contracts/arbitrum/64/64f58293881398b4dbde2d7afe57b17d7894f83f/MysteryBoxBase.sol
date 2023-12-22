// SPDX-License-Identifier: MIT
// Mateline Contracts (MysteryBoxBase.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";

import "./GasFeeCharger.sol";

import "./MysteryBox1155.sol";
import "./MBRandomSourceBase.sol";

abstract contract MysteryBoxBase is 
    Context, 
    Pausable, 
    AccessControl,
    IOracleRandComsumer
{
    using GasFeeCharger for GasFeeCharger.MethodExtraFees;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant RAND_ROLE = keccak256("RAND_ROLE");

    event OracleOpenMysteryBox(uint256 oracleRequestId, uint256 indexed mbTokenId, address indexed owner);
    event OpenMysteryBox(address indexed owner, uint256 indexed mbTokenId, MBContentMinter1155Info[] sfts, MBContentMinterNftInfo[] nfts);

    event BatchOracleOpenMysteryBox(uint256 oracleRequestId, uint256 indexed mbTokenId, address indexed owner, uint8 batchCount);
    event BatchOpenMysteryBox(address indexed owner, uint256 indexed mbTokenId, MBContentMinter1155Info[] sfts, MBContentMinterNftInfo[] nfts);

    struct UserData{
        address owner;
        uint32 randomType;
        uint32 mysteryType;
        uint8 count;
        uint256 tokenId;
    }
    
    MysteryBox1155 public _mb1155;
    
    mapping(uint32=>address) _randomSources; // random type => random source
    mapping(uint256 => UserData) public _oracleUserData; // indexed by oracle request id

    // Method extra fee
    // For smart contract method which need extra transaction by other service, we define extra fee
    // extra fee charge by method call tx with `value` paramter, and send to target service wallet address
    GasFeeCharger.MethodExtraFees _methodExtraFees;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(RAND_ROLE, _msgSender());
    }

    function getName() external virtual returns(string memory);

    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MysteryBox: must have pauser role to pause");
        _pause();
    }
    
    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MysteryBox: must have pauser role to unpause");
        _unpause();
    }

    function setNftAddress(address nftAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "MysteryBox: must have manager role to manage");
        _mb1155 = MysteryBox1155(nftAddr);
    }

    function getNftAddress() external view returns(address) {
        return address(_mb1155);
    }

    function setRandomSource(uint32 randomType, address randomSrc) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "MysteryBox: must have manager role to manage");
        _randomSources[randomType] = randomSrc;
    }

    function getRandomSource(uint32 randomType) external view returns(address){
        return _randomSources[randomType];
    }

    /**
    * @dev set smart contract method invoke by transaction with extra fee
    *
    * Requirements:
    * - caller must have `MANAGER_ROLE`
    *
    * @param methodKey key of which method need extra fee
    * @param value extra fee value
    * @param target target address where extra fee goes to
    */
    function setMethodExtraFee(uint8 methodKey, uint256 value, address target) external {
        require(
            hasRole(MANAGER_ROLE, _msgSender()),
            "MysteryBox: must have manager role"
        );

        _methodExtraFees.setMethodExtraFee(methodKey, value, target);
    }

    /**
    * @dev cancel smart contract method invoke by transaction with extra fee
    *
    * Requirements:
    * - caller must have `MANAGER_ROLE`
    *
    * @param methodKey key of which method need cancel extra fee
    */
    function removeMethodExtraFee(uint8 methodKey) external {
        require(
            hasRole(MANAGER_ROLE, _msgSender()),
            "MysteryBox: must have manager role"
        );

        _methodExtraFees.removeMethodExtraFee(methodKey);
    }

    /**
    * @dev open mystery box, emit {OracleOpenMysteryBox}
    * call `oracleRand` in {Random} of address from `getRandSource` in {MBRandomSource}
    * send a oracle random request and emit {OracleRandRequest}
    *
    * Extrafees:
    * - `oracleOpenMysteryBox` call need charge extra fee for `fulfillRandom` in {Random} call by oracle service
    * - methodKey = 1, extra gas fee = 0.0013 with tx.value needed
    *
    * Requirements:
    * - caller must out side contract, not from contract
    * - caller must owner of `tokenId` in {MysteryBox1155}
    * - contract not paused
    *
    * @param tokenId token id of {MysteryBox1155}, if succeed, token will be burned
    */
    function oracleOpenMysteryBox(uint256 tokenId) external payable whenNotPaused {
        require(tx.origin == _msgSender(), "MysteryBox: only for outside account");
        require(_mb1155.balanceOf(_msgSender(), tokenId) >= 1, "MysteryBox: insufficient mb");

        // check mb 1155 type
        uint32 randomType = (uint32)((tokenId >> 32) & 0xffffffff);
        address randSrcAddr = _randomSources[randomType];
        require(randSrcAddr != address(0), "MysteryBox: not a mystry box");
        
        address rndAddr = MBRandomSourceBase(randSrcAddr).getRandSource();
        require(rndAddr != address(0), "MysteryBox: rand address wrong");

        _methodExtraFees.chargeMethodExtraFee(1); // charge oracleOpenMysteryBox extra fee

        _mb1155.burn(_msgSender(), tokenId, 1);

        uint256 reqid = Random(rndAddr).oracleRand();

        UserData storage userData = _oracleUserData[reqid];
        userData.owner = _msgSender();
        userData.randomType = randomType;
        userData.mysteryType = (uint32)(tokenId & 0xffffffff);
        userData.tokenId = tokenId;
        userData.count = 1;
        
        emit OracleOpenMysteryBox(reqid, tokenId, _msgSender());
    }

    /**
    * @dev batch open mystery box, emit {BatchOracleOpenMysteryBox}
    * call `oracleRand` in {Random} of address from `getRandSource` in {MBRandomSource}
    * send a oracle random request and emit {OracleRandRequest}
    *
    * Extrafees:
    * - `batchOracleOpenMysteryBox` call need charge extra fee for `fulfillRandom` in {Random} call by oracle service
    * - methodKey = 2, extra gas fee = 0.0065 with tx.value needed
    *
    * Requirements:
    * - caller must out side contract, not from contract
    * - caller must owner of `tokenId` in {MysteryBox1155}
    * - contract not paused
    *
    * @param tokenId token id of {MysteryBox1155}, if succeed, token will be burned
    */
    function batchOracleOpenMysteryBox(uint256 tokenId, uint8 batchCount) external payable whenNotPaused {
        require(tx.origin == _msgSender(), "MysteryBox: only for outside account");
        require(batchCount <= 10, "MysteryBox: batch count overflow");
        require(_mb1155.balanceOf(_msgSender(), tokenId) >= batchCount, "MysteryBox: insufficient mb");

        // check mb 1155 type
        uint32 randomType = (uint32)((tokenId >> 32) & 0xffffffff);
        address randSrcAddr = _randomSources[randomType];
        require(randSrcAddr != address(0), "MysteryBox: not a mystry box");
        
        address rndAddr = MBRandomSourceBase(randSrcAddr).getRandSource();
        require(rndAddr != address(0), "MysteryBox: rand address wrong");

        _methodExtraFees.chargeMethodExtraFee(2); // charge batchOracleOpenMysteryBox extra fee

        _mb1155.burn(_msgSender(), tokenId, batchCount);
        
        uint256 reqid = Random(rndAddr).oracleRand();

        UserData storage userData = _oracleUserData[reqid];
        userData.owner = _msgSender();
        userData.randomType = randomType;
        userData.mysteryType = (uint32)(tokenId & 0xffffffff);
        userData.tokenId = tokenId;
        userData.count = batchCount;
        
        emit BatchOracleOpenMysteryBox(reqid, tokenId, _msgSender(), batchCount);
    }

    // call back from random contract which triger by service call {fulfillOracleRand} function
    function oracleRandResponse(uint256 reqid, uint256 randnum) override external {
        require(hasRole(RAND_ROLE, _msgSender()), "MysteryBox: must have rand role");

        UserData storage userData = _oracleUserData[reqid];

        require(userData.owner != address(0), "MysteryBox: nftdata owner not exist");

        address randSrcAddr = _randomSources[userData.randomType];
        require(randSrcAddr != address(0), "MysteryBox: not a mystry box");

        if(userData.count > 1) {

            (MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts) 
                = MBRandomSourceBase(randSrcAddr).batchRandomAndMint(randnum, userData.mysteryType, userData.owner, userData.count);

            emit BatchOpenMysteryBox(userData.owner, userData.tokenId, sfts, nfts);
        }
        else {
            (MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts) 
                = MBRandomSourceBase(randSrcAddr).randomAndMint(randnum, userData.mysteryType, userData.owner);

            emit OpenMysteryBox(userData.owner, userData.tokenId, sfts, nfts);
        }

        delete _oracleUserData[reqid];
    }
    
}
