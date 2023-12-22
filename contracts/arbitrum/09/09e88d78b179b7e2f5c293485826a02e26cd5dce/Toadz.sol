//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./CountersUpgradeable.sol";

import "./ToadzMintable.sol";

contract Toadz is Initializable, ToadzMintable {

    using CountersUpgradeable for CountersUpgradeable.Counter;

    function initialize() external initializer {
        ToadzMintable.__ToadzMintable_init();
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

    function tokenURI(uint256 _tokenId) public view override contractsAreSet returns(string memory) {
        require(_exists(_tokenId), "Toadz: Token does not exist");

        return toadzMetadata.tokenURI(_tokenId);
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
