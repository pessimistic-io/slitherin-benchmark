// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC1155.sol";
import "./IERC721.sol";

import "./ERC1155HolderUpgradeable.sol";
import "./ERC721HolderUpgradeable.sol";

import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./UtilitiesV2Upgradeable.sol";
import "./ISchool.sol";
import "./IBalanceSheet_DeFrag.sol";
import "./ISmolverseBridge.sol";

/// @title Smolverse Bridge State
/// @author Gearhart
/// @notice State variables, mappings, and interface support for Smolverse Bridge.

abstract contract SmolverseBridgeState is 
    Initializable, 
    UtilitiesV2Upgradeable, 
    ERC1155HolderUpgradeable, 
    ERC721HolderUpgradeable, 
    ReentrancyGuardUpgradeable, 
    ISmolverseBridge 
    {

    // -------------------------------------------------------------
    //                           VARIABLES
    // -------------------------------------------------------------

    ///@dev Land API role for spending assets on behalf of users. Grant with extreme caution.
    bytes32 internal constant AUTHORIZED_BALANCE_ADJUSTER_ROLE = keccak256("AUTHORIZED_BALANCE_ADJUSTER");

    /// @notice Instance of the SmolSchool contract.
    ISchool public smolSchool;
    
    /// @notice Address of SmolLand contract.
    address public smolLand;

    /// @notice Address of SmolBrains contract.
    address public smolBrains;

    /// @notice Address of DeFrag Finance Asset Manager contract for SmolBrains.
    address public deFragAssetManager;

    /// @notice Address of DeFrag Finance Balance Sheet contract for SmolBrains.
    address public deFragBalanceSheet;

    // -------------------------------------------------------------
    //                          USER MAPPINGS
    // -------------------------------------------------------------

    /// @notice NFT collection address, to token ID, to stat ID, to deposited balance.
    mapping (address => mapping (uint256 => mapping( uint256 => uint256))) public collectionToStatBalance;

    /// @notice User address to ERC20 token address to deposited balance.
    mapping (address => mapping ( address => uint256)) public userToERC20Balance;

    /// @notice User address to NFT collection address to token ID to deposited balance.
    mapping (address => mapping (address => mapping (uint256 => uint256))) public userToERC1155Balance;

    /// @notice User address to NFT collection address to token ID to bool indicating if token is currently deposited or not.
    mapping (address => mapping (address => mapping (uint256 => bool))) public userToDepositedERC721s;

    // -------------------------------------------------------------
    //                       COLLECTION MAPPINGS
    // -------------------------------------------------------------

    /// @notice ERC20 token address to bool indicating if the token is approved for ERC20 deposit.
    mapping (address => bool) public addressToERC20DepositApproval;

    /// @notice NFT collection address to bool indicating if the collection is approved for stat deposit.
    mapping (address => bool) public collectionToStatDepositApproval;

    /// @notice NFT collection address to bool indicating if the collection is approved for ERC1155 NFT deposit.
    mapping (address => bool) public collectionToERC1155DepositApproval;

    /// @notice NFT collection address to bool indicating if the collection is approved for ERC721 NFT deposit.
    mapping (address => bool) public collectionToERC721DepositApproval;

    /// @dev NFT collection address to EnumerableSet containing all stat/nft IDs available for deposit for that collection.
    mapping (address => EnumerableSetUpgradeable.UintSet) internal collectionToApprovedIds;

    // -------------------------------------------------------------
    //                     SUPPORTED INTERFACES
    // -------------------------------------------------------------
    
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155ReceiverUpgradeable, AccessControlEnumerableUpgradeable) returns (bool) {
        return interfaceId == type(IAccessControlEnumerableUpgradeable).interfaceId
        || interfaceId == type(IERC1155ReceiverUpgradeable).interfaceId
        || interfaceId == type(IERC721ReceiverUpgradeable).interfaceId
        || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------
    //                         INITIALIZER
    // -------------------------------------------------------------

    function __SmolverseBridgeState_init() internal initializer {
            UtilitiesV2Upgradeable.__Utilities_init();
            ERC1155HolderUpgradeable.__ERC1155Holder_init();
            ERC721HolderUpgradeable.__ERC721Holder_init();
            ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    }
}
