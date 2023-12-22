// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./AccessControl.sol";
import "./ECDSA.sol";

import "./RealWorldAssetTether.sol";

/// @title OffchainTreasuryOracle
/// @author FluidFi & DeFi Bridge DAO - nic@fluidfi.ch, alexander@takasecurity.com
/// @notice An on chain ledger mirroring all inflows and outflows of the offchain
/// treasury.
contract OffchainTreasuryOracle is AccessControl {
  /**
  * @dev is allowed to update the offchainSigner and tokenContract
  */
  bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
  
  /**
  * @dev is allowed to call update()
  */
  bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");
  
  RealWorldAssetTether public tokenContract;
  
  /**
  * @dev will sign all the offchain provided txes to the update function
  *      so that we can be sure an oracle updater is posting valid txes
  */
  address public offchainSigner;
  
  /**
  * @dev stores the overall offchain treasury balance, according to mints and redeems
  */
  int256 public balance;

  /**
  * @dev keeps track of the CeFiTxHashes that have already been processed
  */
  mapping (bytes32 => bool) public processedCeFiTxIds;

  event TxAmountZero(bytes32 indexed cefiTxID);
  event TxInvalidSignature(bytes32 indexed cefiTxID);
  event TxAlreadyProcessed(bytes32 indexed cefiTxID);
  event Inflow(bytes32 indexed cefiTxID, uint amount, uint256 indexed chainID);
  event Outflow(bytes32 indexed cefiTxID, uint amount, uint256 indexed chainID);

  event UpdateOffchainSigner(address indexed signer);
  event UpdateTokenContract(address indexed addr);

  
  constructor(address _offchainSigner) {
    require(_offchainSigner != address(0), "_offchainSigner is 0x0");

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(ORACLE_ADMIN_ROLE, msg.sender);
    _setupRole(ORACLE_UPDATER_ROLE, msg.sender);
    
    offchainSigner = _offchainSigner;
  }

  /**
  * @dev hashes the data that is signed by the offchainSigner, so that we can validate the signature
  */
  function _hashSignedData(uint256 _amount, address _address, bytes32 _cefiTxID, uint256 _chainID) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(
      "\x19Ethereum Signed Message:\n32", 
      keccak256(abi.encodePacked(_amount, _address, _cefiTxID, _chainID))
    ));
  }
  
  function _absUint256(int256 _val) internal pure returns (uint256) {
    return _val < 0 ? uint256(-_val) : uint256(_val);
  }
  
  /**
  * @dev this struct+enum are used inside the update() function to prevent a 
  *      "Stack too deep, try removing local variables" error
  *      and to generally make the code more readable
  */
  enum TxType { mint, redeem }
  struct UpdateInfo {
    uint amount;
    address account;
    bytes32 cefiTxID;
    uint256 chainID;
    bytes signature;
    TxType txType;
  }
  
  /**
  * @dev called by oracle updaters to mint to recipients, or release a pending redeem, after a valid CeFi tx.
  *      all txes are individually signed by the offchainSigner, and validated in the below function
  */
  function update(
    int256[] calldata _amounts, 
    address[] calldata _addresses, 
    bytes32[] calldata _cefiTxIDs,
    uint256[] calldata _chainIDs,
    bytes[] calldata _signatures
  ) external onlyRole(ORACLE_UPDATER_ROLE) {
    require(
      _amounts.length == _addresses.length && 
      _amounts.length == _cefiTxIDs.length &&
      _amounts.length == _chainIDs.length &&
      _amounts.length == _signatures.length,
      "invalid arguments: same number of amounts, addresses, cefiTxIDs and signatures must be specified"
    );
    
    for(uint256 i = 0; i < _amounts.length; i++) {
      if(_amounts[i] == 0) {
        emit TxAmountZero(_cefiTxIDs[i]);
        continue;
      }      
      
      UpdateInfo memory ui = UpdateInfo({
        cefiTxID: _cefiTxIDs[i],
        amount: _absUint256(_amounts[i]),
        txType: _amounts[i] > 0 ? TxType.mint : TxType.redeem,
        account: _addresses[i],
        chainID: _chainIDs[i],
        signature: _signatures[i]
      });      
      
      if (processedCeFiTxIds[ui.cefiTxID]) {
        emit TxAlreadyProcessed(ui.cefiTxID);
        continue;
      }
      
      if (ECDSA.recover(_hashSignedData(ui.amount, ui.account, ui.cefiTxID, ui.chainID), ui.signature) != offchainSigner) {
        emit TxInvalidSignature(ui.cefiTxID);
        continue;
      }
      
      balance += _amounts[i];

      // Money In - mint if mint target is this chainID
      if(ui.txType == TxType.mint) { 
        if(ui.chainID == block.chainid) {
          bool success = tokenContract.mint(ui.account, ui.amount, ui.cefiTxID);
          if(!success) {
            balance -= _amounts[i]; // undo L:135
            continue;
          }
        }
        emit Inflow(ui.cefiTxID, ui.amount, ui.chainID); 
      } 
      // Money Out -> releasePending
      else { // ui.txType == TxType.redeem
        if(ui.chainID == block.chainid) {
          bool success = tokenContract.releasePendingRedeem(ui.account, ui.amount, ui.cefiTxID);
          if(!success) {
            balance -= _amounts[i]; // undo L:135
            continue;
          }
        }
        emit Outflow(ui.cefiTxID, ui.amount, ui.chainID); 
      }
      
      processedCeFiTxIds[ui.cefiTxID] = true;
    }
  }

  function updateOffchainSigner(address _offchainSigner) external onlyRole(ORACLE_ADMIN_ROLE) {
    require(_offchainSigner != address(0), "_offchainSigner is 0x0");
    require(_offchainSigner != offchainSigner, "_offchainSigner equals current");
    offchainSigner = _offchainSigner;
    emit UpdateOffchainSigner(_offchainSigner);
  }

  function updateTokenContract(address _tokenContract) external onlyRole(ORACLE_ADMIN_ROLE) {
    require(_tokenContract != address(0), "_tokenContract is 0x0");
    tokenContract = RealWorldAssetTether(_tokenContract);
    emit UpdateTokenContract(_tokenContract);
  }

  function getLatestAnswer() public view returns (int) {
    return balance;
  }
}
