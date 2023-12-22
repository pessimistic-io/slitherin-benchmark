// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC721EnumerableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IERC165Upgradeable.sol";

import "./IFriendTechReward.sol";

//MMMMWKl.                                            .:0WMMMM//
//MMMWk,                                                .dNMMM//
//MMNd.                                                  .lXMM//
//MWd.    .','''....                         .........    .lXM//
//Wk.     ';......'''''.                ..............     .dW//
//K;     .;,         ..,'.            ..'..         ...     'O//
//d.     .;;.           .''.        ..'.            .'.      c//
//:       .','.           .''.    ..'..           ....       '//
//'         .';.            .''...'..           ....         .//
//.           ';.             .''..             ..           .//
//.            ';.                             ...           .//
//,            .,,.                           .'.            .//
//c             .;.                           '.             ;//
//k.            .;.             .             '.            .d//
//Nl.           .;.           .;;'            '.            :K//
//MK:           .;.          .,,',.           '.           'OW//
//MM0;          .,,..       .''  .,.       ...'.          'kWM//
//MMMK:.          ..'''.....'..   .'..........           ,OWMM//
//MMMMXo.             ..'...        ......             .cKMMMM//
//MMMMMWO:.                                          .,kNMMMMM//
//MMMMMMMNk:.                                      .,xXMMMMMMM//
//MMMMMMMMMNOl'.                                 .ckXMMMMMMMMM//

contract FriendTechReward is
    Initializable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IFriendTechReward
{
    using StringsUpgradeable for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    uint256 public override currentId;
    mapping(uint256 => address) soulboundMapping;
    mapping(uint256 => uint256) tokenIdToType;
    mapping(uint256 => string) typeToMetadataURL;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin
    ) public initializer {
        __ERC721_init("Battlefly FriendTech Reward", "BF_FT_RWRD");
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        if (admin == address(0)) revert InvalidAddress(admin);

        _setupRole(ADMIN_ROLE, admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert UnexistingToken(tokenId);
        return typeToMetadataURL[tokenIdToType[tokenId]];
    }

    function setMetadataURLOfType(string[] calldata metadata, uint256[] calldata types) external onlyAdmin {
        if(metadata.length != types.length) revert IncorrectArrayLength();
        for (uint256 i = 0; i < types.length; ) {
            typeToMetadataURL[types[i]] = metadata[i];
            unchecked {
                ++i;
            }
        }
    }

    function getMetadataURLOfType(uint256 tokenType) external view returns(string memory) {
        return typeToMetadataURL[tokenType];
    }

    function mint(address[] calldata receivers, uint256[] calldata types) external nonReentrant onlyAdmin {
        if(receivers.length != types.length) revert IncorrectArrayLength();
        uint256 index = 0;
        for (uint256 i = currentId; i < (currentId + receivers.length); ) {
            unchecked {
                ++i;
            }
            soulboundMapping[i] = receivers[index];
            tokenIdToType[i] = types[index];
            _mint(receivers[index], i);
            emit Minted(receivers[index], i);
            unchecked {
                ++index;
            }
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal virtual override {
        if (soulboundMapping[firstTokenId] != to)
            revert TransferNotAllowed(from, to, firstTokenId);
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    // The following functions are overrides required by Solidity.

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable, ERC721EnumerableUpgradeable, IERC165Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert AccessDenied();
        _;
    }
}

