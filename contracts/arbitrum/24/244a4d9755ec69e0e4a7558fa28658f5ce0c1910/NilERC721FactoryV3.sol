// SPDX-License-Identifier: MIT
/**
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(     (@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(   @@@@@@@@@@@@@@@@@@@@(            @@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@         @@@@@@@@@@@@@@@             @@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @@@@@@@@@@@(            @@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@      @@@@@@@@@@@@             @@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@(            @@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@     @@@@@@@     @@@@@@@             @@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@(         @@(         @@(            @@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@          @@          @@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@     @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@ @@@@@@@@@@@ @@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(     @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           @           @           @@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@(            @@@         @@@         @@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@             @@@@@@@     @@@@@@@     @@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@(            @@@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@             @@@@@@@@@@@       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@(            @@@@@@@@@@@@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@             @@@@@@@@@@@@@@@         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@(            @@@@@@@@@@@@@@@@@@@@@   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@(     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@ @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 */
pragma solidity 0.8.11;

import "./ClonesUpgradeable.sol";
import "./Initializable.sol";
import "./INilERC721V1.sol";
import "./INil.sol";
import "./INOwnerResolver.sol";
import "./NilERC721TemplateV1.sol";

contract NilERC721FactoryV3 is Initializable {

    address public nftImplementation;
    address public dao;
    address public operator;
    address public signer;
    uint256 public nftContractIdCounter;
    uint256 public protocolFeesInBPS;

    event Created(uint256 nftContractIdCounter, address clone);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        address dao_,
        address signer_,
        address operator_,
        address nilERC721TemplateV1_,
        uint256 protocolFeesInBPS_
    ) public initializer {
        require(dao_ != address(0), "NIL:ILLEGAL_ADDRESS");
        require(signer_ != address(0), "NIL:ILLEGAL_ADDRESS");
        require(operator_ != address(0), "NIL:INVALID_OPERATOR_ADDRESS");
        require(nilERC721TemplateV1_ != address(0), "NIL:INVALID_TEMPLATE_ADDRESS");
        require(protocolFeesInBPS_ <= 100, "NIL:FEES_TOO_HIGH");
        dao = dao_;
        signer = signer_;
        operator = operator_;
        protocolFeesInBPS = protocolFeesInBPS_;
        nftImplementation = nilERC721TemplateV1_;
    }

    function createERC721Contract(
        string calldata name,
        string calldata symbol,
        address owner,
        INilERC721V1.NftParameters calldata nftParameters_
    ) external returns (address) {
        address clone = ClonesUpgradeable.clone(nftImplementation);
        NilERC721TemplateV1(clone).initialize(
            name,
            symbol,
            nftParameters_,
            owner,
            protocolFeesInBPS,
            INilERC721V1.ContractAddresses(dao, operator, signer)
        );
        emit Created(nftContractIdCounter, clone);
        nftContractIdCounter++;
        return clone;
    }

    function setProtocolFeesInBPS(uint256 protocolFeesInBPS_) external {
        require(msg.sender == dao, "NIL:ONLY_DAO_CAN_SET_PROTOCOL_FEES");
        require(protocolFeesInBPS_ <= 100, "NIL:FEES_TOO_HIGH");
        protocolFeesInBPS = protocolFeesInBPS_;
    }

    function setOperator(address operator_) external {
        require(msg.sender == dao, "NIL:ONLY_DAO_CAN_SET_OPERATOR_ADDRESS");
        require(operator_ != address(0), "NIL:INVALID_OPERATOR_ADDRESS");
        operator = operator_;
    }

    function setNFTTemplate(address nftImplementation_) external {
        require(msg.sender == dao, "NIL:ONLY_DAO_CAN_SET_OPERATOR_ADDRESS");
        require(nftImplementation_ != address(0), "NIL:INVALID_NFT_IMPLEMENTATION_ADDRESS");
        nftImplementation = nftImplementation_;
    }

}

