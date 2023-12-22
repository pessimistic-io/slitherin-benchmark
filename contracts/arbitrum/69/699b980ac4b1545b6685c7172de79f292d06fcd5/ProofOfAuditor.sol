// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.14;

import "./ERC721.sol";
import "./IDatabase.sol";

/// @title   Proof Of Auditor
/// @notice  NFT received when added as auditor
/// @author  Hyacinth
contract ProofOfAuditor is ERC721 {
    using Strings for uint256;

    /// EVENTS ///

    /// @notice          Emitted after database has been set
    /// @param database  Address of database contract
    event DatabaseSet(address database);

    /// @notice            Emitted after level logic contract has been set
    /// @param levelLogic  Address of level logic contract
    event LevelLogicSet(address levelLogic);

    /// @notice         Emitted after proof of auditor NFT is minted
    /// @param auditor  Address of auditor
    /// @param poaId    Id of NFT minted
    event ProofOfAuditorMinted(address indexed auditor, uint256 indexed poaId);

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
    string private _baseURIextended = "ipfs://bafybeibmc6z7lzkaugmtiv5wbgeqnr23ri4umu5dswoemr3rgfo3wirpgu/";

    /// @notice Id adddress holds
    mapping(address => uint256) public idHeld;

    /// CONSTRUCTOR  ///

    constructor() ERC721("Hyacinth Auditor NFT", "POA") {
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

    /// @notice          Mint approved auditor their POA NFT
    /// @param auditor_  Address of auditor who is receiving NFT
    /// @return id_      Id of NFT minted
    function mint(address auditor_) external payable returns (uint256 id_) {
        if (msg.sender != database) revert NotDatabase();
        id_ = totalSupply;
        _safeMint(auditor_, id_);
        ++totalSupply;

        idHeld[auditor_] = id_;

        emit ProofOfAuditorMinted(auditor_, id_);
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

    /// @notice          Returns level of `tokenId_`
    /// @param tokenId_  Token id of Proof Of Auditor NFT to return level for
    /// @return level_   Level of `tokenId_`
    function level(uint256 tokenId_) public view returns (uint256 level_) {
        address owner_ = ownerOf(tokenId_);
        uint256[4] memory levelsCompleted_ = IDatabase(database).levelsCompleted(owner_);
        uint256 totalCompleted_;
        for (uint256 i; i < 4; ++i) totalCompleted_ += levelsCompleted_[i];

        (, uint256 positive_, uint256 negative_, uint256 baseLevel_) = IDatabase(database).auditors(owner_);

        uint256 totalFeedback_ = positive_ + negative_;
        uint256 feedbackPercent_;
        if (totalFeedback_ > 0) feedbackPercent_ = (10000 * positive_) / totalFeedback_;

        if (levelsCompleted_[2] >= 10 && feedbackPercent_ >= 9500) level_ = 3;
        else if (totalCompleted_ >= 20 && levelsCompleted_[1] >= 10 && feedbackPercent_ >= 9000) level_ = 2;
        else if (totalCompleted_ >= 5 && feedbackPercent_ >= 8000) level_ = 1;

        if (baseLevel_ > level_) level_ = baseLevel_;
    }

    /// @notice            Returns token URI for `tokenId_`
    /// @param tokenId_    Id that is having URI returned
    /// @return tokenURI_  URI for `tokenId_`
    function tokenURI(uint256 tokenId_) public view override returns (string memory tokenURI_) {
        return string(abi.encodePacked(_baseURI(), level(tokenId_).toString()));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

