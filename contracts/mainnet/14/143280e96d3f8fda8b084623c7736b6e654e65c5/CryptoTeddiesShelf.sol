// SPDX-License-Identifier: AGPL-3.0-only
// @author creco.xyz 🐊 2022 

pragma solidity ^0.8.17;
import "./AccessControl.sol";
import "./AccessControlEnumerable.sol";
import "./IERC1155Receiver.sol";

interface OSS {
  function balanceOf(address, uint256) external view returns (uint256);
  function setApprovalForAll(address operator, bool approved) external;
  function safeTransferFrom(
    address from,
    address to,
    uint256 id,
    uint256 amount,
    bytes calldata data
  ) external;
}

/**
  This contract securely holds wrapped OSS tokens
 */
contract CryptoTeddiesShelf is
    AccessControlEnumerable,
    IERC1155Receiver {

    bool public isUnlockEnabled;
    OSS storeFront = OSS(0x495f947276749Ce646f68AC8c248420045cb7b5e); // OpenSea Storefront contract
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");    

    // permission modifiers
    modifier onlyAdmin {
      require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "CryptoTeddies Shelf: must have Admin role");
      _;
    } 

    modifier onlyMinter {
      require(hasRole(MINTER_ROLE, _msgSender()), "CryptoTeddies Shelf: must have Minter role");
      _;
    } 

    constructor() { 
      isUnlockEnabled = true;
       _setupRole(DEFAULT_ADMIN_ROLE, _msgSender()); // set admin permissions
    }
    
    // lock NFTs forever
    function disableUnlocking() onlyAdmin external {
      isUnlockEnabled = false;
    }

    // unlock NFTs
    function unlock(uint _tokenId, address _to) onlyMinter public  {
      require(isUnlockEnabled, "CryptoTeddies Shelf - unlocking is disabled");
      storeFront.safeTransferFrom(address(this), _to, _tokenId, 1, "");
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
      return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
      return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId ||
        super.supportsInterface(interfaceId);
    }
}



