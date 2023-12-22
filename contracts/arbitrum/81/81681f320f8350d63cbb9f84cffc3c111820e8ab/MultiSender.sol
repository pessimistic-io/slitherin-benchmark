//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./AccessControlUpgradeable.sol";

contract MultiSender is AccessControlUpgradeable{
    bytes32 public constant SMOLNEANDER_OWNER_ROLE = keccak256("SMOLNEANDER_OWNER_ROLE");
    bytes32 public constant SMOLNEANDER_ADMIN_ROLE = keccak256("SMOLNEANDER_ADMIN_ROLE");

    modifier onlyAdmin {
        require(isAdmin(_msgSender()), "MinterControl: not a SMOLNEANDER_ADMIN_ROLE");
        _;
    }

    function grantAdmin(address _admin) external {
        grantRole(SMOLNEANDER_ADMIN_ROLE, _admin);
    }

    function isAdmin(address _admin) public view returns (bool) {
        return hasRole(SMOLNEANDER_ADMIN_ROLE, _admin);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable) returns (bool) {
        return AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    function initialize() initializer public {
        _setRoleAdmin(SMOLNEANDER_OWNER_ROLE, SMOLNEANDER_OWNER_ROLE);
        _setRoleAdmin(SMOLNEANDER_ADMIN_ROLE, SMOLNEANDER_OWNER_ROLE);

        _setupRole(SMOLNEANDER_OWNER_ROLE, _msgSender());
        _setupRole(SMOLNEANDER_ADMIN_ROLE, _msgSender());
    }

    IERC721 nft;
    
    function setAddress(address nftAddress) external onlyAdmin{
        nft = IERC721(nftAddress);
    }

    function sendBatch(address[] calldata addresses, uint256[] calldata tokenIDs) external onlyAdmin {
        for(uint i=0; i<addresses.length; i++) {
            nft.safeTransferFrom(msg.sender, addresses[i], tokenIDs[i]);
        }
    }
}

interface IERC721 {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}
