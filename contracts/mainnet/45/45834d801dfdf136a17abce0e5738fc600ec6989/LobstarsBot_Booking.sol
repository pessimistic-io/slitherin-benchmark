// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

/*
      __       _____      _____    _____    _____    _______   ______  
     /\_\     ) ___ (   /\  __/\ /\  __/\  ) ___ ( /\_______)\/ ____/\ 
    ( ( (    / /\_/\ \  ) )(_ ) )) )(_ ) )/ /\_/\ \\(___  __\/) ) __\/ 
     \ \_\  / /_/ (_\ \/ / __/ // / __/ // /_/ (_\ \ / / /     \ \ \   
     / / /__\ \ )_/ / /\ \  _\ \\ \  _\ \\ \ )_/ / /( ( (      _\ \ \  
    ( (_____(\ \/_\/ /  ) )(__) )) )(__) )\ \/_\/ /  \ \ \    )____) ) 
     \/_____/ )_____(   \/____\/ \/____\/  )_____(   /_/_/    \____\/  
                                                          
    The Lobstarbots All Rights Reserved 2022
    Developed by ATOMICON.PRO (info@atomicon.pro)
*/

import "./IERC721A.sol";

import "./Ownable.sol";
import "./ECDSA.sol";

contract LobstarbotsBooking is Ownable {

    error InvalidBookingSlotIndex();
    error NotATokenHolder();
    error SlotAlreadyTaken();

    error HashComparisonFailed();
    error UntrustedSigner();
    error HashAlreadyUsed();
    error SignatureNoLongerValid();
    
    event SlotBooked(uint256 tokenId, uint64 indexed bookedSlotId, uint64 freedSlotId);

    IERC721A private immutable _lobstarBotsContract;

    mapping(uint64 => uint256) private _bookingSlots;
    mapping(uint256 => uint64) private _tokenBookingSlotId;
    uint64 private _bookingSlotsCount;

    bytes8 private constant _hashSalt = 0x9a6f9334e0a49511;
    address private constant _signerAddress = 0x542eA56F66bbCe7A7704b96fB130f08C03306061;
    mapping(uint64 => bool) private _usedNonces;

    constructor(IERC721A lobstarBotsContract) {
        _lobstarBotsContract = lobstarBotsContract;
    }

    // @notice Book a timeslot using a token you own
    function bookSlot(bytes32 hash, bytes calldata signature, uint64 signatureValidityTimestamp, uint64 nonce, uint256 tokenId, uint64 slotId) external {
        if (slotId > _bookingSlotsCount || slotId < 1) revert InvalidBookingSlotIndex();
        if (_lobstarBotsContract.ownerOf(tokenId) != msg.sender) revert NotATokenHolder();
        if (_bookingSlots[slotId] != 0) revert SlotAlreadyTaken();

        if (signatureValidityTimestamp < block.timestamp) revert SignatureNoLongerValid();
        if (_bookOperationHash(msg.sender, slotId, signatureValidityTimestamp, nonce) != hash) revert HashComparisonFailed();
        if (!_isTrustedSigner(hash, signature)) revert UntrustedSigner();
        if (_usedNonces[nonce]) revert HashAlreadyUsed();

        uint64 oldBookingSlotId = _tokenBookingSlotId[tokenId];
        _bookingSlots[oldBookingSlotId] = 0;

        _bookingSlots[slotId] = tokenId;
        _tokenBookingSlotId[tokenId] = slotId;

        _usedNonces[nonce] = true;

        emit SlotBooked(tokenId, slotId, oldBookingSlotId);
    }

    // @notice Set the count of slots available for booking
    function setBookingSlotsCount(uint64 bookingSlotsCount) external onlyOwner {
        _bookingSlotsCount = bookingSlotsCount;
    }

    // @notice Get a booked timeslot of a token. Notice, that booking slot ids begin with 1
    function tokenBookingSlotId(uint256 tokenId) external view returns(uint64) {
        return _tokenBookingSlotId[tokenId];
    }

    /// @notice Get booking slots of all tokens
    function getBookingSlots() external view returns(uint256[] memory) {
        uint256[] memory bookingSlotsTokenIds = new uint256[](_bookingSlotsCount);

        for(uint64 id = 1; id <= _bookingSlotsCount; id++) {
            bookingSlotsTokenIds[id-1] = _bookingSlots[id];
        }

        return bookingSlotsTokenIds;
    }

    /// @dev Generate hash of current slot booking operation
    function _bookOperationHash(address owner, uint64 slotId, uint64 validityTimestamp, uint64 nonce) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            _hashSalt,
            owner,
            block.chainid,
            slotId,
            validityTimestamp,
            nonce
        ));
    }

    /// @dev Check, whether a message was signed by a trusted address
    function _isTrustedSigner(bytes32 hash, bytes memory signature) internal pure returns (bool) {
        return _signerAddress == ECDSA.recover(hash, signature);
    }
}
