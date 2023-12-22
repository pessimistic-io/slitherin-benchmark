pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IERC20.sol";
import "./ISignature.sol";
import "./IElleriumTokenERC20.sol";

/** 
 * Tales of Elleria
*/
contract ElleriaERC20Bridge is Ownable {

  ISignature private signatureAbi;
  address private signerAddr;

  IElleriumTokenERC20 private elleriumAbi;
  address private elleriumAddr;
  mapping(uint256 => bool) private _isProcessed;

  uint256 private withdrawCounter;
  uint256 private depositsCounter;
  
  /**
   * Counts the number of 
   * withdraw transactions.
  */
  function withdrawCount() external view returns (uint256) {
    return withdrawCounter;
  }

  /**
   * Sets references to the other contracts. 
   */
  function SetReferences(address _signatureAddr, address _signerAddr, address _elmAddr) external onlyOwner {
      signatureAbi = ISignature(_signatureAddr);
      signerAddr = _signerAddr;

      elleriumAbi = IElleriumTokenERC20(_elmAddr);
      elleriumAddr = _elmAddr;
  }

  /**
   * Allows someone to bridge ELM into Elleria for in-game usage.
   */
  function BridgeIntoGame(uint256 _amountInWEI, address _erc20Addr) external {
    IERC20(_erc20Addr).transferFrom(msg.sender, address(0), _amountInWEI);
    emit ERC20Deposit(msg.sender, _erc20Addr, _amountInWEI, ++depositsCounter);
  }


  /**
   * Allows someone to withdraw $ELLERIUM from Elleria (sent out from contract).
   */
  function RetrieveElleriumFromGame(bytes memory _signature, uint256 _amountInWEI, uint256 _txnCount) external {
    require(!_isProcessed[_txnCount], "Duplicate TXN Count!");

    elleriumAbi.mint(msg.sender, _amountInWEI);
    _isProcessed[_txnCount] = true;

    emit ERC20Withdraw(msg.sender, elleriumAddr, _amountInWEI, ++withdrawCounter);
    require(signatureAbi.verify(signerAddr, msg.sender, _amountInWEI, "elm withdrawal", _txnCount, _signature), "Invalid withdraw");
  }

  /**
    * Allows the owner to withdraw ERC20 tokens
    * from this contract.
    */
  function withdrawERC20(address _erc20Addr, address _recipient) external onlyOwner {
    IERC20(_erc20Addr).transfer(_recipient, IERC20(_erc20Addr).balanceOf(address(this)));
  }

  // Events
  event ERC20Deposit(address indexed sender, address indexed erc20Addr, uint256 value, uint256 counter);
  event ERC20Withdraw(address indexed recipient, address indexed erc20Addr, uint256 value, uint256 counter);
}
