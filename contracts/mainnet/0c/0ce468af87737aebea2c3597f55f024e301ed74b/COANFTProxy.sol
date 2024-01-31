// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Address.sol";
import "./Ownable.sol";
import "./ECDSA.sol";
import "./IERC721.sol";
import "./SCOA.sol";

interface ICOA {
    function createCertificate(
        address to_,
        SCOA.Certificate calldata certificate_,
        bytes calldata signature_
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
}

contract COANFTProxy is Ownable {
    using ECDSA for bytes32;
    using Address for address;

    struct Payment {
        uint256 amount;
        bytes32 nonce;
        bytes signature;
    }
    mapping(bytes32 => bool) public payments;

    ICOA internal _coa;

    constructor(address coa_) {
        _coa = ICOA(coa_);
    }

    function updateCOA(address coa_) external onlyOwner {
        _coa = ICOA(coa_);
    }

    // we create a new certificate and mint the NFT, sending both to the new owner
    /*
     * caller can be purchaser or coa creator
     */
    function digitalArtCreate(
        address to_,
        SCOA.Certificate calldata certificate_,
        bytes calldata signature_,
        address nftContract_,
        bytes calldata contractFunctionData_,
        Payment calldata payment_
    ) external payable {
        uint256 nftPrice = (msg.value - payment_.amount);
        require(nftContract_.isContract(), "NFT contract is not a contract");
        require(contractFunctionData_.length > 0, "NFT contract function data is empty");
        _coa.createCertificate(to_, certificate_, signature_);
        nftContract_.functionCallWithValue(contractFunctionData_, nftPrice);
        bytes32 dataHash = keccak256(
            abi.encode(to_, signature_, nftContract_, contractFunctionData_)
        );
        _payment(payment_, dataHash);
    }

    // we are transfering certificate and a NFT to the new owner
    /*
     * caller must be coa creator
     */
    function digitalArtTransfer(
        address to_,
        address certFrom_,
        uint256 certificateId_,
        address nftContract_,
        address nftFrom_,
        uint256 nftId_,
        Payment calldata payment_
    ) external payable {
        require(nftContract_.isContract(), "NFT contract is not a contract");
        _coa.safeTransferFrom(certFrom_, to_, certificateId_, 1, "");
        IERC721(nftContract_).safeTransferFrom(nftFrom_, to_, nftId_);
        bytes32 dataHash = keccak256(
            abi.encode(to_, certFrom_, certificateId_, nftContract_, nftFrom_, nftId_)
        );
        _payment(payment_, dataHash);
    }

    // we are transferring certificate to the physical art owner
    /*
     * caller must be coa creator
     */
    function physicalArtTransfer(
        address to_,
        address certFrom_,
        uint256 certificateId_,
        Payment calldata payment_
    ) external payable {
        _coa.safeTransferFrom(certFrom_, to_, certificateId_, 1, "");
        bytes32 dataHash = keccak256(abi.encode(to_, certFrom_, certificateId_));
        _payment(payment_, dataHash);
    }

    function makePayment(
        uint256 amount_,
        bytes32 nonce_,
        bytes calldata signature_
    ) public pure returns (Payment memory) {
        return Payment(amount_, nonce_, signature_);
    }

    function _payment(Payment calldata payment_, bytes32 dataHash_) internal {
        require(payment_.nonce == dataHash_, "Invalid nonce");
        address signer = payment_.nonce.toEthSignedMessageHash().recover(payment_.signature);
        require(signer == owner(), "Invalid signature");
        require(!payments[dataHash_], "Payment already processed");
        payments[dataHash_] = true;
        require(address(this).balance >= payment_.amount, "Insufficient funds");
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }
}

