// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC721ReceiverUpgradeable.sol";
import "./Initializable.sol";

interface ERCBase {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function getApproved(uint256 tokenId) external view returns (address);
}

interface ERC721Partial is ERCBase {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

interface ERC1155Partial is ERCBase {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external;
}


contract Test2 is Initializable, PausableUpgradeable, OwnableUpgradeable, IERC721ReceiverUpgradeable {

    bytes4 _ERC721;
    bytes4 _ERC1155;
    uint meaningOfLife;

    function initialize() public initializer {

      _ERC721 = 0x80ac58cd;
      _ERC1155 = 0xd9b67a26;

      meaningOfLife = 42;

      // Call the init function of OwnableUpgradeable to set owner
      // Calls will fail without this
      __Ownable_init();

    }

    function getMeaningOfLife() public view returns (uint) {
      return meaningOfLife * 2;
    }

    function pause() onlyOwner external {
       _pause();
    }

    function unpause() onlyOwner external {
       _unpause();
    }

    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    receive () external payable { }

    fallback () external payable { }

}

