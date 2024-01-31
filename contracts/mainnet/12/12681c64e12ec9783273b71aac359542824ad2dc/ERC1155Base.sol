// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC1155.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Address.sol";
import "./IERC1155.sol";
import "./ERC1155Burnable.sol";
import "./ERC1155Supply.sol";
import "./Initializable.sol";
import "./IRoyaltySplitter.sol";
import "./AccessControlEnumerable.sol";
import "./Pausable.sol";
import "./ITargetInitializer.sol";
import "./Errors.sol";
import "./EIP2981.sol";

error IncorrectSplitTotal(uint256 expectedTotal, uint256 total);
error MetadataLocked();
error RoyaltiesMismatch(uint256 splits, uint256 recipients);
error TokenDoesNotExist();
error TokenAlreadyExists();

abstract contract ERC1155Base is
    EIP2981,
    Ownable,
    AccessControlEnumerable,
    Initializable,
    Pausable,
    ERC1155Burnable,
    ERC1155Supply,
    IRoyaltySplitter
{
    mapping(uint256 => string) tokenURIs;
    uint16[] royaltySplits;
    address payable[] royaltyRecipients;

    // Token name
    string public name;
    // Token symbol
    string public symbol;

    bool public isMetadataLocked;

    constructor(
        string memory _init_name,
        string memory _init_symbol,
        TargetInit memory params,
        bytes memory data
    ) ERC1155("") {
        name = _init_name;
        symbol = _init_symbol;

        isMetadataLocked = false;
        _royaltyRecipient = params.royaltyRecipients[0];
        _royaltyFee = params.royaltyFee;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);

        _setupRole(DEFAULT_ADMIN_ROLE, params.admin);

        _setupRole(MANAGER_ROLE, params.admin);
        _setupRole(MANAGER_ROLE, params.manager);

        _setupRole(MINTER_ROLE, params.admin);
        _setupRole(MINTER_ROLE, params.minter);

        _setupRole(CREATOR_ROLE, params.creator);

        // owner set to msg.sender in `Ownable`. Setting owner with _transferOwnership
        // https://github.com/OpenZeppelin/openzeppelin-contracts/issues/2639#issuecomment-1253408868
        _transferOwnership(params.admin);

        setUpRecipients(params.royaltySplits, params.royaltyRecipients);
    }

    function initialize(
        string memory _init_name,
        string memory _init_symbol,
        TargetInit calldata params,
        bytes memory data
    ) public virtual initializer {
        name = _init_name;
        symbol = _init_symbol;

        isMetadataLocked = false;
        _royaltyRecipient = params.royaltyRecipients[0];
        _royaltyFee = params.royaltyFee;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MANAGER_ROLE, msg.sender);

        _setupRole(DEFAULT_ADMIN_ROLE, params.admin);

        _setupRole(MANAGER_ROLE, params.admin);
        _setupRole(MANAGER_ROLE, params.manager);

        _setupRole(MINTER_ROLE, params.admin);
        _setupRole(MINTER_ROLE, params.minter);

        _setupRole(CREATOR_ROLE, params.creator);

        // owner set to msg.sender in `Ownable`. Sertting owner with _transferOwnership
        // https://github.com/OpenZeppelin/openzeppelin-contracts/issues/2639#issuecomment-1253408868
        _transferOwnership(params.admin);

        setUpRecipients(params.royaltySplits, params.royaltyRecipients);
    }

    /// Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// >>>>>>>>>>>>>>>>>>>>>  VIEW  <<<<<<<<<<<<<<<<<<<<<< ///

    function uri(uint256 tokenId) public view override returns (string memory) {
        return tokenURIs[tokenId];
    }

    /// >>>>>>>>>>>>>>>>>>>>>  EXTERNAL  <<<<<<<<<<<<<<<<<<<<<< ///

    function setUri(uint256 tokenId, string memory newUri)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (isMetadataLocked) {
            revert MetadataLocked();
        }
        tokenURIs[tokenId] = newUri;
    }

    /// @notice Locks metadata upgrades
    function setMetadataLocked() public onlyRole(DEFAULT_ADMIN_ROLE) {
        isMetadataLocked = true;
    }

    /// @notice set address of the minter
    /// @param owner The address of the new owner
    function setOwner(address owner) public onlyOwner {
        transferOwnership(owner);
    }

    function mint(
        address to,
        uint256 id,
        uint256 quantity,
        bytes memory data
    ) public onlyRole(MINTER_ROLE) whenNotPaused {
        if (bytes(tokenURIs[id]).length == 0) revert TokenDoesNotExist();

        _mint(to, id, quantity, data);
    }

    function mint(
        address to,
        uint256 id,
        string memory _uri,
        uint256 quantity,
        bytes memory data
    ) public onlyRole(MINTER_ROLE) whenNotPaused {
        if (bytes(tokenURIs[id]).length == 0) {
            tokenURIs[id] = _uri;
        }

        _mint(to, id, quantity, data);
    }

    /// @notice Burns token that has been redeemed for something else
    /// @dev Allows MINTER_ROLE to call this function (otherwise only token owner)
    /// @param from token owner address
    /// @param tokenId id of the token
    /// @param tokenId amount of tokens to be burned
    function redeemBurn(
        address from,
        uint256 tokenId,
        uint256 amount
    ) public onlyRole(MINTER_ROLE) whenNotPaused {
        _burn(from, tokenId, amount);
    }

    /// @notice Burns tokens that have been redeemed for something else
    /// @dev Allows MINTER_ROLE to call this function (otherwise only tokens' owner)
    /// @param from token owner address
    /// @param tokenIds tokenIds to be burned
    /// @param amounts amount of tokens to be burned (respective to array of tokenId's)
    ///     * - `tokenIds` and `amounts` must have the same length.
    function redeemBurnBatch(
        address from,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) public onlyRole(MINTER_ROLE) whenNotPaused {
        _burnBatch(from, tokenIds, amounts);
    }

    /// @notice Pause contract
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, EIP2981, AccessControlEnumerable, IERC165)
        returns (bool)
    {
        return
            ERC1155.supportsInterface(interfaceId) ||
            EIP2981.supportsInterface(interfaceId) ||
            AccessControlEnumerable.supportsInterface(interfaceId) ||
            ERC165.supportsInterface(interfaceId) ||
            interfaceId == type(IRoyaltySplitter).interfaceId;
    }

    /// @notice builds Recipients and calls IRoyaltySplitter setRecipients
    /// @dev The bps must add up to total of 10000 (100%).
    /// @dev Recipient address and split count must match
    /// @param _royaltySplits uint16[]
    /// @param _royaltyRecipients address[]
    function setUpRecipients(
        uint16[] memory _royaltySplits,
        address payable[] memory _royaltyRecipients
    ) public onlyRole(MANAGER_ROLE) {
        if (_royaltySplits.length != _royaltyRecipients.length) {
            revert RoyaltiesMismatch(
                _royaltySplits.length,
                _royaltyRecipients.length
            );
        }

        uint32 mBpTotal = 0;
        for (uint256 i = 0; i < _royaltyRecipients.length; i++) {
            if (_royaltyRecipients[i] == address(0)) revert PayoutZeroAddress();

            mBpTotal += _royaltySplits[i];
        }

        if (mBpTotal != 10000) {
            revert IncorrectSplitTotal(10000, mBpTotal);
        }

        royaltySplits = _royaltySplits;
        royaltyRecipients = _royaltyRecipients;
    }

    /// @notice sets the royalty recipients address and split
    /// @dev The bps must add up to total of 10000 (100%).
    /// @param _recipients Recipient[]
    function setRecipients(Recipient[] calldata _recipients)
        public
        onlyRole(MANAGER_ROLE)
    {
        uint16[] memory _royaltySplits = new uint16[](_recipients.length);
        address payable[] memory _royaltyRecipients = new address payable[](
            _recipients.length
        );

        for (uint256 i = 0; i < _recipients.length; i++) {
            _royaltySplits[i] = _recipients[i].bps;
            _royaltyRecipients[i] = _recipients[i].recipient;
        }

        setUpRecipients(_royaltySplits, _royaltyRecipients);
    }

    /// @notice gets the royalty recipient addresses and splits
    function getRecipients() external view returns (Recipient[] memory) {
        Recipient[] memory mRecipients = new Recipient[](
            royaltyRecipients.length
        );

        for (uint256 i = 0; i < royaltyRecipients.length; i++) {
            Recipient memory recipient = Recipient(
                royaltyRecipients[i],
                royaltySplits[i]
            );
            mRecipients[i] = recipient;
        }
        return mRecipients;
    }

    /// @notice sets the fee of royalties
    /// @dev The fee denominator is 10000 in BPS.
    /// @param fee fee
    /*
        Example

        This would set the fee at 5%
        ```
        KeyUnlocks.setRoyaltyFee(500)
        ```
    */
    function setRoyaltyFee(uint256 fee) public onlyRole(MANAGER_ROLE) {
        _royaltyFee = fee;
    }

    function setRoyaltyRecipient(address royaltyRecipient)
        public
        onlyRole(MANAGER_ROLE)
    {
        _royaltyRecipient = royaltyRecipient;
    }

    /// >>>>>>>>>>>>>>>>>>>>>  HOOKS  <<<<<<<<<<<<<<<<<<<<<< ///

    /**
     * @dev See {ERC1155-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - the contract must not be paused.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory memoryIds,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._beforeTokenTransfer(
            operator,
            from,
            to,
            memoryIds,
            amounts,
            data
        );
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

