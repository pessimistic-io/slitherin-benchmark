//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {     IERC20Upgradeable,     SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { TreasureClaimerAdmin, Initializable, ClaimInfo, ITreasureBadges, IPayments } from "./TreasureClaimerAdmin.sol";
import { ECDSAUpgradeable } from "./ECDSAUpgradeable.sol";
import { EIP712Upgradeable } from "./draft-EIP712Upgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

contract TreasureClaimer is Initializable, EIP712Upgradeable, TreasureClaimerAdmin {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ECDSAUpgradeable for bytes32;
    using AddressUpgradeable for address payable;

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

    function claim(
        ClaimInfo calldata _claimInfo,
        bytes memory _authoritySignature
    ) external payable override whenNotPaused {
        if (_claimInfo.priceInUSD > 0) {
            uint256 paymentAmount = IPayments(spellcaster).calculatePaymentAmountByPriceType(
                _claimInfo.paymentToken, // pay in ETH/MAGIC
                _claimInfo.priceInUSD, // priced in USD value
                IPayments.PriceType.PRICED_IN_USD, // pin to USD value
                address(0) // USD is not a token
            );
            if (_claimInfo.paymentToken == address(0)) {
                if (msg.value < paymentAmount) {
                    revert InsufficientValue();
                } else if (msg.value > paymentAmount) {
                    payable(msg.sender).sendValue(msg.value - paymentAmount);
                }
            } else {
                IERC20Upgradeable(_claimInfo.paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);
            }
        }
        _claim(_claimInfo, _authoritySignature);
    }

    function claimBatch(
        ClaimInfo[] calldata _claimInfos,
        bytes[] memory _authoritySignatures
    ) external payable override whenNotPaused {
        uint256 _numClaims = _claimInfos.length;
        require(_numClaims > 0, "No claim params given");
        require(_numClaims == _authoritySignatures.length, "Bad number of signatures");
        uint256 _totalPaymentRequired;
        address _paymentToken = _numClaims > 0 ? _claimInfos[0].paymentToken : address(0);

        for (uint256 i = 0; i < _claimInfos.length; i++) {
            if (_claimInfos[i].paymentToken != _paymentToken) {
                revert InvalidPaymentToken();
            }
            _totalPaymentRequired = _totalPaymentRequired + _claimInfos[i].priceInUSD;
            _claim(_claimInfos[i], _authoritySignatures[i]);
        }
        if (_totalPaymentRequired > 0) {
            uint256 paymentAmount = IPayments(spellcaster).calculatePaymentAmountByPriceType(
                _paymentToken, // pay in ETH/MAGIC
                _totalPaymentRequired, // priced in USD value
                IPayments.PriceType.PRICED_IN_USD, // pin to USD value
                address(0) // USD is not a token
            );
            if (_paymentToken == address(0)) {
                if (msg.value < paymentAmount) {
                    revert InsufficientValue();
                } else if (msg.value > paymentAmount) {
                    payable(msg.sender).sendValue(msg.value - paymentAmount);
                }
            } else {
                IERC20Upgradeable(_paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);
            }
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
                    _claimInfo.nonce,
                    _claimInfo.priceInUSD,
                    _claimInfo.paymentToken
                )
            )
        );
    }
}

