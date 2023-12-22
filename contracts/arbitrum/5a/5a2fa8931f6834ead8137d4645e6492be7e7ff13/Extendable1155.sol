// SPDX-License-Identifier: MIT
// Metaline Contracts (Extendable1155.sol)

pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./ERC1155Burnable.sol";
import "./ERC1155Pausable.sol";
import "./ERC1155Supply.sol";
import "./AccessControl.sol";
import "./Context.sol";
import "./IERC20.sol";

import "./IERC2981Royalties.sol";
import "./TransferHelper.sol";

/**
 * @dev {ERC1155} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to other accounts.
 */
contract ERC1155PresetMinterPauser is 
    Context, 
    AccessControl, 
    ERC1155Burnable, 
    ERC1155Pausable, 
    ERC1155Supply, 
    IERC2981Royalties 
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // erc2981 royalty fee, /10000
    uint256 public _royalties;

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE`, and `PAUSER_ROLE` to the account that
     * deploys the contract.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        string memory uri
    ) ERC1155(uri) {
        _name = name_;
        _symbol = symbol_;
        _royalties = 500; // 5%

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    /**
     * @dev As 1155 contract name for some dApp which read name from contract, See {IERC721Metadata-name}.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev As 1155 contract symbol for some dApp which read symbol from contract, See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev update base token uri, See {IERC1155MetadataURI-uri}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function updateURI(string calldata newuri) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have minter role to update");
        _setURI(newuri);
    }

    /**
     * @dev Creates `amount` new tokens for `to`, of token type `id`.
     *
     * See {ERC1155-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have minter role to mint");

        _mint(to, id, amount, data);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] variant of {mint}.
     */
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have minter role to mint");

        _mintBatch(to, ids, amounts, data);
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC1155Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have pauser role to pause");
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC1155Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have pauser role to unpause");
        _unpause();
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155)
        returns (bool)
    {
        return interfaceId == type(IERC2981Royalties).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155, ERC1155Pausable, ERC1155Supply) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    // set royalties
    function setRoyalties(uint256 royalties) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have minter role");
        _royalties = royalties;
    }

    /// @inheritdoc	IERC2981Royalties
    function royaltyInfo(uint256, uint256 value)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        receiver = address(this);
        royaltyAmount = (value * _royalties) / 10000;
    }

    // fetch royalty income
    function fetchIncome(address erc20) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have minter role");

        uint256 amount = IERC20(erc20).balanceOf(address(this));
        if(amount > 0) {
            TransferHelper.safeTransfer(erc20, _msgSender(), amount);
        }
    }
    function fetchIncomeEth() external {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC1155PresetMinterPauser: must have minter role");

        // send eth
        (bool sent, ) = _msgSender().call{value:address(this).balance}("");
        require(sent, "ERC1155PresetMinterPauser: transfer error");
    }
}

contract Extendable1155 is ERC1155PresetMinterPauser {
    
    bytes32 public constant DATA_ROLE = keccak256("DATA_ROLE");

    /**
    * @dev emit when token data section changed

    * @param id 1155 id which data has been changed
    * @param extendData data after change
    */
    event Extendable1155Modify(uint256 indexed id, bytes extendData);

    mapping(uint256=>bytes) _extendDatas;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory uri) ERC1155PresetMinterPauser(name_, symbol_, uri) 
    {
    }

    /**
    * @dev modify extend 1155 data, emit {Extendable1155Modify} event
    *
    * Requirements:
    * - caller must have general `DATA_ROLE`
    *
    * @param id 1155 id to modify extend data
    * @param extendData extend data in bytes, use a codec to encode or decode the bytes data outside
    */
    function modifyExtendData(
        uint256 id,
        bytes memory extendData
    ) external whenNotPaused {
        require(
            hasRole(DATA_ROLE, _msgSender()),
            "R6"
        );

        require(
            exists(id),
            "E4"
        );

        // modify extend data
        _extendDatas[id] = extendData;

        emit Extendable1155Modify(id, extendData);
    }

    /**
    * @dev get extend 1155 data 
    *
    * @param id 1155 id to get extend data
    * @return extend data in bytes, use a codec to encode or decode the bytes data outside
    */
    function getTokenExtendNftData(uint256 id)
        external
        view
        returns (bytes memory)
    {
        require(exists(id), "E6");

        return _extendDatas[id];
    }

}
