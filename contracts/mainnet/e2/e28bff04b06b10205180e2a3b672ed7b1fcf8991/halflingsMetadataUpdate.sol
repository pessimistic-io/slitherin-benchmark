// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./Context.sol";
import "./ECDSA.sol";

interface IERC721  {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}


interface ERC1155 /* is ERC165 */ {
    /**
        @dev Either `TransferSingle` or `TransferBatch` MUST emit when tokens are transferred, including zero value transfers as well as minting or burning (see "Safe Transfer Rules" section of the standard).
        The `_operator` argument MUST be the address of an account/contract that is approved to make the transfer (SHOULD be msg.sender).
        The `_from` argument MUST be the address of the holder whose balance is decreased.
        The `_to` argument MUST be the address of the recipient whose balance is increased.
        The `_id` argument MUST be the token type being transferred.
        The `_value` argument MUST be the number of tokens the holder balance is decreased by and match what the recipient balance is increased by.
        When minting/creating tokens, the `_from` argument MUST be set to `0x0` (i.e. zero address).
        When burning/destroying tokens, the `_to` argument MUST be set to `0x0` (i.e. zero address).        
    */
    event TransferSingle(address indexed _operator, address indexed _from, address indexed _to, uint256 _id, uint256 _value);

    /**
        @dev Either `TransferSingle` or `TransferBatch` MUST emit when tokens are transferred, including zero value transfers as well as minting or burning (see "Safe Transfer Rules" section of the standard).      
        The `_operator` argument MUST be the address of an account/contract that is approved to make the transfer (SHOULD be msg.sender).
        The `_from` argument MUST be the address of the holder whose balance is decreased.
        The `_to` argument MUST be the address of the recipient whose balance is increased.
        The `_ids` argument MUST be the list of tokens being transferred.
        The `_values` argument MUST be the list of number of tokens (matching the list and order of tokens specified in _ids) the holder balance is decreased by and match what the recipient balance is increased by.
        When minting/creating tokens, the `_from` argument MUST be set to `0x0` (i.e. zero address).
        When burning/destroying tokens, the `_to` argument MUST be set to `0x0` (i.e. zero address).                
    */
    event TransferBatch(address indexed _operator, address indexed _from, address indexed _to, uint256[] _ids, uint256[] _values);

    /**
        @dev MUST emit when approval for a second party/operator address to manage all tokens for an owner address is enabled or disabled (absence of an event assumes disabled).        
    */
    event ApprovalForAll(address indexed _owner, address indexed _operator, bool _approved);

    /**
        @dev MUST emit when the URI is updated for a token ID.
        URIs are defined in RFC 3986.
        The URI MUST point to a JSON file that conforms to the "ERC-1155 Metadata URI JSON Schema".
    */
    event URI(string _value, uint256 indexed _id);

    /**
        @notice Transfers `_value` amount of an `_id` from the `_from` address to the `_to` address specified (with safety call).
        @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
        MUST revert if `_to` is the zero address.
        MUST revert if balance of holder for token `_id` is lower than the `_value` sent.
        MUST revert on any other error.
        MUST emit the `TransferSingle` event to reflect the balance change (see "Safe Transfer Rules" section of the standard).
        After the above conditions are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call `onERC1155Received` on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).        
        @param _from    Source address
        @param _to      Target address
        @param _id      ID of the token type
        @param _value   Transfer amount
        @param _data    Additional data with no specified format, MUST be sent unaltered in call to `onERC1155Received` on `_to`
    */
    function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _value, bytes calldata _data) external;

    /**
        @notice Transfers `_values` amount(s) of `_ids` from the `_from` address to the `_to` address specified (with safety call).
        @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
        MUST revert if `_to` is the zero address.
        MUST revert if length of `_ids` is not the same as length of `_values`.
        MUST revert if any of the balance(s) of the holder(s) for token(s) in `_ids` is lower than the respective amount(s) in `_values` sent to the recipient.
        MUST revert on any other error.        
        MUST emit `TransferSingle` or `TransferBatch` event(s) such that all the balance changes are reflected (see "Safe Transfer Rules" section of the standard).
        Balance changes and events MUST follow the ordering of the arrays (_ids[0]/_values[0] before _ids[1]/_values[1], etc).
        After the above conditions for the transfer(s) in the batch are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call the relevant `ERC1155TokenReceiver` hook(s) on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).                      
        @param _from    Source address
        @param _to      Target address
        @param _ids     IDs of each token type (order and length must match _values array)
        @param _values  Transfer amounts per token type (order and length must match _ids array)
        @param _data    Additional data with no specified format, MUST be sent unaltered in call to the `ERC1155TokenReceiver` hook(s) on `_to`
    */
    function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _values, bytes calldata _data) external;

    /**
        @notice Get the balance of an account's tokens.
        @param _owner  The address of the token holder
        @param _id     ID of the token
        @return        The _owner's balance of the token type requested
     */
    function balanceOf(address _owner, uint256 _id) external view returns (uint256);

    /**
        @notice Get the balance of multiple account/token pairs
        @param _owners The addresses of the token holders
        @param _ids    ID of the tokens
        @return        The _owner's balance of the token types requested (i.e. balance for each (owner, id) pair)
     */
    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids) external view returns (uint256[] memory);

    /**
        @notice Enable or disable approval for a third party ("operator") to manage all of the caller's tokens.
        @dev MUST emit the ApprovalForAll event on success.
        @param _operator  Address to add to the set of authorized operators
        @param _approved  True if the operator is approved, false to revoke approval
    */
    function setApprovalForAll(address _operator, bool _approved) external;

    /**
        @notice Queries the approval status of an operator for a given owner.
        @param _owner     The owner of the tokens
        @param _operator  Address of authorized operator
        @return           True if the operator is approved, false if not
    */
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
    function mint(address to, uint256 id, uint256 amount) external;
    function burn(address user,uint256 id, uint256 amount) external;
}

contract halflingsMetadataUpdate is Ownable {
      address public halflingsNft=0x5266c5aca260818Be013C80bd9ed5ba0F3D49070;
      address public halflingsItems=0x867E2f5CBBF0e1214675B577cD13c1D1ccF2B204;
      address public authAddress = 0x350F84C2f5272973646342Be1AdbE232324A552E;
      mapping(uint256 =>mapping(uint256 => bool)) public _isItemRemoved;
      mapping(uint256 =>mapping(uint256 => bool)) public _isAttributeAvailable;
      mapping(uint256 =>bool) public isSeedUsed;
      bool public _isPause;
      constructor()  {}



      event Withdraw(uint256 amount);
      event contractPauseEvent(bool isPause,address user);
      event _addItems(address user,uint256 nftid,uint256[] itemId,uint256[] attributeId,bool[] isFirstAttribute,uint256 seed);
      event _removeItem(address user,uint256 nftid,uint256 itemId,uint256 attributeId,uint256 seed);
      event _multipleRemoveItem(address user,uint256 nftid,uint256[] itemId,uint256[] attributeId,uint256 seed);
      event sethalflingsNftEvent(address callerAddress,address halflingsNft);
      event sethalflingsItemsEvent(address callerAddress,address halflingsItems);
      event sethAuthAddressEvent(address callerAddress,address halflingsItems);


    //addItems items from NFT
    function addItems(
        uint256 nftid,
        uint256[] memory itemId,
        uint256[] memory attributeId,
        bool[] memory isFirstAttribute,
        uint256 seed,
        bytes calldata signature
    ) external {
        bytes32 hash = keccak256(abi.encodePacked(_msgSender(),nftid,itemId,attributeId,isFirstAttribute,seed));
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        address receivedAddress = ECDSA.recover(message, signature);
        require(receivedAddress == authAddress, "Invalid signature");
        require(!isSeedUsed[seed], "Seed is used");
        require(!_isPause, "currently contract is paused");
        isSeedUsed[seed]=true;
        require((IERC721(halflingsNft).ownerOf(nftid) == _msgSender()),"caller is not owner of NFT");
        for(uint itemcount=0;itemcount<itemId.length;itemcount++){
        require((ERC1155(halflingsItems).balanceOf(_msgSender(),itemId[itemcount]) >0),"caller is not owner of NFT item");
        if(_isAttributeAvailable[nftid][attributeId[itemcount]] || isFirstAttribute[itemcount]  )
        {
        require((_isItemRemoved[nftid][attributeId[itemcount]]== true),"need to remove item from NFT");
        }
        _isAttributeAvailable[nftid][attributeId[itemcount]]=true;
        _isItemRemoved[nftid][attributeId[itemcount]] = false;
        ERC1155(halflingsItems).burn(_msgSender(),itemId[itemcount],1);
        }
        emit _addItems(_msgSender(),nftid,itemId,attributeId,isFirstAttribute,seed);
    }



    //removeItem items to NFT
    function removeItem(
        uint256 nftid,
        uint256 itemId,
        uint256 attributeId,
        uint256 seed,
        bytes calldata signature
    ) external { 
        bytes32 hash = keccak256(abi.encodePacked(_msgSender(),nftid,itemId,attributeId,seed));
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        address receivedAddress = ECDSA.recover(message, signature);
        require(receivedAddress == authAddress, "Invalid signature");
        require(!isSeedUsed[seed], "Seed is used");
        require(!_isPause, "currently contract is paused");
        isSeedUsed[seed]=true;
        require((IERC721(halflingsNft).ownerOf(nftid) == _msgSender()),"caller is not owner of NFT");
        require((_isItemRemoved[nftid][attributeId] == false),"item already removed from NFT");
        _isItemRemoved[nftid][attributeId] = true;
        ERC1155(halflingsItems).mint(_msgSender(),itemId,1);
        emit _removeItem(_msgSender(),nftid,itemId,attributeId,seed);
    }


    //multipleRemove items to NFT
    function multipleRemove(
        uint256 nftid,
        uint256[] memory itemId,
        uint256[] memory attributeId,
        uint256 seed,
        bytes calldata signature
    ) external { 
        bytes32 hash = keccak256(abi.encodePacked(_msgSender(),nftid,itemId,attributeId,seed));
        bytes32 message = ECDSA.toEthSignedMessageHash(hash);
        address receivedAddress = ECDSA.recover(message, signature);
        require(receivedAddress == authAddress, "Invalid signature");
        require(!isSeedUsed[seed], "Seed is used");
        require(!_isPause, "currently contract is paused");
        isSeedUsed[seed]=true;
        require((IERC721(halflingsNft).ownerOf(nftid) == _msgSender()),"caller is not owner of NFT");
        for(uint itemcount=0;itemcount<itemId.length;itemcount++){
        require((_isItemRemoved[nftid][attributeId[itemcount]] == false),"item already removed from NFT");
        _isItemRemoved[nftid][attributeId[itemcount]] = true;
        ERC1155(halflingsItems).mint(_msgSender(),itemId[itemcount],1);
        }
        emit _multipleRemoveItem(_msgSender(),nftid,itemId,attributeId,seed);
    }


     // BNB sent by mistake can be returned
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;

        payable( msg.sender ).transfer( balance );
        
        emit Withdraw(balance);
    }

   
    function sethalflingsNft(address _address) external onlyOwner {
        require(_address != address(0));
        halflingsNft = _address;
        emit sethalflingsNftEvent( _msgSender(),_address );
    }

    function sethAuthAddress(address _address) external onlyOwner {
        require(_address != address(0));
        authAddress = _address;
        emit sethAuthAddressEvent( _msgSender(),_address );
    }
    function sethalflingsItems(address _address) external onlyOwner {
        require(_address != address(0));
        halflingsItems = _address;
        emit sethalflingsItemsEvent( _msgSender(),_address );
    }
    function pause(bool isPause) external onlyOwner {
        _isPause = isPause;
        emit contractPauseEvent( isPause,msg.sender );
    }

}
