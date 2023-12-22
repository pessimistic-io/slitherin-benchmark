//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { TreasureClaimerAdmin, Initializable, ClaimInfo, ITreasureBadges } from "./TreasureClaimerAdmin.sol";
import { ECDSAUpgradeable } from "./ECDSAUpgradeable.sol";
import { EIP712Upgradeable } from "./draft-EIP712Upgradeable.sol";

contract TreasureClaimer is Initializable, EIP712Upgradeable, TreasureClaimerAdmin {
    using ECDSAUpgradeable for bytes32;

    function initialize(address _signingAuthority, address _badgeAddress) external initializer {
        __TreasureClaimerAdmin_init();
        __EIP712_init("TreasureClaimer", "1.0.0");
        signingAuthority = _signingAuthority;
        treasureBadgeCollection = ITreasureBadges(_badgeAddress);
    }

    function _claim(ClaimInfo calldata _claimInfo, bytes memory _authoritySignature) private {
        if (_claimInfo.claimer != msg.sender) {
            revert NotRecipient();
        }

        bytes32 claimToHash = claimInfoHash(_claimInfo);
        address signer = claimToHash.recover(_authoritySignature);
        if (signer != signingAuthority) {
            revert InvalidSignature(signer);
        }
        if (isClaimed(_claimInfo)) {
            revert BadgeAlreadyClaimed(
                _claimInfo.claimer, _claimInfo.badgeAddress, _claimInfo.badgeId, _claimInfo.nonce
            );
        }

        _setIsClaimed(_claimInfo, true);
        treasureBadgeCollection.adminMint(msg.sender, _claimInfo.badgeId);

        emit BadgeClaimed(_claimInfo.claimer, _claimInfo.badgeAddress, _claimInfo.badgeId, _claimInfo.nonce);
    }

    function claim(ClaimInfo calldata _claimInfo, bytes memory _authoritySignature) external override whenNotPaused {
        _claim(_claimInfo, _authoritySignature);
    }

    function claimBatch(
        ClaimInfo[] calldata _claimInfos,
        bytes[] memory _authoritySignatures
    ) external override whenNotPaused {
        require(_claimInfos.length > 0, "No claim params given");
        require(_claimInfos.length == _authoritySignatures.length, "Bad number of signatures");

        for (uint256 i = 0; i < _claimInfos.length; i++) {
            _claim(_claimInfos[i], _authoritySignatures[i]);
        }
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
                    _claimInfo.badgeAddress,
                    _claimInfo.badgeId,
                    _claimInfo.nonce
                )
            )
        );
    }
}

