// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./SakabaERC1155Token.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./FactorySignatureVerifier.sol";
import "./ISignerProvider.sol";

contract SakabaTokenFactory is ISignerProvider, Ownable {
    // contractId to contract address
    mapping(uint => SakabaERC1155Token) public contracts;
    address private _signer;
    uint[] private _contractIds;
    FactorySignatureVerifier verifier = new FactorySignatureVerifier();

    function make1155Contract(
        string memory name,
        string memory url,
        uint contractId,
        address contractOwner,
        bytes memory signature
    ) public {
        require(contractOwner == msg.sender, "msg.sender is not the owner");
        require(
            address(contracts[contractId]) == address(0),
            "duplicated contractId"
        );
        require(
            verifier.verify(
                block.chainid,
                contractId,
                contractOwner,
                getSigner(),
                signature
            ) == true,
            "invalid signature"
        );

        SakabaERC1155Token token = new SakabaERC1155Token();
        token.__sakabaToken_init(name, url, this);
        token.transferOwnership(msg.sender);

        contracts[contractId] = token;
        _contractIds.push(contractId);
    }

    function getContractIds() public view returns (uint[] memory) {
        return _contractIds;
    }

    function getSigner() public view returns (address) {
        return _signer;
    }

    function setSigner(address newSigner) public onlyOwner {
        _signer = newSigner;
    }
}

