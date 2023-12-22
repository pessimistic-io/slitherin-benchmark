// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.14;

import "./ERC721.sol";
import "./DeveloperWallet.sol";

/// @title   Proof Of Deployer
/// @notice  NFT for deployer when deploying a contract and receives audit with Hyacinth
/// @author  Hyacinth
contract ProofOfDeveloper is ERC721 {
    using Strings for uint256;

    /// EVENTS ///

    /// @notice          Emitted after database has been set
    /// @param database  Address of database contract
    event DatabaseSet(address database);

    /// @notice                Emitted after proof of developer NFT is minted
    /// @param developer       Address of developer
    /// @param walletContract  Address of created wallet contract
    /// @param podId           Id of NFT minted
    event ProofOfDeveloperMinted(address indexed developer, address indexed walletContract, uint256 indexed podId);

    /// ERRORS ///

    /// @notice Error for if not database
    error NotDatabase();
    /// @notice Error for if not deployer
    error NotDeployer();
    /// @notice Error for if being transferred
    error CanNotTransfer();
    /// @notice Error for if address already set
    error AddressAlreadySet();

    /// STATE VARIABLES ///

    /// @notice Address of database
    address public database;
    /// @notice Address of deployer
    address public deployer;

    /// @notice Total supply of token
    uint256 public totalSupply;

    /// @notice String of base URI
    string private _baseURIextended = "ipfs://bafybeigu4fedphenplbrzaghieddou4hbfnz7iioeokujsgwgse7fptzee/0";

    /// @notice Id adddress holds
    mapping(address => uint256) public idHeld;

    /// CONSTRUCTOR  ///

    constructor() ERC721("Hyacinth Developer NFT", "POD") {
        deployer = msg.sender;
    }

    /// SET DATABASE ///

    /// @notice           Sets address of database
    /// @param database_  Address of database contract
    function setDatabase(address database_) external {
        if (deployer != msg.sender) revert NotDeployer();
        if (database != address(0)) revert AddressAlreadySet();
        database = database_;

        emit DatabaseSet(database_);
    }

    /// DATABASE FUNCTION ///

    /// @notice                   Mint approved auditor their POA NFT
    /// @param developer_         Address of developer who is receiving NFT
    /// @return id_               Id of NFT minted
    /// @return developerWallet_  Address of developer wallet contract that was created
    function mint(address developer_) external returns (uint256 id_, address developerWallet_) {
        if (msg.sender != database) revert NotDatabase();
        id_ = totalSupply;
        _safeMint(developer_, id_);
        ++totalSupply;

        idHeld[developer_] = id_;

        DeveloperWallet developerWallet = new DeveloperWallet(developer_, database);
        developerWallet_ = address(developerWallet);

        emit ProofOfDeveloperMinted(developer_, developerWallet_, id_);
    }

    /// INTERNAL VIEW FUNCTION ///

    /// @notice           Returns `_baseURIextended`
    /// @return baseURI_  Base URI of token
    function _baseURI() internal view virtual override returns (string memory baseURI_) {
        return _baseURIextended;
    }

    /// @notice         Logic performed before transferring of `tokenId`
    /// @param from     Address where `tokenId` is being sent from
    /// @param to       Address where `tokenId` is being sent to
    /// @param tokenId  Token Id that is being sent
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        if (from != address(0)) {
            revert CanNotTransfer();
        }
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /// EXTERNAL VIEW FUNCTIONS ///

    /// @notice            Returns token URI for `tokenId_`
    /// @param tokenId_    Id that is having URI returned
    /// @return tokenURI_  URI for `tokenId_`
    function tokenURI(uint256 tokenId_) public view override returns (string memory tokenURI_) {
        return string(abi.encodePacked(_baseURI()));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

