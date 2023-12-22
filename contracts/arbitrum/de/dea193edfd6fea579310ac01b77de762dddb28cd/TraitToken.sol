// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/*

TraitToken.sol

Written by: mousedev.eth

*/

import "./ERC1155Upgradeable.sol";
import "./IERC721.sol";
import "./AccessControlEnumerableUpgradableV2.sol";
import "./ISmolsTraitStorage.sol";
import "./SmolsAddressRegistryConsumer.sol";
import "./ISmolsState.sol";
import "./SmolsLibrary.sol";

contract TraitToken is AccessControlEnumerableUpgradableV2, ERC1155Upgradeable {
    bytes32 internal constant TRAIT_TOKEN_ADMIN_ROLE =  keccak256("TRAIT_TOKEN_ADMIN");

    ISmolsAddressRegistry smolsAddressRegistry;

    bytes maleEmptyBytes;
    bytes femaleEmptyBytes;

    function initialize() public initializer {
        __ERC1155_init("");
        __AccessControlEnumerableV2_init();

        _grantRole(TRAIT_TOKEN_ADMIN_ROLE, msg.sender);
    }

    
    /// @dev Sets the smols address registry address.
    /// @param _smolsAddressRegistry The address of the registry.
    function setSmolsAddressRegistry(address _smolsAddressRegistry) external requiresEitherRole(OWNER_ROLE, SMOLS_ADDRESS_REGISTRY_ADMIN_ROLE) {
        smolsAddressRegistry = ISmolsAddressRegistry(_smolsAddressRegistry);
    }


    function getSelectorForType(bytes memory _traitType) internal pure returns(bytes4) {
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Background"))) return ISmolsState.setBackground.selector;
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Body"))) return ISmolsState.setBody.selector;
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Clothes"))) return ISmolsState.setClothes.selector;
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Mouth"))) return ISmolsState.setMouth.selector;
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Glasses"))) return ISmolsState.setGlasses.selector;
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Hat"))) return ISmolsState.setHat.selector;
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Hair"))) return ISmolsState.setHair.selector;
        if (keccak256(_traitType) == keccak256(abi.encodePacked("Skin"))) return ISmolsState.setSkin.selector;
        revert("No matching selector for type.");
    }

    function equipTraitOnSmol(uint256 _traitId, uint256 _smolId, bytes4 _selector) internal returns (bool, uint24){
        //Pull the smols state address from the registry.
        address smolsStateAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSSTATEADDRESS);

        //TODO
        //Pull gender from trait data
        //If its 0, use male and allow equip
        //If its 1 or 2, use relevant image and only allow that gender to equip

        bytes memory callData = abi.encodeWithSelector(_selector, _smolId, _traitId);

        //Call the set trait function to set the new trait.
        (bool success, bytes memory data) = smolsStateAddress.call(callData);

        //Decode the return data to see if we overwrote a trait, and what the id was if we did.
        (bool _overWritten, uint24 _previousTraitId) = abi.decode(data, (bool, uint24));

        return (_overWritten, _previousTraitId);
    }

    function _mintTraitToken(uint256 _traitId, address _user) internal {
        _mint(_user, _traitId, 1, bytes(""));
    }

    function mintTraitTokens(uint256[] calldata _traitIds, address _user) public onlyRole(TRAIT_TOKEN_ADMIN_ROLE) {
        for(uint256 i = 0; i <_traitIds.length; i++){
            _mintTraitToken(_traitIds[i], _user);
        }
    }

    function equipTraits(uint256[] calldata _traitIds, uint256[] calldata _smolIds) public {

        address smolsTraitStorageAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSTRAITSTORAGEADDRESS);
        address smolsAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSADDRESS);
        
        for(uint256 i = 0;i<_traitIds.length;i++){
            //Require they own the smol they are modifying.
            require(IERC721(smolsAddress).ownerOf(_smolIds[i]) == msg.sender, "Not the owner of this smol.");
            
            //Burn the traitId they want to equip
            _burn(msg.sender, _traitIds[i], 1);
            
            //Get the trait type of the trait they are equipping, so you can properly set it.
            bytes memory _traitType = ISmolsTraitStorage(smolsTraitStorageAddress).getTraitType(_traitIds[i],0);
            
            //Pull the selector of this trait type.
            bytes4 _selector = getSelectorForType(_traitType);
            
            //Call function to equip the trait.
            (bool _overWritten, uint24 _previousTraitId) = equipTraitOnSmol(_traitIds[i], _smolIds[i], _selector);
            
            //If we overwrote a trait, check if we should mint it, then mint it.
            if(_overWritten){
                //Pull whether the previous trait was detachable.
                bool isDetachable = ISmolsTraitStorage(smolsTraitStorageAddress).getIsDetachable(_previousTraitId, 0);
                
                //If it was, mint them the 1155.
                if(isDetachable) _mintTraitToken(_previousTraitId, msg.sender);
            }
        }
    }

    function unequipTraits(bytes[] calldata _traitTypes, uint256[] calldata _smolIds) public {
        address smolsTraitStorageAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSTRAITSTORAGEADDRESS);
        address smolsAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSADDRESS);

        for(uint256 i = 0; i < _traitTypes.length; i++){
            //Require they own the smol they are modifying.
            require(IERC721(smolsAddress).ownerOf(_smolIds[i]) == msg.sender, "Not the owner of this smol.");

            //Pull the selector of this trait type.
            bytes4 _selector = getSelectorForType(_traitTypes[i]);

            //Call function to equip the trait.
            (bool _overWritten, uint24 _previousTraitId) = equipTraitOnSmol(0, _smolIds[i], _selector);

            //If we overwrote a trait, check if we should mint it, then mint it.
            if(_overWritten){
                //Pull whether the previous trait was detachable.
                bool isDetachable = ISmolsTraitStorage(smolsTraitStorageAddress).getIsDetachable(_previousTraitId, 0);

                //If it was, mint them the 1155.
                if(isDetachable) _mintTraitToken(_previousTraitId, msg.sender);
            }
        }
    }

    function uri(uint256 _traitId) public view override returns(string memory) {
        address smolsTraitStorageAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSTRAITSTORAGEADDRESS);

        Trait memory _traitData = ISmolsTraitStorage(smolsTraitStorageAddress).getTrait(_traitId, 0);
        bytes memory imageBytes;
        bytes memory emptySmolBytes;

        if(_traitData.gender == 0) imageBytes = _traitData.pngImage.male;
        if(_traitData.gender == 1) imageBytes = _traitData.pngImage.male;
        if(_traitData.gender == 2) imageBytes = _traitData.pngImage.female;

        if(_traitData.gender == 0) emptySmolBytes = maleEmptyBytes;
        if(_traitData.gender == 1) emptySmolBytes = maleEmptyBytes;
        if(_traitData.gender == 2) emptySmolBytes = femaleEmptyBytes;

        if(keccak256(_traitData.traitType) == keccak256(abi.encodePacked("Background"))){
            //If it is a background, reverse the order
            imageBytes = abi.encodePacked(
                    emptySmolBytes,
                    '),url(',
                    imageBytes
            );
        } else {
            //If it is not, keep order the same
            imageBytes = abi.encodePacked(
                    imageBytes,
                    '),url(',
                    emptySmolBytes
            );
        }


        string memory metadata = string(abi.encodePacked(
            '{"name": "',
            _traitData.traitName,
            '", "description": "Equippable trait for any smol.',
            '","image": "data:image/svg+xml;base64,',
            SmolsLibrary.encode(
                abi.encodePacked(
                    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" id="smol" width="100%" height="100%" version="1.1" viewBox="0 0 360 360" ',
                    'style="background-color: transparent;background-image:url(',
                    imageBytes,
                    ')"'
                    ">",
                    "<style>#smol {background-repeat: no-repeat;background-size: contain;background-position: center;image-rendering: -webkit-optimize-contrast;-ms-interpolation-mode: nearest-neighbor;image-rendering: -moz-crisp-edges;image-rendering: pixelated;}</style></svg>"
                )
            ),
            '", "attributes": [',
            '{"trait_type":"',
            "Trait Type",
            '","value":"',
            _traitData.traitType,
            '"},',
            '{"trait_type":"',
            "Trait Name",
            '","value":"',
            _traitData.traitName,
            '"}',
            ']}'
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            SmolsLibrary.encode(bytes(metadata))
        ));
    }

    function setEmptyImages(bytes memory _maleEmptyBytes, bytes memory _femaleEmptyBytes) public onlyRole(OWNER_ROLE) {
        maleEmptyBytes = _maleEmptyBytes;
        femaleEmptyBytes = _femaleEmptyBytes;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerableUpgradeable, ERC1155Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
