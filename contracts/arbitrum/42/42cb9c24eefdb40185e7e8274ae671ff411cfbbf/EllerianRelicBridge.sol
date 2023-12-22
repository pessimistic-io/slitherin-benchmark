// contracts/GameRelics.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IEllerianRelics.sol";
import "./ISignature.sol";

/** 
 * Tales of Elleria
*/
contract EllerianRelicBridge is Ownable {

  IEllerianRelics private relicsAbi;
  ISignature private signatureAbi;
  address private signerAddr;

  mapping(uint256 => bool) private _isProcessed;

  uint256 private withdrawCounter;
  uint256 private depositsCounter;


  /**
   * Links to our other contracts to get things working.
   */
  function SetAddresses(address _relicsAddr, address _signatureAddr, address _signerAddr) external onlyOwner {
    relicsAbi = IEllerianRelics(_relicsAddr);
    signatureAbi = ISignature(_signatureAddr);
    signerAddr = _signerAddr;
      
  }

  /**
  * Burns relic so they appear in your Elleria inventory.
  */
  function BridgeIntoGame(uint256[] memory _ids, uint256[] memory _amounts) external {
    relicsAbi.burnBatch(msg.sender, _ids, _amounts);
    emit RelicBridged(msg.sender, _ids, _amounts, ++depositsCounter);
  }
  
  /**
   * Counts the number of 
   * withdraw transactions.
  */
  function withdrawCount() external view returns (uint256) {
    return withdrawCounter;
  }

  /**
  * Mints relics from Elleria into your Metamask wallet.
  */
  function RetrieveFromGame(bytes[] memory _signatures, uint256[] memory _ids, uint256[] memory _amounts, uint256 _txnCount) external {
    require(!_isProcessed[_txnCount], "Duplicate TXN Count!");
    _isProcessed[_txnCount] = true;

    for (uint i = 0; i < _ids.length; i++) {
      require(signatureAbi.verify(signerAddr, msg.sender, _ids[i] * _amounts[i], "relicwithdrawal", _txnCount, _signatures[i]), "Invalid relic withdraw");
    }

    relicsAbi.mintBatch(msg.sender, _ids, _amounts);
    emit RelicRetrieved(msg.sender, _ids, _amounts, ++withdrawCounter);
  }

    event RelicBridged(address _from, uint256[] ids, uint256[] amounts, uint256 counter);
    event RelicRetrieved(address _from, uint256[] ids, uint256[] amounts, uint256 counter);
}
