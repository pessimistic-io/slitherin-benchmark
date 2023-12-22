// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC721Enumerable.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./Counters.sol";
import "./AccessControl.sol";


interface IConnector {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract CryptoGenerals is
    ERC721Enumerable,
    ReentrancyGuard,
    Ownable,
    AccessControl 
{
    using Counters for Counters.Counter;
    Counters.Counter _tokenIds;

    // Create a new role identifier for the minter role
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");


    // Castles contract
    address public castlesAddress = 0x71f5C328241fC3e03A8c79eDCD510037802D369c;
    IConnector public castlesContract = IConnector(castlesAddress);

    struct general {
        string name;
        uint256 defense;
        uint256 strength;
        uint256 intelligence;
        uint256 agility;
        uint256 abilityPower;
        uint256 magicResistance;
        uint256 constitution;
        uint256 speed;
        uint256 charisma;
        uint256 level;
        uint256 createdAt;
    }

    // Global constants
    uint256 public changeNamePrice = 10000000000000000; // 0.01 ETH
    uint256 public price = 50000000000000000; //0.05 ETH
    uint256 public castleOwnerPrice = 0; // 0 ETH
    bool public paused = false; // Enable disable
    uint256 public maxTokens = 12999;
    uint256 public xpPerQuest = 100;
    uint256 public xpPerNameChange = 250;
    uint256 public maxLevelGenerals = 10;
    uint constant DAY = 1 days;

    // Mappings
    mapping(uint256 => general) public generals;
    mapping(uint256 => string) public bios;
    mapping(uint256 => uint256) public experience;
    mapping(uint256 => uint256) public castle;
    mapping(uint => uint) public generalsQuestLog;
    mapping(uint256 => bool) public claimedWithCastle;

    // Events
    event GeneralCreated(
        string name,
        uint256 generalId,
        general generalCreated
    );

    event LeveledUp(
        address indexed leveler,
        uint256 generalId,
        uint256 level
    );

    event ExperienceSpent(uint256 generalId, uint256 xpSpent, uint256 xpRemaining);
    event ExperienceGained(uint256 generalId, uint256 xpGained, uint256 xpRemaining);
    event NameChanged(uint256 generalId, string name);
    event BioChanged(uint256 generalId, string bio);

    event Quest(uint256 generalId, uint256 xpGained, uint256 xpTotal);
    event AssignedCastle(uint256 generalId, uint256 castleId);

    constructor() ERC721("CryptoGenerals", "CRYPTOGENERALS") Ownable() {
        // Grant the contract deployer the default admin role: it will be able
        // to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    // Change constants

    // Pause or resume minting
    function flipPause() public onlyOwner {
        paused = !paused;
    }

    function setCastleContractAddress(address _castle) public onlyOwner {
        castlesAddress = _castle;
    }

    function setMaxLevels(uint256 _newMaxLevels) public onlyOwner {
        maxLevelGenerals = _newMaxLevels;
    }

    function setXPPerQuest(uint256 _newXPPerQuest) public onlyOwner {
        xpPerQuest = _newXPPerQuest;
    }

    function setXPPerNameChange(uint256 _newXpPerNameChange) public onlyOwner {
        xpPerNameChange = _newXpPerNameChange;
    }

    // Change the public price of the token
    function setPrice(uint256 _newPrice, uint256 _type) external onlyOwner {
        if (_type == 0) {
            price = _newPrice;
        } else if (_type == 1) {
            castleOwnerPrice = _newPrice;
        } else {
            changeNamePrice = _newPrice;
        }
    }

    // Change the maximum amount of tokens
    function setMaxtokens(uint256 newMaxtokens) public onlyOwner {
        maxTokens = newMaxtokens;
    }

    // Claim deposited eth
    function ownerWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    // Normal mint
    function mintWithName(string memory _name) public payable nonReentrant {
        require(!paused, "Minting is paused");
        require(price <= msg.value, "Ether value sent is not correct");
        _internalMint(_name);
    }

    // Mint without name
    function mint() public payable nonReentrant {
        require(!paused, "Minting is paused");
        require(price <= msg.value, "Ether value sent is not correct");
        _internalMint("Crypto General");
    }

    // Mint with castle
    function mintWithCastle(uint256 _castleId, string memory _name)
        external
        payable
        nonReentrant
    {
        require(!paused, "Minting is paused");
        require(
            castlesContract.ownerOf(_castleId) == msg.sender,
            "Not the owner of this castle"
        );
        require(msg.value >= castleOwnerPrice, "Eth sent is not enough");
        require(!claimedWithCastle[_castleId], "Castle already used for claiming a general");

        uint256 tokenId = _internalMint(_name);

        // Update the list of claimed
        claimedWithCastle[_castleId] = true;
        castle[tokenId] = _castleId;
        emit AssignedCastle(tokenId, _castleId);
    }

    // Allow the owner to claim a nft
    function ownerClaim() public nonReentrant onlyOwner {
        _internalMint("Crypto General");
    }

    // Called by every function after safe access checks
    function _internalMint(string memory _name) internal returns (uint256) {
        require(bytes(_name).length < 100 && bytes(_name).length > 3, "Name between 3 and 100 characters");

        // minting logic
        uint256 current = _tokenIds.current();
        require(current <= maxTokens, "Max token reached");

        _tokenIds.increment();
        uint256 tokenId = _tokenIds.current();

        _createGeneral(tokenId, _name);
        _safeMint(_msgSender(), tokenId);
        return tokenId;
    }

    // Create general
    function _createGeneral(uint256 _tokenId, string memory _name) internal {
        generals[_tokenId].name = _name;
        generals[_tokenId].defense = _randomFromString("defense", 10) + 1;
        generals[_tokenId].strength = _randomFromString("strength", 10)  + 1;
        generals[_tokenId].intelligence = _randomFromString("intelligence", 10)  + 1;
        generals[_tokenId].agility = _randomFromString("agility", 10)  + 1;
        generals[_tokenId].abilityPower = _randomFromString("abilityPower", 10)  + 1;
        generals[_tokenId].magicResistance = _randomFromString(
            "magicResistance",
            10
        )  + 1;
        generals[_tokenId].constitution = _randomFromString("constitution", 10)  + 1;
        generals[_tokenId].speed = _randomFromString("speed", 10)  + 1;
        generals[_tokenId].charisma = _randomFromString("charisma", 10)  + 1;

        generals[_tokenId].level = 1;
        generals[_tokenId].createdAt = block.timestamp;

        experience[_tokenId] = 0;

        emit GeneralCreated(
            generals[_tokenId].name,
            _tokenId,
            generals[_tokenId]
        );
    }

    // General modifiers
    function spendExperience(uint256 _tokenId, uint256 _experience) public {
        require(_isApprovedOrOwner(msg.sender, _tokenId) || hasRole(GAME_ROLE, msg.sender), "Does not have permission");
        require(_experience <= experience[_tokenId], "Not enough experience");

        experience[_tokenId] -= _experience;

        emit ExperienceSpent(_tokenId, _experience, experience[_tokenId]);
    }

    function addExperience(uint256 _tokenId, uint256 _experience) public onlyOwner {
        require(hasRole(GAME_ROLE, msg.sender), "Does not have Game role");

        experience[_tokenId] += _experience;
        emit ExperienceGained(_tokenId, _experience, experience[_tokenId]);
    }

    function quest(uint _tokenId) external {
        require(_isApprovedOrOwner(msg.sender, _tokenId));
        require(block.timestamp > generalsQuestLog[_tokenId], "Too early to do a new quest");

        uint256 xpGained = _random(_tokenId, xpPerQuest) + xpPerQuest;

        generalsQuestLog[_tokenId] = block.timestamp + DAY;
        experience[_tokenId] += xpGained;
        emit Quest(_tokenId, xpGained, experience[_tokenId]);
        emit ExperienceGained(_tokenId, xpGained, experience[_tokenId]);
    }

     function levelUp(uint _tokenId) external {
        require(_isApprovedOrOwner(msg.sender, _tokenId) || hasRole(GAME_ROLE, msg.sender), "Does not have permission");
        uint _level = generals[_tokenId].level;
        require(_level <= maxLevelGenerals, "Max level reached");
        uint _xpRequired = experienceRequired(_level, 100);
        spendExperience(_tokenId, _xpRequired);
        
        generals[_tokenId].level += 1;
        generals[_tokenId].defense += 1;
        generals[_tokenId].strength += 1;
        generals[_tokenId].intelligence += 1;
        generals[_tokenId].agility += 1;
        generals[_tokenId].abilityPower += 1;
        generals[_tokenId].magicResistance += 1;
        generals[_tokenId].constitution += 1;
        generals[_tokenId].speed += 1;
        generals[_tokenId].charisma += 1;

        emit LeveledUp(msg.sender, _tokenId, _level + 1);
    }

    // Increase the difficulty of leveling up
    // 100, 220, 360, 520, 700, 900
    function experienceRequired(uint256 _level, uint256 _xpPerLevel)
        public
        pure
        returns (uint256 xp_to_next_level)
    {
        xp_to_next_level = _level * _xpPerLevel;
        for (uint256 i = 1; i < _level; i++) {
            xp_to_next_level += _level * (_xpPerLevel / 10);
        }
    }

    // Change the name of a general
    function changeName(uint256 _tokenId, string memory _name)
        external
        payable
        nonReentrant
    {
        require(msg.value >= changeNamePrice, "Eth sent is not enough");
        require(_isApprovedOrOwner(msg.sender, _tokenId));
        require(bytes(_name).length < 100 && bytes(_name).length > 3, "Name between 4 and 100 characters");
        generals[_tokenId].name = _name;
        // Increase experience
        experience[_tokenId] += xpPerNameChange;
        emit NameChanged(_tokenId, _name);
    }

    function changeBio(uint256 _tokenId, string memory _bio)
        external
        payable
        nonReentrant
    {
        require(msg.value >= changeNamePrice, "Eth sent is not enough");
        require(_isApprovedOrOwner(msg.sender, _tokenId));
        require(bytes(_bio).length < 300 && bytes(_bio).length > 3, "Bio between 4 and 300 characters");
        bios[_tokenId] = _bio;
        experience[_tokenId] += xpPerNameChange;
        emit BioChanged(_tokenId, _bio);
    }

    function changeCastle(uint256 _tokenId, uint256 _castleId)
        external
        nonReentrant
    {
        require(
            castlesContract.ownerOf(_castleId) == msg.sender,
            "Not the owner of this castle"
        );
        require(_isApprovedOrOwner(msg.sender, _tokenId));


        castle[_tokenId] = _castleId;
        emit AssignedCastle(_tokenId, _castleId);
    }

    function _random(uint256 _salt, uint256 _limit)
        internal
        view
        returns (uint256)
    {
        return
            uint256(
                keccak256(
                    abi.encodePacked(block.number, block.timestamp, _salt)
                )
            ) % _limit;
    }

    function _randomFromString(string memory _salt, uint256 _limit)
        internal
        view
        returns (uint256)
    {
        return
            uint256(
                keccak256(
                    abi.encodePacked(block.number, block.timestamp, _salt)
                )
            ) % _limit;
    }



    /**
     * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
     * in child contracts.
     */
    string private baseURI = "ipfs://";

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        baseURI = newBaseURI;
    }

}

