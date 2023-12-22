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

    // DATA 
    ISource public ARMORY;

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
    mapping(address => bool) public minters;


    function equipItem(
        uint256 _wizId,
        uint256 _slot,
        uint256 _itemId
    ) external nonReentrant {
        require(ARCANE.ownerOf(_wizId)==msg.sender,"You don't own this Wizard");
        require(_itemId<1000, "You can't equip this item");

         uint256 itemType = ARMORY.getItemType(_itemId);
        if (itemType < 5) {
            require(itemType == _slot, "Wrong slot");
        } else {
            require(_slot > 4, "Wrong slot");
        }  

        uint256 minLevel = ARMORY.getItemLevel(_itemId);
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

        _unequipItemAndReplace(msg.sender, _wizId, _slot, _itemId);

    }

    // manual unequip by user
    function unequipItem(uint256 _wizId, uint256 _slotId)
        external
        nonReentrant
    {
        require(ARCANE.ownerOf(_wizId)==msg.sender,"You don't own this Wizard");
        require(equipped[_wizId][_slotId]!=10000, "Nothing to unequip");

        uint256 itemId = equipped[_wizId][_slotId];
        // transfer
        _unequip(itemId, _wizId, _slotId, msg.sender);

    }

    function getWizardStats(uint256 _wizId)
        external
        view
        returns (uint256[5] memory)
    {
        uint256[5] memory totalSkills;
        uint256[5] memory skillbookStats = SKILLBOOK.getWizardSkills(_wizId);
        for (uint256 i = 0; i < totalSkills.length; i++) {
            totalSkills[i] = 0;
            totalSkills[i] += skillbookStats[i];
        }
        for (uint256 i = 0; i < totalSkills.length; i++) {
            totalSkills[i] += gearStats[_wizId][i];
        }

        uint256[5] memory wizInfos = ARCANE.getWizardInfosIds(_wizId);
        if (wizInfos[4] == 0) {
            totalSkills[4] += 1;
        } else if (wizInfos[4] == 1) {
            totalSkills[2] += 3;
        } else if (wizInfos[4] == 2) {
            totalSkills[3] += 1;
        } else if (wizInfos[4] == 3) {
            totalSkills[0] += 2;
        } else {
            totalSkills[1] += 2;
        }

        return totalSkills;
    }

    function mintItems(address _to, uint256[] memory _itemIds, uint256[] memory _amounts) external {
        require(minters[msg.sender], "Not authorized");
        _mintBatch(_to, _itemIds, _amounts, "");
    }

    function getEquipped(uint256 _wizId) external view returns (uint256[7] memory) {
        uint256[7] memory currEquipped;
        for(uint i=0; i<currEquipped.length;i++){
            currEquipped[i] = equipped[_wizId][i];
        }
        return currEquipped;
    }
    
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

    function destroy(address _from, uint256[] memory _ids, uint256[] memory _amounts) public {
        require(minters[msg.sender], "Not authorized");
        _burnBatch(_from, _ids, _amounts);
    }

    function uri(uint256 _id) override public view returns(string memory){
        return
            string(
                abi.encodePacked(URIPreffix, _id.toString(), URISuffix)
            );
    }

    function _unequipItemAndReplace(
        address _owner,
        uint256 _wizId,
        uint256 _inSlot,
        uint256 _inItemId
    ) internal {
        // check if slot is empty
        if (equipped[_wizId][_inSlot] != 10000) {
            uint256 outItemId = equipped[_wizId][_inSlot];

            _safeTransferFrom(address(this), _owner, outItemId, 1, "");
            balances[_wizId][outItemId]--;

            uint8[5] memory outItemStats = ARMORY.getItemStats(outItemId);
            for (uint256 i = 0; i < 5; i++) {
                gearStats[_wizId][i] -= uint256(outItemStats[i]);
            }
        }
        safeTransferFrom(msg.sender, address(this), _inItemId, 1, "");
        balances[_wizId][_inItemId]++;
        equipped[_wizId][_inSlot] = _inItemId;

        uint8[5] memory inItemStats = ARMORY.getItemStats(_inItemId);
        for (uint256 i = 0; i < 5; i++) {
            gearStats[_wizId][i] += uint256(inItemStats[i]);
        }
    }

    function _unequip(uint256 _itemId, uint256 _wizId, uint256 _slotId, address _owner) internal {
        _safeTransferFrom(address(this), _owner, _itemId, 1, "");
        balances[_wizId][_itemId]--;
        equipped[_wizId][_slotId] = 10000;
        uint8[5] memory outItemStats = ARMORY.getItemStats(_itemId);
        for (uint256 i = 0; i < 5; i++) {
            gearStats[_wizId][i] -= uint256(outItemStats[i]);
        }
    }

    function setURI(string memory _prefix, string memory _suffix) public onlyOwner {
        URIPreffix = _prefix;
        URISuffix = _suffix;
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public onlyOwner {
        _mintBatch(to, ids, amounts, data);
    }

    function setConnected(address _arcane,address _skillbook,address _adventure, address _dataSource) external onlyOwner {
        ARCANE = IArcane(_arcane);
        SKILLBOOK = ISkillbook(_skillbook);
        ADVENTURE = IAdventure(_adventure);
        ARMORY = ISource(_dataSource);
    }

    function addMinter(address _toAdd,bool _flag) external onlyOwner {
        minters[_toAdd] = _flag;
    }
}

