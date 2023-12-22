//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CountersUpgradeable.sol";

import "./ToadHousezMintable.sol";

contract ToadHousez is Initializable, ToadHousezMintable {

    using CountersUpgradeable for CountersUpgradeable.Counter;

    function initialize() external initializer {
        ToadHousezMintable.__ToadHousezMintable_init();
    }

    function setMaxSupply(uint256 _maxSupply) external onlyAdminOrOwner {
        maxSupply = _maxSupply;
    }

    function adminSafeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external onlyAdminOrOwner {
        _safeTransfer(_from, _to, _tokenId, "");
    }

    function safeBatchTransferFrom(
        address _from,
        address[] calldata _tos,
        uint256[] calldata _tokenIds
    ) external {
        require(_tos.length > 0 && _tos.length == _tokenIds.length, "Bad lengths");
        for(uint256 i = 0; i < _tos.length; i++) {
            safeTransferFrom(_from, _tos[i], _tokenIds[i]);
        }
    }

    function tokenURI(uint256 _tokenId) public view override contractsAreSet returns(string memory) {
        require(_exists(_tokenId), "ToadHousez: Token does not exist");

        return toadHousezMetadata.tokenURI(_tokenId);
    }

    function burn(
        uint256 _tokenId)
    external
    override
    onlyAdminOrOwner
    {
        _burn(_tokenId);

        amountBurned++;
    }
}
