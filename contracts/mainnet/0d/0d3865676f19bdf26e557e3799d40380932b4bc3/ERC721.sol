pragma solidity >=0.5.16 <0.6.0;

import "./Strings.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./ERC2981.sol";
import "./IERC721.sol";
import "./IERC721Metadata.sol";
import "./IERC721Receiver.sol";
import "./Pausable.sol";

/**
 * @title ERC721 Non-Fungible Token Standard basic implementation
 * @dev see https://github.com/ethereum/EIPs/blob/master/EIPS/eip-721.md
 */
contract ERC721 is IERC721, IERC721Metadata, ERC2981, Pausable {

    using SafeMath for uint256;
    using Strings for uint256;
    using Strings for string;
    using Address for address;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner
    mapping (uint256 => address) private _tokenOwner;

    // Mapping from token ID to approved address
    mapping (uint256 => address) private _tokenApprovals;

    // Mapping from owner to number of owned token
    mapping (address => uint256) private _balances;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    // Base URI
    string internal _baseURI = "https://";

    //tokenId:uri
    mapping (uint256 => string) internal _tokenURIs;
    //tokenType:uri
    //mapping (uint8 => string) internal _typeTokenURIs;

    /*
    * 0x80ac58cd ===
    *   bytes4(keccak256('balanceOf(address)')) ^
    *   bytes4(keccak256('ownerOf(uint256)')) ^
    *   bytes4(keccak256('approve(address,uint256)')) ^
    *   bytes4(keccak256('getApproved(uint256)')) ^
    *   bytes4(keccak256('setApprovalForAll(address,bool)')) ^
    *   bytes4(keccak256('isApprovedForAll(address,address)')) ^
    *   bytes4(keccak256('transferFrom(address,address,uint256)')) ^
    *   bytes4(keccak256('safeTransferFrom(address,address,uint256)')) ^
    *   bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)'))
    */
    bytes4 private constant _InterfaceId_ERC721 = 0x80ac58cd;
    
    /*
     *     bytes4(keccak256('name()')) == 0x06fdde03
     *     bytes4(keccak256('symbol()')) == 0x95d89b41
     *     bytes4(keccak256('tokenURI(uint256)')) == 0xc87b56dd
     *
     *     => 0x06fdde03 ^ 0x95d89b41 ^ 0xc87b56dd == 0x5b5e139f
     */
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
  
    modifier onlyOwnerOf(uint _tokenId) {
        require(tx.origin == _tokenOwner[_tokenId],'Token is not yours');
        _;
    }

    constructor(string memory name_, string memory symbol_) public
    {
        _name = name_;
        _symbol = symbol_;
        
        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_InterfaceId_ERC721);
        
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    //function _getTokenType(uint256 tokenId) internal view returns(uint8) {
    //    return 0;
    //}

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];

        // Even if there is a base URI, it is only appended to non-empty token-specific URIs
        if (bytes(_tokenURI).length == 0) {
            return "";
        //    uint8 _type = _getTokenType(tokenId);
        //    _tokenURI = _typeTokenURIs[_type];
        //    return string(abi.encodePacked(_baseURI, _tokenURI));
        }
        else
        {
        //    // abi.encodePacked is being used to concatenate strings
        //    return string(abi.encodePacked(_tokenURI));
            return string(abi.encodePacked(_baseURI, _tokenURI));
        }
    }

    /**
    * @dev Returns the base URI set via {_setBaseURI}. This will be
    * automatically added as a preffix in {tokenURI} to each token's URI, when
    * they are non-empty.
    *
    * _Available since v2.5.0._
    */
    function baseURI() external view returns (string memory) {
        return _baseURI;
    }
    
    /**
    * @dev Gets the balance of the specified address
    * @param owner address to query the balance of
    * @return uint256 representing the amount owned by the passed address
    */
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), 'ERC721: balance query for the zero address');
        return _balances[owner];
    }

    /**
    * @dev Gets the owner of the specified token ID
    * @param tokenId uint256 ID of the token to query the owner of
    * @return owner address currently marked as the owner of the given token ID
    */
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _tokenOwner[tokenId];
        require(owner != address(0), 'ERC721: owner query for nonexistent token');
        return owner;
    }

    /**
    * @dev Approves another address to transfer the given token ID
    * The zero address indicates there is no approved address.
    * There can only be one approved address per token at a given time.
    * Can only be called by the token owner or an approved operator.
    * @param to address to be approved for the given token ID
    * @param tokenId uint256 ID of the token to be approved
    */
    function approve(address to, uint256 tokenId) public whenNotPaused {
        address owner = ownerOf(tokenId);
        require(owner != address(0) && to != owner, 'ERC721: approval to current owner');
        require(msg.sender == owner || isApprovedForAll(owner, msg.sender), 'ERC721: approve caller is not owner nor approved for all');

        _approve(to, tokenId);
    }

    /**
    * @dev Gets the approved address for a token ID, or zero if no address set
    * Reverts if the token ID does not exist.
    * @param tokenId uint256 ID of the token to query the approval of
    * @return address currently approved for the given token ID
    */
    function getApproved(uint256 tokenId) public view returns (address) {
        require(_exists(tokenId), 'ERC721: approved query for nonexistent token');
        return _tokenApprovals[tokenId];
    }

    /**
    * @dev Sets or unsets the approval of a given operator
    * An operator is allowed to transfer all tokens of the sender on their behalf
    * @param to operator address to set the approval
    * @param approved representing the status of the approval to be set
    */
    function setApprovalForAll(address to, bool approved) public {
        require(to != msg.sender, 'ERC721: approve to caller');
        _operatorApprovals[msg.sender][to] = approved;
        emit ApprovalForAll(msg.sender, to, approved);
    }

    /**
    * @dev Tells whether an operator is approved by a given owner
    * @param owner owner address which you want to query the approval of
    * @param operator operator address which you want to query the approval of
    * @return bool whether the given operator is approved by the given owner
    */
    function isApprovedForAll(address owner, address operator) public view returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    /**
    * @dev Transfers the ownership of a given token ID to another address
    * Usage of this method is discouraged, use `safeTransferFrom` whenever possible
    * Requires the msg sender to be the owner, approved, or operator
    * @param from current owner of the token
    * @param to address to receive the ownership of the given token ID
    * @param tokenId uint256 ID of the token to be transferred
    */
    function transferFrom(address from, address to, uint256 tokenId) public whenNotPaused
    {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'ERC721: transfer caller is not owner nor approved');
        require(to != address(0), 'ERC721: transfer to address invalid');

        _transfer(from, to, tokenId);
    }

    /**
    * @dev Safely transfers the ownership of a given token ID to another address
    * If the target address is a contract, it must implement `onERC721Received`,
    * which is called upon a safe transfer, and return the magic value
    * `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`; otherwise,
    * the transfer is reverted.
    *
    * Requires the msg sender to be the owner, approved, or operator
    * @param from current owner of the token
    * @param to address to receive the ownership of the given token ID
    * @param tokenId uint256 ID of the token to be transferred
    */
    function safeTransferFrom(address from, address to, uint256 tokenId) public whenNotPaused
    {
        // solium-disable-next-line arg-overflow
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
    * @dev Safely transfers the ownership of a given token ID to another address
    * If the target address is a contract, it must implement `onERC721Received`,
    * which is called upon a safe transfer, and return the magic value
    * `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`; otherwise,
    * the transfer is reverted.
    * Requires the msg sender to be the owner, approved, or operator
    * @param from current owner of the token
    * @param to address to receive the ownership of the given token ID
    * @param tokenId uint256 ID of the token to be transferred
    * @param _data bytes data to send along with a safe transfer check
    */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public whenNotPaused
    {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'ERC721: transfer caller is not owner nor approved');
        _safeTransfer(from, to, tokenId, _data);
        
        //transferFrom(from, to, tokenId);
        // solium-disable-next-line arg-overflow
        //require(_checkOnERC721Received(from, to, tokenId, _data));
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), 'ERC721: transfer to non ERC721Receiver implementer');
    }

    /**
    * @dev Returns whether the specified token exists
    * @param tokenId uint256 ID of the token to query the existence of
    * @return whether the token exists
    */
    function _exists(uint256 tokenId) internal view returns (bool) {
        address owner = _tokenOwner[tokenId];
        return owner != address(0);
    }

    /**
    * @dev Returns whether the given spender can transfer a given token ID
    * @param spender address of the spender to query
    * @param tokenId uint256 ID of the token to be transferred
    * @return bool whether the msg.sender is approved for the given token ID,
    *  is an operator of the owner, or is the owner of the token
    */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool)
    {
        require(_exists(tokenId), 'ERC721: operator query for nonexistent token');
        
        address owner = ownerOf(tokenId);
        // Disable solium check because of
        // https://github.com/duaraghav8/Solium/issues/175
        // solium-disable-next-line operator-whitespace
        return (
            spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender)
        );
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal {
        _safeMint(to, tokenId, '');
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, _data), 'ERC721: transfer to non ERC721Receiver implementer');
    }

    /**
    * @dev Internal function to mint a new token
    * Reverts if the given token ID already exists
    * @param to The address that will own the minted token
    * @param tokenId uint256 ID of the token to be minted by the msg.sender
    */
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), 'ERC721: mint to the zero address');
        require(!_exists(tokenId), 'ERC721: token already minted');
        
        _beforeTokenTransfer(address(0), to, tokenId);
        _addTokenTo(to, tokenId);
        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId);
    }

    /**
    * @dev Internal function to burn a specific token
    * Reverts if the token does not exist
    * @param tokenId uint256 ID of the token being burned by the msg.sender
    */
    function _burn(address owner, uint256 tokenId) internal {
        _beforeTokenTransfer(owner, address(0), tokenId);
        _clearApproval(owner, tokenId);
        _removeTokenFrom(owner, tokenId);
        delete _tokenOwner[tokenId];
        emit Transfer(owner, address(0), tokenId);
    }

    /**
    * @dev Internal function to add a token ID to the list of a given address
    * Note that this function is left internal to make ERC721Enumerable possible, but is not
    * intended to be called by custom derived contracts: in particular, it emits no Transfer event.
    * @param to address representing the new owner of the given token ID
    * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
    */
    function _addTokenTo(address to, uint256 tokenId) internal {
        require(_tokenOwner[tokenId] == address(0));
        _tokenOwner[tokenId] = to;
        _balances[to] = _balances[to].add(1);
    }

    /**
    * @dev Internal function to remove a token ID from the list of a given address
    * Note that this function is left internal to make ERC721Enumerable possible, but is not
    * intended to be called by custom derived contracts: in particular, it emits no Transfer event,
    * and doesn't clear approvals.
    * @param from address representing the previous owner of the given token ID
    * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
    */
    function _removeTokenFrom(address from, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, 'ERC721: _removeTokenFrom of token that is not own');
        _balances[from] = _balances[from].sub(1);
        _tokenOwner[tokenId] = address(0);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, 'ERC721: transfer of token that is not own');
        require(to != address(0), 'ERC721: transfer to the zero address');

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _clearApproval(from, tokenId);
        _removeTokenFrom(from, tokenId);
        _addTokenTo(to, tokenId);

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal {
        address owner = ownerOf(tokenId);
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    /**
    * @dev Internal function to invoke `onERC721Received` on a target address
    * The call is not executed if the target address is not a contract
    * @param from address representing the previous owner of the given token ID
    * @param to target address that will receive the tokens
    * @param tokenId uint256 ID of the token to be transferred
    * @param _data bytes optional data to send along with the call
    * @return whether the call correctly returned the expected magic value
    */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data) internal returns (bool)
    {
        if (!to.isContract()) {
            return true;
        }
        bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, _data);
        return (retval == _ERC721_RECEIVED);
    }

    /**
    * @dev Private function to clear current approval of a given token ID
    * Reverts if the given address is not indeed the owner of the token
    * @param owner owner of the token
    * @param tokenId uint256 ID of the token to be transferred
    */
    function _clearApproval(address owner, uint256 tokenId) private {
        require(ownerOf(tokenId) == owner, 'ERC721: _clearApproval of token that is not own');
        if (_tokenApprovals[tokenId] != address(0)) {
            _tokenApprovals[tokenId] = address(0);
        }
    }
    
    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal {}
}



