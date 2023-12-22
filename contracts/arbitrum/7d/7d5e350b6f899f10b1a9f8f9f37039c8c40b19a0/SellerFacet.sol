// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AppStorage, LibAppStorage, Modifiers} from "./LibAppStorage.sol";
import {BonkStorage, LibBonkStorage} from "./LibBonkStorage.sol";
import {ECDSA} from "./ECDSA.sol";
import {ReferralStorage, LibReferralStorage} from "./LibReferralStorage.sol";

import {LibMeta} from "./LibMeta.sol";

import {FacetCommons} from "./FacetCommons.sol";

contract SellerFacet is FacetCommons, Modifiers {
    using ECDSA for bytes32;
    event Attack(
        uint256 attacker,
        uint256 winner,
        uint256 loser,
        uint256 scoresWon
    );

    error InvalidBuySignature();
    event BornPet(uint256 petId, string petName, uint256 petTypeId, uint256 timePetBorn,uint256 timeUntilStarving, address owner);

    function setBonkSigner(address newBonkSigner) external onlyOwner {
        BonkStorage storage s = LibBonkStorage.bonkStorage();
        s.bonkSigner = newBonkSigner;
    }

    function mint(uint256 petTypeId, uint256 price, bytes32 nonce, address refAddress, string calldata name, bytes calldata signature) external {
        AppStorage storage s = LibAppStorage.appStorage();

        if (!_signatureMatch(petTypeId, price, nonce, signature) || s.nonces[nonce]) {
            revert InvalidBuySignature();
        }

        ReferralStorage storage r = LibReferralStorage.referralStorage();
        uint256 petId = s._tokenIds;

        require(petId < 20_000, "Over the limit");


        s.token.burnFrom(msg.sender, price);

        s.petName[petId] = name;
        s.timeUntilStarving[petId] = block.timestamp + 1 days;
        s.timePetBorn[petId] = block.timestamp;
        s.petType[petId] = petTypeId;

        r.petToRef[petId] = refAddress;

        // mint NFT
        s.nft.mint(msg.sender);
        s._tokenIds++;
        
        s.nonces[nonce] = true;
        
        
        emit BornPet(petId, name, petTypeId, s.timePetBorn[petId], s.timeUntilStarving[petId], msg.sender);
    }

    function _signatureMatch(
        uint256 petTypeId,
        uint256 price,
        bytes32 nonce,
        bytes calldata signature
    ) internal view returns (bool) {
        BonkStorage storage s = LibBonkStorage.bonkStorage();

        bytes32 message = keccak256(abi.encode(petTypeId, price, nonce))
            .toEthSignedMessageHash();

        address signer = message.recover(signature);

        return signer == s.bonkSigner;
    }

}
