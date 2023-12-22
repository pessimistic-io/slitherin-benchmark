//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./AdminManaged.sol";
import "./SoulBound.sol";
import "./ContractMetadata.sol";
import "./Initializable.sol";

contract AdminManagedSBT is Initializable, AdminManaged, SoulBound, ContractMetadata {
    string private __baseURI;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        address transfer,
        address burner,
        address minter,
        address approver,
        uint48 delay,
        string memory name,
        string memory symbol
    ) public initializerERC721A initializer {
        __SoulBound_init(name, symbol);
        __AdminManaged_init(owner, transfer, burner, minter, approver, delay);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return __baseURI;
    }

    function setBaseURI(string memory _newBaseURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
        assert(bytes(_newBaseURI).length > 0);
        __baseURI = _newBaseURI;
    }

    function mint(address to, uint256 quantity) external onlyRole(MINTER_ROLE) {
        _safeMint(to, quantity);
    }

    function batchMint(address[] calldata to, uint256[] calldata quantity) external onlyRole(MINTER_ROLE) {
        require(to.length == quantity.length, 'AdminManagedSBT: to and quantity length mismatch');
        for (uint256 i = 0; i < to.length; ) {
            _safeMint(to[i], quantity[i]);
            unchecked {
                i++;
            }
        }
    }

    function _burn(uint256 tokenId) internal virtual override(AdminManaged, SoulBound) {
        _unlock(tokenId);
        SoulBound._burn(tokenId);
    }

    function _forceBurn(uint256 tokenId) internal virtual override(AdminManaged, SoulBound) {
        _unlock(tokenId);
        SoulBound._forceBurn(tokenId);
    }

    function forceTransferFrom(address from, address to, uint256 tokenId) public override onlyRole(TRANSFER_ROLE) {
        _unlock(tokenId);
        super.forceTransferFrom(from, to, tokenId);
        _lock(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(SoulBound, AccessControlDefaultAdminRulesUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _approve(address to, uint256 tokenId) internal override(ERC721AUpgradeable, AdminManaged) {
        super._approve(to, tokenId);
    }

    function _transferFrom(address from, address to, uint256 tokenId) internal override {
        safeTransferFrom(from, to, tokenId);
    }

    function _canSetContractURI() internal view virtual override onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        return true;
    }
}

