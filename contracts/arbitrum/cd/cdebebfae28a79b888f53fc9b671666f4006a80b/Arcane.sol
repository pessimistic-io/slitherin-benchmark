//  ` : | | | |:  ||  :     `  :  |  |+|: | : : :|   .        `              .
//      ` : | :|  ||  |:  :    `  |  | :| : | : |:   |  .                    :
//         .' ':  ||  |:  |  '       ` || | : | |: : |   .  `           .   :.
//                `'  ||  |  ' |   *    ` : | | :| |*|  :   :               :|
//        *    *       `  |  : :  |  .      ` ' :| | :| . : :         *   :.||
//             .`            | |  |  : .:|       ` | || | : |: |          | ||
//      '          .         + `  |  :  .: .         '| | : :| :    .   |:| ||
//         .                 .    ` *|  || :       `    | | :| | :      |:| |
// .                .          .        || |.: *          | || : :     :|||
//        .            .   . *    .   .  ` |||.  +        + '| |||  .  ||`
//     .             *              .     +:`|!             . ||||  :.||`
// +                      .                ..!|*          . | :`||+ |||`
//     .                         +      : |||`        .| :| | | |.| ||`     .
//       *     +   '               +  :|| |`     :.+. || || | |:`|| `
//                            .      .||` .    ..|| | |: '` `| | |`  +
//  .       +++                      ||        !|!: `       :| |
//              +         .      .    | .      `|||.:      .||    .      .    `
//          '                           `|.   .  `:|||   + ||'     `
//  __    +      *                         `'       `'|.    `:
//"'  `---"""----....____,..^---`^``----.,.___          `.    `.  .    ____,.,-
//    ___,--'""`---"'   ^  ^ ^        ^       """'---,..___ __,..---""'
//--"'                           ^                         ``--..,__ D.Rice
//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";

interface ISkillbook {
    function createBook(uint256[5] memory _startSkills, uint256 _wizId)
        external;
}

contract Arcane is ERC721Enumerable, ReentrancyGuard, Ownable {
    using Strings for uint256;
    // @dev connected contracts
    // 0 - vault
    // 1 - skillbook
    // 2 - loot
    // 3 - home
    // 4 - adventure
    mapping(uint256 => address) public connected;
    mapping(uint256 => Wizard) public wizards;

    ISkillbook public SKILLBOOK;
    uint256 public MAX_SUPPLY = 5555;
    uint256 public PRICE = 50000000000000000;
    string public BASE_URI;
    string public BASE_EXTENSION = ".json";
    uint256 private randCounter = 0;

    event WizardBorn(
        string name,
        string race,
        string archetype,
        string affinity,
        string identity1,
        string identity2
    );
    event WizardRenounced(uint256 wizardId, string name);

    string[11] public archetypes = [
        "Wizard",
        "Mage",
        "Priest",
        "Warlock",
        "Mentah",
        "Sorcerer",
        "Druid",
        "Enchanter",
        "Astronomer",
        "Elementalist",
        "Shadowcaster"
    ];

    string[6] public affinities = [
        "Arcane",
        "Shadow",
        "Divine",
        "Elemental",
        "Voodoo",
        "Wild"
    ];

    string[29] public identities = [
        "Zen",
        "Uncivilized",
        "Adventurer",
        "Logistician",
        "Farsighted",
        "Mysterious",
        "Paranoiac",
        "Stoic",
        "Suspicious",
        "Honest",
        "Introvert",
        "Leader",
        "Quiet",
        "Inspired",
        "Curious",
        "Veteran",
        "Honest",
        "Fearless",
        "Calculated",
        "Applied",
        "Cunning",
        "Spiritual",
        "Tenacious",
        "Scarred",
        "Hermit",
        "Immoral",
        "Ruthless",
        "Primitive",
        "Brooding"
    ];

    string[5] public races = ["Human", "Siam", "Undead", "Sylvan", "Yord"];

    // Previous "Vision" "Knowledge"
    string[7] public skills = [
        "Focus",
        "Strenght"
        "Intellect",
        "Spell",
        "Endurance"
    ];

    struct Wizard {
        string name;
        uint8 mana;
        uint256 dna;
        uint256 birthday;
    }

    constructor() ERC721("Arcane", "ARC") {}

    modifier isConnected() {
        require(_isContractConnected(msg.sender), "No authority");
        _;
    }

    // EXTERNAL
    // ------------------------------------------------------

    function claimWizard(string memory _name) external payable nonReentrant {
        require(msg.value >= PRICE, "Not enough ETH to summon");
        require(totalSupply() < MAX_SUPPLY, "All Wizards Have Been Summoned!");
        uint256 newId = totalSupply();

        _mintWizard(newId, _name);
        _safeMint(msg.sender, newId);
    }

    // @dev Forever gone in the corridors of Time...
    function renounceWizard(uint256 _wizId, address _caller)
        external
        nonReentrant
        isConnected
    {
        require(_exists(_wizId), "This Wizard doesn't exist");
        require(ownerOf(_wizId) == _caller, "You're not the owner");
        string memory name = wizards[_wizId].name;
        _burn(_wizId);

        emit WizardRenounced(_wizId, name);
    }

    function getWizardInfosIds(uint256 _wizId)
        external
        view
        returns (uint256[5] memory)
    {
        return _sliceDna(wizards[_wizId].dna);
    }

    function getWizardInfosString(uint256 _wizId)
        external
        view
        returns (string[6] memory)
    {
        string[6] memory infos;
        uint256[5] memory ids = _sliceDna(wizards[_wizId].dna);
        infos[0] = wizards[_wizId].name;
        infos[1] = races[ids[4]];
        infos[2] = archetypes[ids[3]];
        infos[3] = affinities[ids[2]];
        infos[4] = identities[ids[1]];
        infos[5] = identities[ids[0]];
        return infos;
    }

    function getBirthday(uint256 _wizId) external view returns (uint256) {
        return wizards[_wizId].birthday;
    }

    function checkIfConnected(address _sender) external view returns (bool) {
        return _isContractConnected(_sender);
    }

    function tokenURI(uint256 _wizId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(_wizId));
        return
            string(
                abi.encodePacked(BASE_URI, _wizId.toString(), BASE_EXTENSION)
            );
    }

    // INTERNAL
    // ------------------------------------------------------

    function _mintWizard(uint256 _id, string memory _name) internal {
        wizards[_id].name = _name;
        wizards[_id].mana = 10;
        uint8 race = uint8(_randomize(_name, 5));
        uint8 archetype = uint8(_randomize(_name, 6));
        uint8 identity1 = uint8(_randomize(_name, 29));
        uint8 identity2 = uint8(_randomize(_name, 29));
        while (identity1 == identity2) {
            identity2 = uint8(_randomize(_name, 29));
        }
        uint8 affinity = uint8(_randomize(_name, 5));

        uint256 dna = _createDNA(
            race,
            archetype,
            affinity,
            identity1,
            identity2
        );
        if (_id == 0) {
            dna = 2021204;
        }
        wizards[_id].dna = dna;
        uint256[5] memory skillBook;
        for (uint8 i; i < 5; i++) {
            skillBook[i] = 1 + uint256(_randomize(_name, 3));
        }
        wizards[_id].birthday = block.timestamp;

        SKILLBOOK.createBook(skillBook, _id);

        emit WizardBorn(
            _name,
            races[race],
            archetypes[archetype],
            affinities[affinity],
            identities[identity1],
            identities[identity2]
        );
    }

    function _randomize(string memory _salt, uint256 _limit)
        internal
        returns (uint256)
    {
        randCounter++;
        if (randCounter >= 1000) {
            randCounter = 0;
        }
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        _salt,
                        block.timestamp,
                        block.number,
                        randCounter
                    )
                )
            ) % _limit;
    }

    function _isContractConnected(address _caller)
        internal
        view
        returns (bool)
    {
        for (uint8 i = 0; i < 10; i++) {
            if (connected[i] == _caller) {
                return true;
            }
        }
        return false;
    }

    function _createDNA(
        uint256 _race,
        uint256 _archetype,
        uint256 _affinity,
        uint256 _identity1,
        uint256 _identity2
    ) internal pure returns (uint256) {
        uint256 dna = _race * 100000000;
        dna += _archetype * 1000000;
        dna += _affinity * 10000;
        dna += _identity1 * 100;
        dna += _identity2;
        return dna;
    }

    function _sliceDna(uint256 _dna) internal pure returns (uint256[5] memory) {
        uint256[5] memory digits;
        uint256 number = _dna;
        uint256 counter = 0;
        while (number > 0) {
            uint8 digit = uint8(number % 100);
            number = number / 100;
            digits[counter] = digit;
            counter++;
        }
        return digits;
    }

    function _getSlice(
        uint256 begin,
        uint256 end,
        string memory text
    ) internal pure returns (string memory) {
        bytes memory a = new bytes(end - begin + 1);
        for (uint256 i = 0; i <= end - begin; i++) {
            a[i] = bytes(text)[i + begin - 1];
        }
        return string(a);
    }

    // ONLY OWNER
    // ------------------------------------------------------

    function setConnected(uint256 _connectedId, address _address)
        external
        onlyOwner
    {
        connected[_connectedId] = _address;
        if (_connectedId == 1) {
            SKILLBOOK = ISkillbook(_address);
        }
    }

    function disconnectContract(uint256 _contractId) external onlyOwner {
        connected[_contractId] = address(0);
    }

    function withdraw() external onlyOwner {
        require(connected[0] != address(0), "Vault is set to 0x0");
        require(payable(connected[0]).send(address(this).balance));
    }

    function setPrice(uint256 _newPrice) external onlyOwner {
        PRICE = _newPrice;
    }

    function setSupply(uint256 _newSupply) external onlyOwner {
        MAX_SUPPLY = _newSupply;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        BASE_URI = _newBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension)
        public
        onlyOwner
    {
        BASE_EXTENSION = _newBaseExtension;
    }
}

