pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IEllerianHeroUpgradeable.sol";
import "./Strings.sol";

/** 
 * Tales of Elleria
*/
contract TokenUriHelper is Ownable {
    using Strings for uint256;

    mapping (uint256 => mapping (uint256 => string)) private tokenUris;
    mapping (uint256 => string) private classNames;

    IEllerianHeroUpgradeable upgradeableAbi;  // Reference to the NFT's upgrade logic.

  /*
   * Link with other contracts necessary for this to function.
   */
  function SetAddresses(address _upgradeableAddr) external onlyOwner {
        upgradeableAbi = IEllerianHeroUpgradeable(_upgradeableAddr);
  }

    function SetUri(uint256 _class, uint256 _rarity, string memory _newUri) external onlyOwner {
        tokenUris[_class][_rarity] = _newUri;
    }

    function SetClassNames(uint256 _class, string memory _className) external onlyOwner {
        classNames[_class] = _className;
    }

    function GetTokenUri(uint256 _tokenId) external view returns (string memory) {

        uint256 _class =  upgradeableAbi.GetHeroClass(_tokenId);
        uint256 _rarity = upgradeableAbi.GetAttributeRarity(_tokenId);
        uint256[9] memory heroDetails = upgradeableAbi.GetHeroDetails(_tokenId);

        string memory stats =  string(abi.encodePacked(
            Strings.toString(heroDetails[0]),';',  
            Strings.toString(heroDetails[1]), ';', 
            Strings.toString(heroDetails[2]), ';', 
            Strings.toString(heroDetails[3]), ';', 
            Strings.toString(heroDetails[4]), ';', 
            Strings.toString(heroDetails[5]), ';', 
            Strings.toString(heroDetails[6]), ';', 
            Strings.toString(heroDetails[7]), ';',
            GetClassName(heroDetails[7]),';')
        );

        return string(abi.encodePacked(
            Strings.toString(_tokenId),';', // tokenId
            tokenUris[_class][_rarity],';', // image
            stats, // str, agi, vit, end, int, will, total, class id, class name
            Strings.toString(upgradeableAbi.GetHeroLevel(_tokenId)),';', // level
            Strings.toString(upgradeableAbi.GetHeroExperience(_tokenId)[0]),';', // exp
            Strings.toString(heroDetails[8]),';', // time summoned
            Strings.toString(_rarity),';', // rarity id
            Strings.toString(upgradeableAbi.IsStaked(_tokenId) ? 1 : 0)) // is staked?
        );
    }

    function GetClassName(uint256 _class) public view returns (string memory) {
        return classNames[_class];
    }
}
