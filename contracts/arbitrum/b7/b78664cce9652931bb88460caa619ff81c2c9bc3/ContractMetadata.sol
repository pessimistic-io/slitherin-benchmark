//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

abstract contract ContractMetadata {
    event ContractURIUpdated(string prevURI, string newURI);
    string public contractURI;

    function setContractURI(string memory _uri) external {
        if (!_canSetContractURI()) {
            revert('Not authorized');
        }

        _setupContractURI(_uri);
    }

    function _setupContractURI(string memory _uri) internal {
        string memory prevURI = contractURI;
        contractURI = _uri;

        emit ContractURIUpdated(prevURI, _uri);
    }

    function _canSetContractURI() internal view virtual returns (bool);
}

