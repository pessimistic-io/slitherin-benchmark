// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import "./Loot8Collection.sol";
import "./ILoot8UniformCollection.sol";

contract Loot8UniformCollection is Loot8Collection, ILoot8UniformCollection {
        
    string public contractURI;
    address public helper;

    constructor(
        string memory _name, 
        string memory _symbol,
        string memory _contractURI,
        bool _transferable,
        address _governor,
        address _helper,
        address _trustedForwarder,
        address _layerZeroEndpoint
    ) Loot8Collection(_name, _symbol, _transferable, _governor, _trustedForwarder, _layerZeroEndpoint) {
        helper = _helper;
        contractURI = _contractURI;
    }

    function updateContractURI(string memory _contractURI) external {
        require(_msgSender() == helper || _msgSender() == owner(), "UNAUTHORIZED");
        contractURI = _contractURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        return contractURI;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId ==  0x96f8caa1 ||  // ILoot8UniformCollection
            super.supportsInterface(interfaceId);
    }
}
