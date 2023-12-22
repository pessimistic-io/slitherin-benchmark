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
import "./INilERC721V2.sol";
import "./INil.sol";
import "./INOwnerResolver.sol";
import "./NilERC721TemplateV2.sol";

contract NilERC721FactoryV1 is Initializable {

    address public nftImplementation;
    address public dao;
    address public operator;
    INil public nil;
    INOwnerResolver public nOwnerResolver;
    address public signer;
    uint256 public nftContractIdCounter;
    uint256 public protocolFeesInBPS;

    event Created(uint256 nftContractIdCounter, address clone);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        address dao_,
        address nil_,
        address nOwnerResolver_,
        address signer_,
        address operator_,
        address nilERC721TemplateV2_,
        uint256 protocolFeesInBPS_
    ) public initializer {
        require(dao_ != address(0), "NIL:ILLEGAL_ADDRESS");
        require(nil_ != address(0), "NIL:ILLEGAL_ADDRESS");
        require(nOwnerResolver_ != address(0), "NIL:ILLEGAL_ADDRESS");
        require(signer_ != address(0), "NIL:ILLEGAL_ADDRESS");
        require(operator_ != address(0), "NIL:INVALID_OPERATOR_ADDRESS");
        require(nilERC721TemplateV2_ != address(0), "NIL:INVALID_TEMPLATE_ADDRESS");
        require(protocolFeesInBPS_ <= 100, "NIL:FEES_TOO_HIGH");
        dao = dao_;
        nil = INil(nil_);
        nOwnerResolver = INOwnerResolver(nOwnerResolver_);
        signer = signer_;
        operator = operator_;
        protocolFeesInBPS = protocolFeesInBPS_;
        nftImplementation = nilERC721TemplateV2_;
    }

    function createERC721Contract(
        string calldata name,
        string calldata symbol,
        address owner,
        INilERC721V2.NftParameters calldata nftParameters_
    ) external returns (address) {
        address clone = ClonesUpgradeable.clone(nftImplementation);
        NilERC721TemplateV2(clone).initialize(
            name,
            symbol,
            nftParameters_,
            owner,
            protocolFeesInBPS,
            INilERC721V2.ContractAddresses(nil, dao, operator, nOwnerResolver, signer)
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

}

