pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./IERC20.sol";
import "./IERC721.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./IVRFHelper.sol";
import "./IEllerianHero.sol";
import "./ISignature.sol";
import "./IHeroBridge.sol";

/** 
 * Tales of Elleria
*/
contract EllerianHeroUpgradeable is Ownable {
  uint256[] private fail_probability = [0, 0, 0, 0, 10, 20, 25, 30, 35, 40, 50, 60, 60, 60, 60];
  uint256[] private upgrade_gold_cost = [0, 20000, 50000, 150000, 450000, 1000000, 2000000, 5000000, 10000000, 20000000, 50000000, 100000000, 100000000, 100000000, 100000000];
  uint256[] private upgrade_token_cost = [0, 0, 0, 0, 5, 50, 100, 500, 1000, 1000, 2000, 5000, 5000, 5000, 10000];
  uint256[] private experience_needed = [0, 0, 50, 150, 450, 1000, 2000, 3000, 4000, 8000, 10000, 12000, 14000, 16000, 50000];

  uint256[] private attributesRarity = [0, 250, 320];

  mapping(uint256 => uint256) private heroExperience;
  mapping(uint256 => uint256) private heroLevel;
  mapping(uint256 => string) private heroName;
  mapping (uint256 => bool) private isStaked;

  uint256 private nameChangeFee = (5000 * 10 ** 18);

  mapping (address => bool) private _approvedAddresses;
  
  // The hero's attributes.
  struct heroAttributes {
    uint256 str;          // Strength =     PHYSICAL ATK
    uint256 agi;          // Agility =      HIT RATE
    uint256 vit;          // Vitality =     HEALTH
    uint256 end;          // Endurance =    PHYSICAL DEFENSE
    uint256 intel;        // Intelligence = MAGIC ATK
    uint256 will;         // Will =         MAGIC DEFENSE
    uint256 total;        // Total Attributes 
    uint256 class;        // Class
    uint256 tokenid;      // Token ID
    uint256 summonedTime; // Time of Mint
  }

  mapping(uint256 => heroAttributes) private heroDetails;  // Keeps track of each hero's attributes.

  address private minterAddress;
  address private tokenAddress;
  address private goldAddress;
  address private feesAddress;
  address private signerAddr;
  IHeroBridge private heroBridgeAbi;
  ISignature private signatureAbi;
  IVRFHelper vrfAbi;
  
  /**
   * Adjust the attribute rarity threshold if required .
   */
  function SetAttributeRarity(uint256[] memory _attributes) external {
    require(_approvedAddresses[msg.sender], "17");

    attributesRarity = _attributes;

    emit AttributeRarityChange(msg.sender, _attributes);
  }

    
  /**
   * Allows the name change fee to be changed.
   */
  function SetNameChangeFee(uint256 _feeInWEI) external {
    require(_approvedAddresses[msg.sender], "17");
    nameChangeFee = _feeInWEI;

    emit RenamingFeeChange(msg.sender, _feeInWEI);
  }

  /**
   * Allows the different contracts to be linked.
   */
  function SetAddresses(address _minterAddress, address _goldAddress,  address _tokenAddress, 
  address _signatureAddr, address _feesAddress, address _vrfAddress, address _signerAddr,
  address _heroBridgeAddr) external onlyOwner {
      minterAddress = _minterAddress;
      goldAddress = _goldAddress;
      tokenAddress = _tokenAddress;
      feesAddress = _feesAddress;
      signerAddr = _signerAddr;

      heroBridgeAbi = IHeroBridge(_heroBridgeAddr);
      signatureAbi = ISignature(_signatureAddr);
      vrfAbi = IVRFHelper(_vrfAddress);
  }

  /**
    * Approves the specified addresses
    * for administrative functions.
    */
  function SetApprovedAddress(address _address, bool _allowed) public onlyOwner {
      _approvedAddresses[_address] = _allowed;
  }

  /**
    * Sets the upgrade costs and requirements.
    */
  function SetUpgradeRequirements(uint256[] memory _new_gold_costs_in_ether, uint256[] memory _new_token_costs_in_ether, uint256[] memory _new_chances) external onlyOwner {
    upgrade_gold_cost = _new_gold_costs_in_ether;
    upgrade_token_cost = _new_token_costs_in_ether;
    fail_probability = _new_chances;

    emit UpgradeRequirementsChanged(msg.sender, _new_gold_costs_in_ether, _new_token_costs_in_ether, _new_chances);
  }

  /**
    * Sets the requirements needed to level up.
    */
  function SetEXPRequiredForLevelUp(uint256[] memory _new_exp) external onlyOwner {
    experience_needed = _new_exp;
    emit ExpRequirementsChanged(msg.sender, _new_exp);
  }

  /**
    * Allows the hero's name to be changed.
    * Must be called directly from a wallet.
    */
  function SetHeroName(uint256 _tokenId, string memory _name) public {
    require(IERC721(minterAddress).ownerOf(_tokenId) == tx.origin, "22");
    heroName[_tokenId] = _name;

    IERC20(goldAddress).transferFrom(tx.origin, feesAddress, nameChangeFee);
    emit NameChange(msg.sender, _tokenId, _name);
  }

  /**
   * Changes the attributes and emits an event to
   * make transparent all attribute updates.
   */
  function UpdateAttributes(uint256 _tokenId, uint256 _str, uint256 _agi, uint256 _vit, uint256 _end, uint256 _intel, uint256 _will) external {
    require(_approvedAddresses[msg.sender], "21");

    heroDetails[_tokenId].str = _str;
    heroDetails[_tokenId].agi = _agi;
    heroDetails[_tokenId].vit = _vit;
    heroDetails[_tokenId].end = _end;
    heroDetails[_tokenId].intel = _intel;
    heroDetails[_tokenId].will = _will;
    heroDetails[_tokenId].total = _str + _agi + _vit + _end + _intel + _will;

    uint256 class = heroDetails[_tokenId].class;

    emit AttributeChange(msg.sender, _tokenId, _str, _agi, _vit, _end, _intel, _will, class);
  }

  /**
   * Gets the original owner of a specific hero.
   */
  function IsStaked(uint256 _tokenId) external view returns (bool) {
      return isStaked[_tokenId];
  }


  /**
   * Gets the attributes for a specific hero.
   */
  function GetHeroDetails(uint256 _tokenId) external view returns (uint256[9] memory) {
    return [heroDetails[_tokenId].str, heroDetails[_tokenId].agi, heroDetails[_tokenId].vit, 
    heroDetails[_tokenId].end, heroDetails[_tokenId].intel, heroDetails[_tokenId].will, 
    heroDetails[_tokenId].total, heroDetails[_tokenId].class, heroDetails[_tokenId].summonedTime];
  }

  /**
   * Gets only the class for a specific hero.
   */
  function GetHeroClass(uint256 _tokenId) external view returns (uint256) {
    return heroDetails[_tokenId].class;
  }

  /**
   * Gets only the level for a specific hero.
   */
  function GetHeroLevel(uint256 _tokenId) external view returns (uint256) {
    return heroLevel[_tokenId];
  }
  
  /**
   * Gets the upgrade cost for a specific level.
   */
  function GetUpgradeCost(uint256 _level) external view returns (uint256[2] memory) {
    return [upgrade_gold_cost[_level], upgrade_token_cost[_level]];
  }

  /**
   * Gets the upgrade cost for a specific hero.
   */
  function GetUpgradeCostFromTokenId(uint256 _tokenId) public view returns (uint256[2] memory) {
    return [upgrade_gold_cost[heroLevel[_tokenId]], upgrade_token_cost[heroLevel[_tokenId]]];
  }

  /**
   * Gets the experience a certain hero has.
   */
  function GetHeroExperience(uint256 _tokenId) external view returns (uint256[2] memory) {
    return [heroExperience[_tokenId], experience_needed[heroLevel[_tokenId]]];
  }
  
  /**
   * Resets a hero's experience to its starting point.
   */
  function ResetHeroExperience(uint256 _tokenId, uint256 _exp) external {
      require(_approvedAddresses[msg.sender], "18");
      heroExperience[_tokenId] = _exp;

      emit ExpChange(msg.sender, _tokenId, _exp);
  }

  /**
   * Gets the name for a specific hero.
   */
  function GetHeroName(uint256 _tokenId) external view returns (string memory) {
    return heroName[_tokenId];
  }

  /**
  * Gets the exp required to upgrade for a certain level.
  */
  function GetEXPRequiredForLevelUp(uint256 _level) external view returns (uint256) {
    return experience_needed[_level];
  }

  /**
    * Gets the probability to fail an upgrade for a certain level.
    */
  function GetFailProbability(uint256 _level) external view returns (uint256) {
    return fail_probability[_level];
  }

  /**
   * Adjust the attribute rarity threshold if required .
   */
  function GetAttributeRarity(uint256 _tokenId) external view returns (uint256) {
    uint256 _totalAttributes = heroDetails[_tokenId].total;

    if (_totalAttributes < attributesRarity[1])
      return 0;
    else if (_totalAttributes < attributesRarity[2])
      return 1;

    return 2;
  }

  /**
   * Rewards a certain hero with experience.
   */
  function UpdateHeroExperience(uint256 _tokenId, uint256 _exp) external {
    require(_approvedAddresses[msg.sender], "7");
    heroExperience[_tokenId] = heroExperience[_tokenId] + _exp;

    emit ExpChange(msg.sender, _tokenId, heroExperience[_tokenId]);
  }

  /**
   * Sets the level for a specific hero.
   * Emits an event so abuse can be tracked.
   */
  function SetHeroLevel (uint256 _tokenId, uint256 _level) external {
    require(_approvedAddresses[msg.sender], "17");
    heroLevel[_tokenId] = _level;

    emit LevelChange(msg.sender, _tokenId, _level, 0, 0);
  }

  /**
   * Synchronizes a hero's stats from Elleria
   * onto the blockchain.
   */
  function SynchronizeHero (bytes memory _signature, uint256[] memory _data) external {
    require (heroBridgeAbi.GetOwnerOfTokenId(_data[0]) == msg.sender, "22");
    // _data[0] = tokenId, [1] = str, [2] = agi, [3] = vit, [4] = end, [5] = int, [6] = will, [7] = total, [8] = class, [9] = level,
    // [10] = experience
    uint256 tokenId = _data[0];

    heroDetails[tokenId].str = _data[1];
    heroDetails[tokenId].agi = _data[2];
    heroDetails[tokenId].vit = _data[3];
    heroDetails[tokenId].end = _data[4];
    heroDetails[tokenId].intel = _data[5];
    heroDetails[tokenId].will = _data[6];
    heroDetails[tokenId].total = _data[7];
    heroDetails[tokenId].class = _data[8];

    heroLevel[tokenId] = _data[9];
    heroExperience[tokenId] = _data[10];

    emit AttributeChange(msg.sender, tokenId, _data[1], _data[2], _data[3], _data[4], _data[5],  _data[6], _data[8]);
    emit ExpChange(msg.sender, tokenId, _data[10]);
    emit LevelChange(msg.sender, tokenId, _data[9], 0, 0);
    require(signatureAbi.bigVerify(signerAddr, msg.sender, _data, _signature));
  }

  /**
    * Allows someone to attempt an upgrade on his hero.
    * Must be called directly from a wallet.
    */  
  function AttemptHeroUpgrade(uint256 _tokenId, uint256 _goldAmountInEther, uint256 _tokenAmountInEther) public {
      require (IERC721(minterAddress).ownerOf(_tokenId) == tx.origin, "22");
      require(msg.sender == tx.origin, "9");

      // Transfer $MEDALS
      uint256 correctAmount = _goldAmountInEther * 1e18;
      IERC20(goldAddress).transferFrom(tx.origin, feesAddress, correctAmount);

      // Transfer $ELLERIUM
      correctAmount = _tokenAmountInEther * 1e18;
      if (correctAmount > 0) {
      IERC20(tokenAddress).transferFrom(tx.origin, feesAddress, correctAmount);
      }

      // Attempts the upgrade.
      uint256 level = updateLevel(_tokenId, _goldAmountInEther, _tokenAmountInEther);

      emit Upgrade(msg.sender, _tokenId, level);
  }

  /**
    * Rolls a number to check if the upgrade succeeds.
  */
  function updateLevel(uint256 _tokenId, uint256 _goldAmountInEther, uint256 _tokenAmountInEther) internal returns (uint256) {
      uint256[2] memory UpgradeCosts = GetUpgradeCostFromTokenId(_tokenId);
      require(_goldAmountInEther == UpgradeCosts[0], "ERR4");
      require(_tokenAmountInEther == UpgradeCosts[1], "ERR5");
      require(heroExperience[_tokenId] >= experience_needed[heroLevel[_tokenId]], "ERR6");

      uint256 randomNumber = vrfAbi.GetVRF(_tokenId) % 100;
      if (randomNumber >= fail_probability[heroLevel[_tokenId]]) {
        heroLevel[_tokenId] = heroLevel[_tokenId] + 1;
        emit LevelChange(msg.sender, _tokenId, heroLevel[_tokenId], _goldAmountInEther, _tokenAmountInEther);
      }

      return heroLevel[_tokenId];
  }

  /**
    * Initializes the hero upon minting.
    */
  function initHero(uint256 _tokenId, uint256 _str, uint256 _agi, uint256 _vit, uint256 _end,
  uint256 _intel, uint256 _will, uint256 _total, uint256 _class) external {
    require(_approvedAddresses[msg.sender], "36");
    heroName[_tokenId] = "Hero";
    heroLevel[_tokenId] = 1;

    heroDetails[_tokenId] = heroAttributes({
      str: _str,
      agi: _agi, 
      vit: _vit,
      end: _end,
      intel: _intel,
      will: _will,
      total: _total,
      class: _class,
      tokenid: _tokenId,
      summonedTime: block.timestamp
      });

    emit AttributeChange(msg.sender, _tokenId, _str, _agi, _vit, _end, _intel, _will, _class);
  }

  /**
    * Locks the hero temporarily so he can perform in-game actions.
  */
  function Stake(uint256 _tokenId) external {
    require(_approvedAddresses[msg.sender], "36");
    isStaked[_tokenId] = true;
    emit Staked(_tokenId);
  }

 /**
  * Unlocks the hero.
  */
  function Unstake(uint256 _tokenId) external {
    require(_approvedAddresses[msg.sender], "36");
    isStaked[_tokenId] = false;
    emit Unstaked(_tokenId);
  }

  event Staked(uint256 tokenId);
  event Unstaked(uint256 tokenId);
  event AttributeRarityChange(address _from, uint256[] _newRarity);
  event RenamingFeeChange(address _from, uint256 _newFee);
  event UpgradeRequirementsChanged(address _from, uint256[] _new_gold_costs_in_ether, uint256[] _new_token_costs_in_ether, uint256[] _new_chances);
  event ExpRequirementsChanged(address _from, uint256[] _expRequirements);
  event NameChange(address _from, uint256 _tokenId, string _newName);
  event Upgrade(address _from, uint256 _tokenId, uint256 _level);
  event ExpChange(address _from, uint256 _tokenId, uint256 _exp);
  event LevelChange(address _from, uint256 _tokenId, uint256 _level, uint256 _gold, uint256 _token);
  event AttributeChange(address _from, uint256 _tokenId, uint256 _str, uint256 _agi, uint256 _vit, uint256 _end, uint256 _intel, uint256 _will, uint256 _class);
}
