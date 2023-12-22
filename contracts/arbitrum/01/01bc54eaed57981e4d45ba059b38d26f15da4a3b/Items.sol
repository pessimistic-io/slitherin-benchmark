//                         .
//                     /   ))     |\         )               ).
//               c--. (\  ( `.    / )  (\   ( `.     ).     ( (
//               | |   ))  ) )   ( (   `.`.  ) )    ( (      ) )
//               | |  ( ( / _..----.._  ) | ( ( _..----.._  ( (
// ,-.           | |---) V.'-------.. `-. )-/.-' ..------ `--) \._
// | /===========| |  (   |      ) ( ``-.`\/'.-''           (   ) ``-._
// | | / / / / / | |--------------------->  <-------------------------_>=-
// | \===========| |                 ..-'./\.`-..                _,,-'
// `-'           | |-------._------''_.-'----`-._``------_.-----'
//               | |         ``----''            ``----''
//               | |
//               c--`
//hm
pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./ERC1155Burnable.sol";
import "./IERC1155Receiver.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";


interface ISource {
    function getItemType(uint256 _id) external view returns (uint256 itemType);

    function getItemLevel(uint256 _id) external view returns (uint256);

    function getItemStats(uint256 _id) external view returns (uint8[5] memory);
}

interface IArcane {
    function ownerOf(uint256 tokenId) external view returns (address);

    function getWizardInfosIds(uint256 _wizId)
        external
        view
        returns (uint256[5] memory);
}

interface ISkillbook {
    function getWizardSkills(uint256 _wizId)
        external
        view
        returns (uint256[5] memory);
}

interface IAdventure {
    function getWizardLevel(uint256 _wizId) external view returns (uint256);
}


contract Items is
    ERC1155,
    ReentrancyGuard,
    Ownable,
    ERC1155Burnable,
    IERC1155Receiver
{
    constructor() ERC1155("") {}
    using Strings for uint256;

    // EVENTS
    event Equip(
        uint256 wizId,
        uint256 slot,
        uint256 itemId
    );

    event Unequip(
        uint256 wizId,
        uint256 slot
    );

    event LootItem(
        address to,
        uint256[] itemIds
    );

    // DATA 
    ISource public ARMORY;
    ISource public CRAFTINGBOOK;
    ISource public SPECIAL;

    // SYSTEMS
    IArcane public ARCANE;
    ISkillbook public SKILLBOOK;
    IAdventure public ADVENTURE;

    string public URISuffix;
    string public URIPreffix;

    // balances (currently equipped): wizId => itemId => amount
    mapping(uint256 => mapping(uint256 => uint256)) public balances;
    // Equipped SLOTS: 0:head 1:torso 2:legs 3:necklace 4:ring 5:righthand 6:lefthand
    mapping(uint256 => mapping(uint256 => uint256)) public equipped;
    // initialised state
    mapping(uint256 => bool) public initialised;
    // total gear stats
    mapping(uint256 => mapping(uint256 => uint256)) public gearStats;
    // races recorded for racial perks
    mapping(uint256 => uint256) public races;
    // gear minters
    mapping(address => bool) public minters;

    modifier wizardOwner(uint256 _wizId) {
        require(
            ARCANE.ownerOf(_wizId) == msg.sender,
            "You don't own this Wizard"
        );
        _;
    }

    modifier validSlot(uint256 _itemId, uint256 _slot) {
        uint256 itemType = _getSource(_itemId).getItemType(_itemId);
        if (itemType < 5) {
            require(itemType == _slot, "Wrong slot");
        } else {
            require(_slot > 4, "Wrong slot");
        }
        _;
    }

    // EXTERNAL
    // ------------------------------------------------------

    // manual equip by user, make sure it's from the armory
    function equipItem(
        uint256 _wizId,
        uint256 _slot,
        uint256 _itemId
    ) external nonReentrant wizardOwner(_wizId) validSlot(_itemId, _slot) {
        // check level & that its equipable gear
        require(_itemId<1000, "You can't equip this item");
        uint256 minLevel = _getSource(_itemId).getItemLevel(_itemId);
        require(
            minLevel <= ADVENTURE.getWizardLevel(_wizId),
            "You don't have the level required"
        );

        // empty slots, will run only once
        if (!initialised[_wizId]) {
            for (uint256 i = 0; i < 7; i++) {
                equipped[_wizId][i] = 10000;
            }
            initialised[_wizId] = true;
        }

       
        if(!isApprovedForAll(msg.sender, address(this))){
            setApprovalForAll(address(this), true);
        }

        // transfer out to owner and replace
        _unequipItemAndReplace(msg.sender, _wizId, _slot, _itemId);

        emit Equip(_wizId,_slot,_itemId);
    }

    // manual unequip by user
    function unequipItem(uint256 _wizId, uint256 _slotId)
        external
        nonReentrant
        wizardOwner(_wizId)
    {
        require(equipped[_wizId][_slotId]!=10000, "Nothing to unequip");

        uint256 itemId = equipped[_wizId][_slotId];
        // transfer
        _unequip(itemId, _wizId, _slotId, msg.sender);

        emit Unequip(_wizId, _slotId);
    }

    function getWizardStats(uint256 _wizId)
        external
        view
        returns (uint256[5] memory)
    {
        uint256[5] memory totalSkills;
        uint256[5] memory skillbookStats = SKILLBOOK.getWizardSkills(_wizId);
        // get skillbook stats
        for (uint256 i = 0; i < totalSkills.length; i++) {
            totalSkills[i] = 0;
            totalSkills[i] += skillbookStats[i];
        }
        // add gear stats
        for (uint256 i = 0; i < totalSkills.length; i++) {
            totalSkills[i] += gearStats[_wizId][i];
        }

        // Racial Perks
        uint256[5] memory wizInfos = ARCANE.getWizardInfosIds(_wizId);
        if (wizInfos[4] == 0) {
            // Human - endurance
            totalSkills[4] += 1;
        } else if (wizInfos[4] == 1) {
            // Siam - intellect
            totalSkills[2] += 3;
        } else if (wizInfos[4] == 2) {
            //  Undead - spell
            totalSkills[3] += 1;
        } else if (wizInfos[4] == 3) {
            // Sylvan - focus
            totalSkills[0] += 2;
        } else {
            // Yord - strength
            totalSkills[1] += 2;
        }

        return totalSkills;
    }

    function mintItems(address _to, uint256[] memory _itemIds, uint256[] memory _amounts) external {
        require(minters[msg.sender], "Not authorized");
        _mintBatch(_to, _itemIds, _amounts, "");
        emit LootItem(_to, _itemIds);
    }

    function getEquipped(uint256 _wizId) external view returns (uint256[7] memory) {
        uint256[7] memory currEquipped;
        for(uint i=0; i<currEquipped.length;i++){
            currEquipped[i] = equipped[_wizId][i];
        }
        return currEquipped;
    }

    // PUBLIC
    // ------------------------------------------------------

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }



    function uri(uint256 _id) override public view returns(string memory){
        return
            string(
                abi.encodePacked(URIPreffix, _id.toString(), URISuffix)
            );
    }

    // INTERNAL
    // ------------------------------------------------------

    function _unequipItemAndReplace(
        address _owner,
        uint256 _wizId,
        uint256 _inSlot,
        uint256 _inItemId
    ) internal {
        // check if slot is empty
        if (equipped[_wizId][_inSlot] != 10000) {
            // get id
            uint256 outItemId = equipped[_wizId][_inSlot];

            // transfer
            _safeTransferFrom(address(this), _owner, outItemId, 1, "");
            // edit balances
            balances[_wizId][outItemId]--;

            // remove stats
            uint8[5] memory outItemStats = _getSource(outItemId).getItemStats(outItemId);
            for (uint256 i = 0; i < 5; i++) {
                gearStats[_wizId][i] -= uint256(outItemStats[i]);
            }
        }
        // transfer in, update balance
        safeTransferFrom(msg.sender, address(this), _inItemId, 1, "");
        balances[_wizId][_inItemId]++;
        // edit equipped
        equipped[_wizId][_inSlot] = _inItemId;

        // add stats
        uint8[5] memory inItemStats = _getSource(_inItemId).getItemStats(_inItemId);
        for (uint256 i = 0; i < 5; i++) {
            gearStats[_wizId][i] += uint256(inItemStats[i]);
        }
    }

    function _unequip(uint256 _itemId, uint256 _wizId, uint256 _slotId, address _owner) internal {
             // transfer
        _safeTransferFrom(address(this), _owner, _itemId, 1, "");
        // edit balances
        balances[_wizId][_itemId]--;
        // set empty
        equipped[_wizId][_slotId] = 10000;
        // remove stats
        uint8[5] memory outItemStats = _getSource(_itemId).getItemStats(_itemId);
        for (uint256 i = 0; i < 5; i++) {
            gearStats[_wizId][i] -= uint256(outItemStats[i]);
        }
    }

    function _getSource(uint256 _itemId) internal view returns (ISource){
        if(_itemId<1000){
            return ARMORY;
        }else if(_itemId>999 && _itemId<2000){
            return CRAFTINGBOOK;
        } else {
            return SPECIAL;
        }
    }

    // OWNER
    // ------------------------------------------------------

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public onlyOwner {
        _mint(account, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    // 0:Armory 1:Craftingbook 2:Special
    function setSource(address _dataSource, uint256 _sourceId) external onlyOwner {
        if(_sourceId==0){
            ARMORY = ISource(_dataSource);
        }else if(_sourceId==1){
            CRAFTINGBOOK = ISource(_dataSource);
        }else{
            SPECIAL = ISource(_dataSource);
        }
    }

    function setArcane(address _arcane) external onlyOwner {
        ARCANE = IArcane(_arcane);
    }

    function setSkillbook(address _skillbook) external onlyOwner {
        SKILLBOOK = ISkillbook(_skillbook);
    }

    function setAdventure(address _adventure) external onlyOwner {
        ADVENTURE = IAdventure(_adventure);
    }

    function addMinter(address _toAdd) external onlyOwner {
        minters[_toAdd] = true;
    }

    function removeMinter(address _toAdd) external onlyOwner {
        minters[_toAdd] = false;
    }

    function mintBatch(
        address _to,
        uint256 _itemId,
        uint256 _amount
    ) external onlyOwner {
        _mint(_to, _itemId, _amount, "");
    }
}

