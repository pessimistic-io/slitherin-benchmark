//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import { ECDSAUpgradeable } from "./ECDSAUpgradeable.sol";
import { EIP712Upgradeable } from "./draft-EIP712Upgradeable.sol";

import "./ConsumableClaimerContracts.sol";

struct ClaimInfo {
    address claimer;
    uint256 tokenId;
    uint256 quantity;
    bytes32 nonce;
}

contract ConsumableClaimer is Initializable, ConsumableClaimerContracts {

    using ECDSAUpgradeable for bytes32;

    function initialize() external initializer {
        ConsumableClaimerContracts.__ConsumableClaimerContracts_init();
    }

    function claim(ClaimInfo calldata _claimInfo, bytes memory _authoritySignature) external whenNotPaused contractsAreSet {
        require(_claimInfo.claimer == msg.sender, "Bad claimer");

        bytes32 _claimToHash = claimInfoHash(_claimInfo);
        address _signer = _claimToHash.recover(_authoritySignature);
        require(isAdmin(_signer), "Bad signature or signer not admin");
        require(!claimerToNonceToIsClaimed[_claimInfo.claimer][_claimInfo.nonce], "Nonce used already");

        claimerToNonceToIsClaimed[_claimInfo.claimer][_claimInfo.nonce] = true;

        consumable.mint(_claimInfo.claimer, _claimInfo.tokenId, _claimInfo.quantity);

        emit ConsumableClaimed(_claimInfo.claimer, _claimInfo.nonce);
    }

    function undoClaim(ClaimInfo calldata _claimInfo) external onlyAdminOrOwner {
        require(isClaimed(_claimInfo), "ConsumableClaimer: Cannot undo claim that didn't happen");
        claimerToNonceToIsClaimed[_claimInfo.claimer][_claimInfo.nonce] = false;
        emit ConsumableUnclaimed(_claimInfo.claimer, _claimInfo.nonce);
    }

    function isClaimed(ClaimInfo calldata _claimInfo) public view returns (bool) {
        return claimerToNonceToIsClaimed[_claimInfo.claimer][_claimInfo.nonce];
    }

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function claimInfoHash(ClaimInfo calldata _claimInfo) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CLAIMINFO_TYPE_HASH,
                    _claimInfo.claimer,
                    _claimInfo.tokenId,
                    _claimInfo.quantity,
                    _claimInfo.nonce
                )
            )
        );
    }
}
