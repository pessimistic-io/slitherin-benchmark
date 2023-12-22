pragma solidity ^0.8.0;
//SPDX-License-Identifier: UNLICENSED

import "./ERC721.sol";
import "./IERC20.sol";
import "./IEllerianHeroUpgradeable.sol";
import "./IVRFHelper.sol";
import "./IHeroBridge.sol";

// Interface for Whitelist Verifier using Merkle Tree
contract IWhitelistVerifier {
  function verify(bytes32 leaf, bytes32[] memory proof) external view returns (bool) {}
} 

contract ITokenUriHelper {
  function GetTokenUri(uint256 _tokenId) external view returns (string memory) {}
  function GetClassName(uint256 _class) external view returns (string memory) {}
}




/** 
 * Tales of Elleria
*/
contract EllerianHero is ERC721 {


  uint256 private currentSupply;  // Keeps track of the current supply.
  bool private globalMintOpened;  // Can minting happen?

  // Variables to make the pre-sales go smoothly. 
  // Mint will be locked on deployment, and needs to be manually enabled by the owner.
  mapping (address => bool) private isWhitelisted;
  mapping (address => uint256) private presalesMinted;
  bool private requiresWhitelist;
  bool private presalesMintOpened;
  uint256 private mintCostInWEI;
  uint256 private maximumMintable;
  uint256 private maximumMintsPerWallet;

  // We define the initial minimum stats for minting.
  // Caters for different 'banners', for expansion, and for different options in the future.
  uint256[][] private minStats = [
  [0, 0, 0, 0, 0, 0],
  [20, 1, 10, 1, 1, 1],
  [10, 20, 1, 1, 1, 1],
  [1, 1, 1, 1, 20, 10],
  [20, 10, 1, 1, 1, 1]];

  // We define the initial maximum stats for minting.
  // Maximum stats cannot be adjusted after a class is added.
  uint256[][] private maxStats = [
  [0, 0, 0, 0, 0, 0],
  [100, 75, 90, 80, 50, 50],
  [90, 100, 75, 50, 50, 80],
  [50, 80, 50, 75, 100, 90],
  [100, 90, 75, 50, 50, 80]];

  // Keeps track of the main and secondary stats for each class.
  uint256[] private mainStatIndex = [ 0, 0, 1, 4, 0 ];
  uint256[] private subStatIndex = [ 0, 2, 0, 5, 1 ];

  // Keeps track of the possibilities of minting each class,
  // Can be adjusted for each banner during minting events, after presales, etc.
  // or to introduce legendary characters, exclusive banners, etc.
  uint256[][] private classPossibilities = [[0, 2500, 5000, 7500, 10000], 
  [0, 7000, 8000, 9000, 10000], [0, 1000, 2000, 3000, 10000]];

  uint256[] private maximumMintsForClass = [0, 0, 0, 0, 0]; // Allows certain classes to have a maximum mint cap for rarity.
  mapping(uint256 => uint256) private currentMintsForClass; // Keeps track of the number of mints.

  // Keeps track of admin addresses.
  mapping (address => bool) private _approvedAddresses;

  address private ownerAddress;             // The contract owner's address.
  address private tokenMinterAddress;       // Reference to the NFT's minting logic.

  IEllerianHeroUpgradeable upgradeableAbi;  // Reference to the NFT's upgrade logic.
  IVRFHelper vrfAbi;                        // Reference to the Randomizer.
  IWhitelistVerifier verifierAbi;           // Reference to the Whitelist
  ITokenUriHelper uriAbi;                   // Reference to the tokenUri handler.
  IHeroBridge bridgeAbi;                    // Reference to the ERC721 bridge.

  constructor() 
    ERC721("EllerianHeroes", "EllerianHeroes") {
      ownerAddress = msg.sender;
    }
    
    function _onlyOwner() private view {
      require(msg.sender == ownerAddress, "O");
    }

    modifier onlyOwner() {
      _onlyOwner();
      _;
    }


  /**
    * Returns the number of global remaining mints.
    */
  function GetRemainingMints() external view returns (uint256) {
    return maximumMintable - currentSupply;
  }

  /**
    * Returns the number of remaining wallet mints.
  */
  function GetRemainingPresalesMints() external view returns (uint256) {
    if ( presalesMinted[msg.sender] >= maximumMintsPerWallet)
      return 0;
      
    return maximumMintsPerWallet - presalesMinted[msg.sender];
  }
  
  /*
  * Custom tokenURI to allow for customisability.
  * Returns imageUri, 
  * str, agi, vit, end, int, wil, 
  * totalAttr, class name, summonedTime,
  * level
  * 
  */
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    return uriAbi.GetTokenUri(tokenId);
  }

  /**
    * Allows the ownership of the contract to be transferred to a safer multi-sig wallet once deployed.
    */ 
  function TransferOwnership(address _newOwner) external onlyOwner {
    require(_newOwner != address(0));
    ownerAddress = _newOwner;
  }

  /**
    * Allows presales minting variables to be adjusted.
    */
  function SetMintable(bool _presalesOpened, uint256 _newMintCostInWEI, uint256 _maxMints,  bool _requireWhitelist, uint256 _max) external onlyOwner {
    presalesMintOpened = _presalesOpened;
    requiresWhitelist = _requireWhitelist;
    mintCostInWEI = _newMintCostInWEI;
    maximumMintable = _max;
    maximumMintsPerWallet = _maxMints;
    globalMintOpened = false; // Locks the mint in case of accidents. To be manually enabled again.
  }

  /**
    * Allows the owner to add new classes. 
    * When a new class is added, minting will automatically be locked.
    */
  function AddNewClass(uint256[6] memory _new_class_min, uint256[6] memory _new_class_max, uint256 _main_stat, uint256 _sub_stat, uint256[][] memory _classPossibilities, uint256[] memory _maximumClassMints) external onlyOwner {
    minStats.push(_new_class_min);
    maxStats.push(_new_class_max);
    mainStatIndex.push(_main_stat);
    subStatIndex.push(_sub_stat);
    UpdateClassPossibilities(_classPossibilities, _maximumClassMints);
    globalMintOpened = false; // Locks the mint in case of accidents. Remember to re-open!
  }

  /*
   * Allows the owner to block or allow minting.
   */
  function SetGlobalMint(bool _allow) external onlyOwner {
    globalMintOpened = _allow;
  }

  /*
   * Allows the owner to modify the possibilities for getting different classes, as well as impose a limit on different classes.
   *  Classes 1-4 (the OG ones) are exempted from the limit.
   */
  function UpdateClassPossibilities(uint256[][] memory _classPossibilities, uint256[] memory _maximumClassMint) public onlyOwner {
    for (uint256 i = 0; i < _classPossibilities.length; i++) {
      require(_classPossibilities[i].length == maxStats.length, "12");
    }
    
    require(_maximumClassMint.length == maxStats.length, "12");
    classPossibilities = _classPossibilities;
    maximumMintsForClass = _maximumClassMint;
  }
 
  /*
   * Allows the owner to modify minimum stats for different events if necessary.
   */
  function SetRandomStatMinimums(uint256[][] memory _newMinStats) external onlyOwner {
    require(minStats.length == _newMinStats.length);
    minStats = _newMinStats;
  }

  /*
   * Link with other contracts necessary for this to function.
   */
  function SetAddresses(address _upgradeableAddr, address _tokenMinterAddr, address _vrfAddr, address _verifierAddr, address _uriAddr) external onlyOwner {
    tokenMinterAddress = _tokenMinterAddr;

    upgradeableAbi = IEllerianHeroUpgradeable(_upgradeableAddr);
    vrfAbi = IVRFHelper(_vrfAddr);
    verifierAbi = IWhitelistVerifier(_verifierAddr);
    uriAbi = ITokenUriHelper(_uriAddr);
  }

  /**
    * Allows approval of certain contracts
    * for transfers. (bridge, marketplace, staking)
    */
  function SetApprovedAddress(address _address, bool _allowed) public onlyOwner {
      _approvedAddresses[_address] = _allowed;
  }   

  /**
  *  Allows batch minting of Heroes! (for presales only).
  */
  function mintPresales (address _owner, uint256 _amount, uint256 _variant, bytes32[] memory _proof) public payable {
      require (currentSupply + _amount < maximumMintable + 1, "8");
      require (tx.origin == msg.sender, "9");
      require (msg.sender == _owner, "9");
      require (globalMintOpened, "20");
      require (presalesMintOpened, "11");
      require (presalesMinted[msg.sender] + _amount < maximumMintsPerWallet + 1, "39");
      require (msg.value == mintCostInWEI * _amount, "19");

      if (requiresWhitelist) {
        require (verifierAbi.verify(keccak256(abi.encode(_owner)), _proof), "13");
      }
      
      presalesMinted[msg.sender] = presalesMinted[msg.sender] + _amount;

      for (uint256 a = 0; a < _amount; a++) {
          uint256 id = currentSupply;
          _safeMint(msg.sender, id);
          _processMintedToken(id, _variant);
      }
  }

  /**
  * Allows the minting of NFTs using tokens.
  * This function must be called by a delegated minter contract.
  */
  function mintUsingToken(address _recipient, uint256 _amount, uint256 _variant) public {
    require (currentSupply + _amount < maximumMintable + 1, "8");
    require(tokenMinterAddress == msg.sender, "15");
    require (globalMintOpened, "20");

    for (uint256 a = 0; a < _amount; a++) {
          uint256 id = currentSupply;
          _safeMint(_recipient, id);
          _processMintedToken(id, _variant);
    }
  }
  
  /*
  * Allows the owner to airdrop NFTs for distributions/rewards/team.
  * Cannot airdrop exceeding maximum supply!
  */ 
  function airdrop (address _to, uint256 _amount, uint256 _variant) public onlyOwner {
    require( currentSupply + _amount < maximumMintable + 1, "8");
    for (uint256 a = 0; a < _amount; a++) {
        uint256 id = currentSupply;
        _safeMint(_to, id);
        _processMintedToken(id, _variant);
    }
  }

  function safeTransferFrom (address _from, address _to, uint256 _tokenId) public override {
    safeTransferFrom(_from, _to, _tokenId, "");
  }

  /* 
   * Do not allow transfers to non approved addresses.
   */
  function safeTransferFrom (address _from, address _to, uint256 _tokenId, bytes memory _data) public override {
    require(_isApprovedOrOwner(_msgSender(), _tokenId), "SFF");
    require(!upgradeableAbi.IsStaked(_tokenId), "41");

    if (_approvedAddresses[_from] || _approvedAddresses[_to]) {
    } else if (_to != address(0)) {
      // Reset experience for non-exempted addresses.
      upgradeableAbi.ResetHeroExperience(_tokenId, 0);
    }

    _safeTransfer(_from, _to, _tokenId, _data);
  }

  /* 
   * Allows burning and approval check for heroes.
   */
  function burn (uint256 _tokenId, bool _isBurnt) public {
    require(_isApprovedOrOwner(_msgSender(), _tokenId), "22");
    if (_isBurnt) {
      _burn(_tokenId);
    }
  }

  /* 
   * Allows the withdrawal of presale funds into the owner's wallet.
   * For fund allocation, refer to the whitepaper.
   */
  function withdraw() public onlyOwner {
    (bool success, ) = (msg.sender).call{value:address(this).balance}("");
    require(success, "2");
  }

  /* 
   * Internal function to generate stats. 
   * Owner must have enabled global minting.
   */
  function _processMintedToken(uint256 id, uint256 _variant) internal {

    uint256 randomClass = _getClass(id, _variant); // Base Classes = 1: Warrior, 2: Assassin, 3: Mage, 4: Ranger
    if (randomClass > 4 && (currentMintsForClass[randomClass] > maximumMintsForClass[randomClass])) {
      randomClass = (vrfAbi.GetVRF(id) % 4) + 1; 
    }

    uint256[6] memory placeholderStats = [uint256(0), 0, 0, 0, 0, 0];

    for (uint256 b = 0; b < 6; b++) {
      placeholderStats[b] = (vrfAbi.GetVRF(id * randomClass * b) % (maxStats[randomClass][b] - minStats[randomClass][b] + 1)) + minStats[randomClass][b];
    }
    
    upgradeableAbi.initHero(id, placeholderStats[0], placeholderStats[1], placeholderStats[2],
    placeholderStats[3],placeholderStats[4],placeholderStats[5],
    placeholderStats[0] + placeholderStats[1] + placeholderStats[2] + placeholderStats[3] + placeholderStats[4] + placeholderStats[5],
    randomClass);

    ++currentSupply;
    ++currentMintsForClass[randomClass];
  }

  /* 
   * Random function to allow weighted randomness for classes.
   * Will kick in when legendary/rare characters are introduced further into the game.
   */
  function _getClass(uint256 _seed, uint256 _variant) internal view returns (uint256) {
    uint256 classRandom = vrfAbi.GetVRF(_seed) % 10000;
    for (uint256 i = 0; i < classPossibilities[_variant].length; i++) {
      if (classRandom < classPossibilities[_variant][i])
        return i;
      }

      return classPossibilities[_variant].length - 1;
  }
}
