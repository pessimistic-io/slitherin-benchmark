// SPDX-License-Identifier: MIT
import { ERC721, ERC721Enumerable } from "./ERC721Enumerable.sol";
import { AccessControlEnumerable } from "./AccessControlEnumerable.sol";
import { IGNSNftDesign } from "./IGNSNftDesign.sol";

pragma solidity 0.8.17;

contract GNSTestNft4 is ERC721, ERC721Enumerable, AccessControlEnumerable{
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    IGNSNftDesign public design;

    constructor() ERC721("GNS TEST NFT 4", "GNSTESTNFT4") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        for(uint i = 15; i < 20; i++){
            _mint(msg.sender, i);
        }
    }

    function updateDesign(IGNSNftDesign newValue) external onlyRole(DEFAULT_ADMIN_ROLE){
        design = newValue;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, AccessControlEnumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function mint(address to, uint tokenId) external onlyRole(BRIDGE_ROLE) {
        _mint(to, tokenId);
    }

    function burn(uint tokenId) external onlyRole(BRIDGE_ROLE) {
        _burn(tokenId);
    }

    function tokenURI(uint tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        return design.buildTokenURI(4, tokenId);
    }   
}
