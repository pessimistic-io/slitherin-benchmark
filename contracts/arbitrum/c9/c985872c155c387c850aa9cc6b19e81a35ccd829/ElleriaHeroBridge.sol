pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IERC721.sol";
import "./IEllerianHero.sol";
import "./IEllerianHeroUpgradeable.sol";
import "./ISignature.sol";

/** 
 * Tales of Elleria
*/
contract ElleriaHeroBridge is Ownable {

  mapping (uint256 => address) private originalOwners;

  //IEllerianHero private ellerianHeroAbi;
  address private heroAddress;
  IEllerianHeroUpgradeable private upgradeableAbi;
  ISignature private signatureAbi;
  address private signerAddr;

   /**
   * Gets the original owner of a specific hero.
   */
  function GetOwnerOfTokenId(uint256 _tokenId) external view returns (address) {
      return originalOwners[_tokenId];
  }

  /**
   * Links to our other contracts to get things working.
   */
  function SetAddresses(address _ellerianHeroAddr, address _upgradeableAddr, address _signatureAddr, address _signerAddr) external onlyOwner {
      //ellerianHeroAbi = IEllerianHero(_ellerianHeroAddr);
      heroAddress = _ellerianHeroAddr;
      upgradeableAbi = IEllerianHeroUpgradeable(_upgradeableAddr);
      signatureAbi = ISignature(_signatureAddr);
      signerAddr = _signerAddr;
      
  }

  /**
  * Sends a hero into Elleria (Metamask > Elleria)
  * Changed from transfer to https://www.erc721nes.org/.
  */
  function BridgeIntoGame(uint256[] memory _tokenIds) external {
    for (uint i = 0; i < _tokenIds.length; i++) {
        require(IERC721(heroAddress).ownerOf(_tokenIds[i]) == msg.sender, "SFF");
      //ellerianHeroAbi.safeTransferFrom(msg.sender, address(this), _tokenIds[i]);
        originalOwners[_tokenIds[i]] = msg.sender; // Keep track of the original owner so we can return them.
        upgradeableAbi.Stake(_tokenIds[i]);
    }
  }

  /**
  * Retrieves your hero out of Elleria (Elleria > Metamask)
  */
  function RetrieveFromGame(bytes memory _signature, uint256[] memory _tokenIds) external {
    uint256 tokenSum;
    for (uint i = 0; i < _tokenIds.length; i++) {
      require(msg.sender == originalOwners[_tokenIds[i]], "B1");
      //ellerianHeroAbi.safeTransferFrom(address(this), originalOwners[_tokenIds[i]], _tokenIds[i]);
      //delete originalOwners[_tokenIds[i]];
      upgradeableAbi.Unstake(_tokenIds[i]);
      tokenSum = _tokenIds[i] + tokenSum;
    }

    require(signatureAbi.verify(signerAddr, msg.sender, _tokenIds.length, "withdrawal", tokenSum, _signature), "Invalid withdraw");
  }


}
