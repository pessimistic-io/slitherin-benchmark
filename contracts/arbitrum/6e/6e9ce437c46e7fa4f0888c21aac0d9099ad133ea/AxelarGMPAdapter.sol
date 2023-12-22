pragma solidity ^0.8.17;

import { AxelarExecutable } from "./AxelarExecutable.sol";
import { OracleAdapter } from "./OracleAdapter.sol";

struct AxelarGMPAdapterDomainParams {
    uint256 domain;
    string domainName;
    string headerReporter;
}

contract AxelarGMPAdapter is OracleAdapter, AxelarExecutable {
    mapping(string => uint256) public domainNameToDomainId;
    mapping(uint256 => bytes32) public domainToHeaderReporterHash;

    constructor(address gateway, AxelarGMPAdapterDomainParams[] memory _domainsParams) AxelarExecutable(gateway) {
        for (uint256 i = 0; i < _domainsParams.length; i++) {
            domainNameToDomainId[_domainsParams[i].domainName] = _domainsParams[i].domain;
            domainToHeaderReporterHash[_domainsParams[i].domain] = keccak256(bytes(_domainsParams[i].headerReporter));
        }
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal override {
        uint256 domain = domainNameToDomainId[sourceChain];

        require(domain != 0, "AA: invalid domain");
        require(keccak256(bytes(sourceAddress)) == domainToHeaderReporterHash[domain], "AA: invalid sender");

        (uint256 blockNumber, bytes32 newBlockHeader) = abi.decode(payload, (uint256, bytes32));
        _storeHash(domain, blockNumber, newBlockHeader);
    }
}

