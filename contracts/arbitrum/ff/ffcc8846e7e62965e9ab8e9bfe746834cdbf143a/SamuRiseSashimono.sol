// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SamuRiseLandErrors.sol";


interface IERC20 {
     function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
     function transfer(address to, uint256 amount) external returns (bool);
}

interface ISamuRiseQuest {
    function increaseTokenIdToDojoRarityBonus(uint256 tokenId, uint256 bonusAmount) external;
    function mintItem(address _originator, uint256 _collectionId, uint256 _numberToClaim, uint256 _maxAllocation)  external;
    function setLandTokenIdFactionAndProvince(uint256 _tokenId, uint256 _faction, uint256 _province) external;
}

interface ISamuRiseItems {
    function getTokenSupply(uint256 _collectionId) external view returns (uint256);
    function getTokenMaxSupply(uint256 _collectionId) external view returns (uint256);
}

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
}


interface IDiceRNG {
    function rollSingleDice(uint256 _numberOfSides, bytes memory _entropy) external returns(uint256);
}

contract SamuRiseSashimono is UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable
{
    using ECDSAUpgradeable for bytes32;
    using StringsUpgradeable for uint256;
    
    uint256 constant public ZERO_MAGIC = 0;
    uint256 constant public TEN_MAGIC = 10e18;
    uint256 constant public TWENTY_MAGIC = 20e18;
    uint256 constant public THIRTY_MAGIC = 30e18;
    uint256 constant public FORTY_MAGIC = 40e18;
    uint256 constant public FIFTY_MAGIC = 50e18;

    address public magicContract;
    address public questContract;
    address public landContract;
    address public itemsContract;
    address public diceRNGContract;
    address public treasuryWallet;

    uint256 public itemCollectionIdToMint;
    
    mapping(uint8 => uint256) public factionToFlagsPlantedCount;
    mapping (uint256 => bool) public tokenIdToHasPlantedFlag;
    mapping(bytes32 => bool) public usedHashes;
    
    event DiceRollEvent(uint256 diceRoll);
    
    function initialize(address _magicContract) public initializer {
        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _pause();
        magicContract = _magicContract;
    }

    modifier callerIsUser() {
        if(tx.origin != msg.sender) revert CallerIsAnotherContract();
        _;
    }

    modifier validateInputData(uint256 _landTokenId,  uint8 _faction, uint256 _amountOfMagic) {
        require(IERC721(landContract).ownerOf(_landTokenId) == msg.sender, "land token is not owned by msg.sender");
        require(factionToFlagsPlantedCount[_faction] < 3333, "Maximum for this faction has already been allocated");
        require(tokenIdToHasPlantedFlag[_landTokenId] == false, "Sashimono has already been planted on this land");
        require(
                _amountOfMagic == ZERO_MAGIC || _amountOfMagic == TEN_MAGIC || _amountOfMagic == TWENTY_MAGIC ||
                _amountOfMagic == THIRTY_MAGIC || _amountOfMagic == FORTY_MAGIC || _amountOfMagic == FIFTY_MAGIC, 
                "incorrect denomination of Magic sent"
        );

        _;
    }

    function plantFlag(uint256 _landTokenId,  uint8 _faction, uint256 _amountOfMagic) 
        public
        callerIsUser()
        whenNotPaused()
        validateInputData(_landTokenId, _faction, _amountOfMagic)
    {
        if(_amountOfMagic > 0) {
            IERC20(magicContract).transferFrom(msg.sender, treasuryWallet, _amountOfMagic);
        }
        
        uint256 province = factionToFlagsPlantedCount[_faction]++ % 3;
        uint256 diceRoll = IDiceRNG(diceRNGContract).rollSingleDice(4, abi.encodePacked(msg.sender, _landTokenId, _faction, _amountOfMagic));

        emit DiceRollEvent(diceRoll);
        
        if (diceRoll == 1) {
            if(_amountOfMagic >= TEN_MAGIC) {
                ISamuRiseQuest(questContract).increaseTokenIdToDojoRarityBonus(_landTokenId, 1);
            }
            if(_amountOfMagic >= FORTY_MAGIC) {
                if(ISamuRiseItems(itemsContract).getTokenSupply(itemCollectionIdToMint) == ISamuRiseItems(itemsContract).getTokenMaxSupply(itemCollectionIdToMint)){
                    ISamuRiseQuest(questContract).increaseTokenIdToDojoRarityBonus(_landTokenId, 1);
                } else {
                    ISamuRiseQuest(questContract).mintItem(msg.sender, itemCollectionIdToMint, 1, 1);
                }
            } 
        } else if (diceRoll == 2) {
            if(_amountOfMagic >= TWENTY_MAGIC) {
                ISamuRiseQuest(questContract).increaseTokenIdToDojoRarityBonus(_landTokenId, 1);
            }
            if(_amountOfMagic == FIFTY_MAGIC){
                if(ISamuRiseItems(itemsContract).getTokenSupply(itemCollectionIdToMint) == ISamuRiseItems(itemsContract).getTokenMaxSupply(itemCollectionIdToMint)){
                    ISamuRiseQuest(questContract).increaseTokenIdToDojoRarityBonus(_landTokenId, 1);
                } else {
                    ISamuRiseQuest(questContract).mintItem(msg.sender, itemCollectionIdToMint, 1, 1);
                }
            }
        } else if (diceRoll == 3) {
            if(_amountOfMagic >= THIRTY_MAGIC) {
                ISamuRiseQuest(questContract).increaseTokenIdToDojoRarityBonus(_landTokenId, 1);
            }
        } else if (diceRoll == 4) {
            if(_amountOfMagic >= THIRTY_MAGIC) {
                ISamuRiseQuest(questContract).increaseTokenIdToDojoRarityBonus(_landTokenId, 1);
            }
        }

        ISamuRiseQuest(questContract).setLandTokenIdFactionAndProvince(_landTokenId, _faction, province);
        tokenIdToHasPlantedFlag[_landTokenId] = true;

    }


    /* OWNER FUNCTIONS */
    function withdrawToken(address _to, uint256 _amount) external onlyOwner {
        IERC20 tokenContract = IERC20(magicContract);
        
        tokenContract.transfer(_to, _amount);
    }

    function setFactionToFlagsPlantedCount(uint8 _factionId, uint256 _numberPlanted) external onlyOwner {
        factionToFlagsPlantedCount[_factionId] = _numberPlanted;
    }

    function setItemCollectionIdToMint(uint256 _collectionId) external onlyOwner {
        itemCollectionIdToMint = _collectionId;
    }

    function setQuestContract(address _address) external onlyOwner {
        questContract = _address;
    }

    function setLandContract(address _address) external onlyOwner {
        landContract = _address;
    }

    function setItemsContract(address _address) external onlyOwner {
        itemsContract = _address;
    }

    function setTreasuryWallet(address _address) external onlyOwner {
        treasuryWallet = _address;
    }

    function setDiceContract(address _address) external onlyOwner {
        diceRNGContract = _address;
    }


    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }


    function _authorizeUpgrade(address) internal override onlyOwner {}
}
