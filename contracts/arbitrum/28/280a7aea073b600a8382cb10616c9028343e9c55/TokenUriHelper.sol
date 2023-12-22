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

    mapping (uint256 => bool) private isBugged;
    
    IEllerianHeroUpgradeable upgradeableAbi;  // Reference to the NFT's upgrade logic.

    constructor () {
        upgradeableAbi = IEllerianHeroUpgradeable(0x7A0D491469fb5D7D3aDbF186221891AfE3b5d028);

        classNames[1] = "Warrior";
        classNames[2] = "Assassin";
        classNames[3] = "Mage";
        classNames[4] = "Ranger";

        tokenUris[1][0] = "https://ipfs.moralis.io:2053/ipfs/QmXdUDFBCx3MfCMZK9nK3AeFayxCYi7SiKU4xz98MdMC49";
        tokenUris[1][1] = "https://ipfs.moralis.io:2053/ipfs/QmbXmaaWNFx8jK9DaxGF3x4Zj9RbTaRKQF3UkhuLfQLheG";
        tokenUris[1][2] = "https://ipfs.moralis.io:2053/ipfs/QmXB9VvdGXGu7gbmcKGamhJpTLYrtJFrtyeGf2YzgFHA3J";
        tokenUris[2][0] = "https://ipfs.moralis.io:2053/ipfs/QmVVGAmNvUgUhyLy3HPKmwbzCnRfjGrV9kjW1G6ALUZUNF";
        tokenUris[2][1] = "https://ipfs.moralis.io:2053/ipfs/Qmd66PRkYUWN78VUSzYyxmZeP4zLpC8Wroif3QNCyofvj7";
        tokenUris[2][2] = "https://ipfs.moralis.io:2053/ipfs/QmP8X5uSrp6D4HGCkQ7asTQAaRxsn2eVS4TcapEf5evk4f";
        tokenUris[3][0] = "https://ipfs.moralis.io:2053/ipfs/QmVWzYTi7pYBZcMrzoHJ82ucRxPxVyEUNPZDtjbewzhfEC";
        tokenUris[3][1] = "https://ipfs.moralis.io:2053/ipfs/QmQuAxvgQP9r8cuV8sJxrjA7ttZYb2UdM4JdC17PgWv29U";
        tokenUris[3][2] = "https://ipfs.moralis.io:2053/ipfs/QmVdphWGBK78DupEntsxDut2mks9ihitxzu21hkpQJGVQ8";
        tokenUris[4][0] = "https://ipfs.moralis.io:2053/ipfs/QmZZGVv1rHm6KQ5ng7ehT9Dd38wnSCFZD9tWFfKgRpyeMa";
        tokenUris[4][1] = "https://ipfs.moralis.io:2053/ipfs/QmSvcrDYijxrZ5Fpz97P3t2dChEnq2syNwLQ6qGZ2nDzKc";
        tokenUris[4][2] = "https://ipfs.moralis.io:2053/ipfs/QmWBudHCS6wcSeJTVbHSYPddnLaBGdPJbHynwYG95Ambs3";

        tokenUris[1][3] = "https://ipfs.moralis.io:2053/ipfs/QmdvJr2XjPoepJoxT8kH6RGJeuxopCpC2JahQfrtGATdkE";
        tokenUris[2][3] = "https://ipfs.moralis.io:2053/ipfs/QmdvJr2XjPoepJoxT8kH6RGJeuxopCpC2JahQfrtGATdkE";
        tokenUris[3][3] = "https://ipfs.moralis.io:2053/ipfs/QmdvJr2XjPoepJoxT8kH6RGJeuxopCpC2JahQfrtGATdkE";
        tokenUris[4][3] = "https://ipfs.moralis.io:2053/ipfs/QmdvJr2XjPoepJoxT8kH6RGJeuxopCpC2JahQfrtGATdkE";

        tokenUris[1][4] = "https://ipfs.moralis.io:2053/ipfs/QmafevGMgE4pTF1Z3UjL3PBm2SZqj3ZSK6Hue7iKte5Rk1";
        tokenUris[2][4] = "https://ipfs.moralis.io:2053/ipfs/QmafevGMgE4pTF1Z3UjL3PBm2SZqj3ZSK6Hue7iKte5Rk1";
        tokenUris[3][4] = "https://ipfs.moralis.io:2053/ipfs/QmafevGMgE4pTF1Z3UjL3PBm2SZqj3ZSK6Hue7iKte5Rk1";
        tokenUris[4][4] = "https://ipfs.moralis.io:2053/ipfs/QmafevGMgE4pTF1Z3UjL3PBm2SZqj3ZSK6Hue7iKte5Rk1";
    }

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

    function SetBuggedIndex(uint256[] memory indexes, bool isBug) external onlyOwner {
        for (uint256 i = 0; i < indexes.length; i++) {
            isBugged[indexes[i]] = isBug;
        }
    }

    function GetTokenUri(uint256 _tokenId) external view returns (string memory) {

        uint256 _class =  upgradeableAbi.GetHeroClass(_tokenId);
        uint256 _rarity = upgradeableAbi.GetAttributeRarity(_tokenId);
        
        // Check if affected by the rarity issue, and alter the rarity if so.
        if (isBugged[_tokenId]) {
            // From 0 = common, 1 = epic, 2 = legendary, 3 = jester, 4 = witch
            if (_rarity == 0) {
                _rarity = 3;
            } else ( _rarity = 4);
            
        }

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
