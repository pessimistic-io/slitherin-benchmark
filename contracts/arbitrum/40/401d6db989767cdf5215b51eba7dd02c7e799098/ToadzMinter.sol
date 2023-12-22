//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./MerkleProofUpgradeable.sol";

import "./ToadzMinterSettings.sol";

contract ToadzMinter is Initializable, ToadzMinterSettings {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        ToadzMinterSettings.__ToadzMinterSettings_init();
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdminOrOwner {
        merkleRoot = _merkleRoot;
    }

    function setMaxBatchSize(uint8 _maxBatchSize) external onlyAdminOrOwner {
        maxBatchSize = _maxBatchSize;
    }

    function startMintingMultisigToadz(
        uint256 _amount)
    external
    onlyEOA
    onlyAdminOrOwner
    {
        _createBatchesForUser(MULTISIG_ADDRESS, _amount);
    }

    function finishMintingMultisigToadz(
        uint8 _maxBatches)
    external
    onlyEOA
    onlyAdminOrOwner
    {
        _finishMintingToadzForUser(MULTISIG_ADDRESS, _maxBatches);
    }

    function startMintingToadz(
        bytes32[] calldata _proof,
        uint256 _amount)
    external
    whenNotPaused
    onlyEOA
    {
        require(
            !addressToHasClaimed[msg.sender],
            "ToadzMinter: Already claimed Toadz"
        );

        bytes32 _leaf = keccak256(abi.encodePacked(msg.sender, _amount));

        require(
            MerkleProofUpgradeable.verify(_proof, merkleRoot, _leaf),
            "ToadzMinter: Proof invalid"
        );

        addressToHasClaimed[msg.sender] = true;

        // Get badge for whitelist
        badgez.mintIfNeeded(msg.sender, whitelistBadgeId);

        _createBatchesForUser(msg.sender, _amount);
    }

    function _createBatchesForUser(address _user, uint256 _amount) private {
        uint256 _amountLeft = _amount;

        while(_amountLeft > 0) {
            uint256 _batchSize = _amountLeft > maxBatchSize ? maxBatchSize : _amountLeft;

            _amountLeft -= _batchSize;

            uint256 _requestId = randomizer.requestRandomNumber();
            addressToRequestIds[_user].add(_requestId);
            requestIdToBatchSize[_requestId] = _batchSize;

            emit MintingToadzStarted(_user, _batchSize, _requestId);
        }
    }

    function finishMintingToadz()
    external
    whenNotPaused
    onlyEOA
    {
        _finishMintingToadzForUser(msg.sender, 1);
    }

    function _finishMintingToadzForUser(address _user, uint8 _maxBatches) private {
        uint256[] memory _requestIds = addressToRequestIds[_user].values();

        require(_requestIds.length > 0, "ToadzMinter: Nothing to finish");

        uint8 _processedRequests = 0;

        for(uint256 i = 0; i < _requestIds.length; i++) {
            if(!randomizer.isRandomReady(_requestIds[i])) {
                continue;
            }

            addressToRequestIds[_user].remove(_requestIds[i]);

            _processedRequests++;

            uint256 _randomNumber = randomizer.revealRandomNumber(_requestIds[i]);
            uint256 _batchSize = requestIdToBatchSize[_requestIds[i]];
            uint256 _regularAxes = 0;
            uint256 _goldenAxes = 0;

            for(uint256 j = 0; j < _batchSize; j++) {
                // Need to ensure each mint is using a different random number. Otherwise, they would all be the same
                if(j != 0) {
                    _randomNumber = uint256(keccak256(abi.encode(_randomNumber, j)));
                }

                _regularAxes += axesPerToad;

                uint256 _goldenAxeResult = _randomNumber % 256;
                if(_goldenAxeResult < chanceGoldenAxePerToad) {
                    _goldenAxes++;
                    _regularAxes--;
                }

                // Only use 8 bits for the random calculation.
                ToadTraits memory _traits = _pickTraits(_randomNumber >> 8);

                toadz.mint(
                    _user,
                   _traits
                );
            }

            if(_regularAxes > 0) {
                itemz.mint(_user, regularAxeId, _regularAxes);
            }
            if(_goldenAxes > 0) {
                itemz.mint(_user, goldenAxeId, _goldenAxes);
            }

            emit MintingToadzFinished(_user, _batchSize, _requestIds[i]);

            if(_processedRequests >= _maxBatches) {
                break;
            }
        }

        // Revert here. We do not want users to waste gas on a request if nothing is ready.
        require(_processedRequests > 0, "ToadzMinter: No requests are ready");
    }

    function _pickTraits(uint256 _randomNumber) private view returns(ToadTraits memory _toadTraits) {
        _toadTraits.rarity = ToadRarity.COMMON;

        _toadTraits.background = ToadBackground(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.BACKGROUND],
            traitTypeToAliases[ToadTraitConstants.BACKGROUND]));
        _randomNumber >>= 16;

        _toadTraits.mushroom = ToadMushroom(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.MUSHROOM],
            traitTypeToAliases[ToadTraitConstants.MUSHROOM]));
        _randomNumber >>= 16;

        _toadTraits.skin = ToadSkin(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.SKIN],
            traitTypeToAliases[ToadTraitConstants.SKIN]));
        _randomNumber >>= 16;

        _toadTraits.clothes = ToadClothes(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.CLOTHES],
            traitTypeToAliases[ToadTraitConstants.CLOTHES]));
        _randomNumber >>= 16;

        _toadTraits.mouth = ToadMouth(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.MOUTH],
            traitTypeToAliases[ToadTraitConstants.MOUTH]));
        _randomNumber >>= 16;

        _toadTraits.eyes = ToadEyes(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.EYES],
            traitTypeToAliases[ToadTraitConstants.EYES]));
        _randomNumber >>= 16;

        _toadTraits.item = ToadItem(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.ITEM],
            traitTypeToAliases[ToadTraitConstants.ITEM]));
        _randomNumber >>= 16;

        _toadTraits.head = ToadHead(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.HEAD],
            traitTypeToAliases[ToadTraitConstants.HEAD]));
        _randomNumber >>= 16;

        _toadTraits.accessory = ToadAccessory(
            _pickTrait(uint16(_randomNumber & 0xFFFF),
            traitTypeToRarities[ToadTraitConstants.ACCESSORY],
            traitTypeToAliases[ToadTraitConstants.ACCESSORY]));
    }

    function _pickTrait(
        uint16 _randomNumber,
        uint8[] storage _rarities,
        uint8[] storage _aliases)
    private
    view
    returns(uint8)
    {
        uint8 _trait = uint8(_randomNumber) % uint8(_rarities.length);

        // If a selected random trait probability is selected, return that trait
        if(_randomNumber >> 8 < _rarities[_trait]) {
            return _trait;
        } else {
            return _aliases[_trait];
        }
    }

    function requestIdsForUser(address _user) external view returns(uint256[] memory) {
        return addressToRequestIds[_user].values();
    }

}
