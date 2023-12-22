// SPDX-License-Identifier: Unlicense
// Based on Chiru Labs and Apetimism NFT:
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";
import "./ERC721A.sol";
import "./IERC1155.sol";
import "./ERC1155.sol";
import "./IERC1155MetadataURI.sol";
import "./IERC1155Receiver.sol";

interface IJoystick is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id)
        external
        view
        returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator)
        external
        view
        returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must be have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    function exists(uint256 _id) external view returns (bool);
}

contract SpaceNerd is
    ERC721A,
    IERC1155Receiver,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    event Received(address, uint256);

    event SetBaseURI(string);
    event SetAllowContract(bool);
    event SetExtraURI(string);
    event SetEnableExtraURI(bool);
    event SetRound(ROUND);
    event SetClaimEnd(bool);
    event SetJoystickId(uint256);
    event SetTreasuryAddress(address);
    event SetEnableSpecialURI(bool);
    event SetAvailableIds(uint256[]);
    event SetJoystick(address);

    event Mint(address, uint256);
    event MintBatchNFT(address, uint256);
    event TotalMintedChanged(uint256);
    event TokenIdToRandom(uint256, uint256);

    uint16 public MAX_SUPPLY = 1402;

    // counter for randomness
    uint256 counter = 1;
    uint256[] availableIds;
    bool enableSpecialURI = true;

    string private _baseURIExtended;
    string private _extraURIExtended;

    enum ROUND {
        None,
        Holder
    }

    mapping(uint256 => string) private specialTokenURIs;

    mapping(address => uint16) private _addressTokenMinted;

    mapping(uint256 => uint256) private tokenIdToRandom;

    /////////////////////
    // Public Variables
    /////////////////////

    ROUND public round = ROUND.None;
    address public treasuryAddress;
    bool private allowContract;
    bool private enableExtraURI;
    bool private claimEnd;
    uint16 public lastRevealedTokenId;
    uint256 public joystickId = 1;

    // erc1155 compatible
    IJoystick private joystick;

    constructor(address _treasury, address _joystick)
        ERC721A("SpaceNerdNFT", "SPN")
    {
        treasuryAddress = _treasury;
        joystick = IJoystick(_joystick);
    }

    //////////////////////
    // Setters for Owner
    //////////////////////

    function setTreasuryAddress(address addr) public onlyOwner {
        require(addr != address(0), "address 0");
        treasuryAddress = addr;
        emit SetTreasuryAddress(addr);
    }

    function setRound(ROUND round_) public onlyOwner {
        round = round_;
        emit SetRound(round_);
    }

    function setBaseURI(string memory baseURI, uint16 _lastRevealedTokenId)
        external
        onlyOwner
    {
        _baseURIExtended = baseURI;
        lastRevealedTokenId = _lastRevealedTokenId;
        emit SetBaseURI(baseURI);
    }

    function setExtraURI(string memory baseURI) external onlyOwner {
        _extraURIExtended = baseURI;
        emit SetExtraURI(baseURI);
    }

    function setEnableExtraURI(bool _status) external onlyOwner {
        enableExtraURI = _status;
        emit SetEnableExtraURI(_status);
    }

    function setSpecialTokenURI(uint256[] memory tokenIds, string[] memory URIs)
        external
        onlyOwner
    {
        require(tokenIds.length == URIs.length, "inequal length");
        for (uint256 i = 0; i < tokenIds.length; i++) {
            specialTokenURIs[tokenIds[i]] = URIs[i];
        }
    }

    function setClaimEnd(bool _end) public onlyOwner {
        claimEnd = _end;
        emit SetClaimEnd(_end);
    }

    function setJoystick(address _joystick) public onlyOwner {
        joystick = IJoystick(_joystick);
        emit SetJoystick(_joystick);
    }

    function setAllowContract(bool _allow) public onlyOwner {
        allowContract = _allow;
        emit SetAllowContract(_allow);
    }

    function setJoystickId(uint256 _id) public onlyOwner {
        joystickId = _id;
        emit SetJoystickId(_id);
    }

    function setEnableSpecialURI(bool _bool) public onlyOwner {
        enableSpecialURI = _bool;
        emit SetEnableSpecialURI(_bool);
    }

    function setAvailableIds(uint256[] calldata _ids, bool _reset)
        public
        onlyOwner
    {
        if (_reset) {
            availableIds = _ids;
        } else {
            for (uint256 i = 0; i < _ids.length; i++) {
                availableIds.push(_ids[i]);
            }
        }

        emit SetAvailableIds(_ids);
    }

    function setERC1155ApprovalForAll(address operator, bool approved)
        public
        onlyOwner
    {
        joystick.setApprovalForAll(operator, approved);
    }

    //////////////
    // Pausable
    //////////////

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    ///////////////
    // Withdraw ETH
    ///////////////

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(treasuryAddress != address(0), "transfer to address 0");
        payable(treasuryAddress).transfer(balance);
    }

    //owner interact with joystick 1155
    function safeTransferFromJoystick(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public onlyOwner {
        joystick.safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFromJoystick(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public onlyOwner {
        joystick.safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    ////////////
    // Claiming
    ////////////

    function requestMint() private view {
        if (!allowContract) {
            require(
                tx.origin == msg.sender,
                "only EOA can mint, not a contract"
            );
        }
    }

    // claim for nerdape holders
    function claim() external nonReentrant whenNotPaused {
        require(round == ROUND.Holder, "allow only holder's round");
        require(claimEnd == false, "claim end");

        // interact with joystick balance in holder's wallet
        require(joystick.exists(joystickId), "joystick Id does not exist");
        uint256 balance = joystick.balanceOf(msg.sender, joystickId);
        require(balance > 0, "no joystick found in your wallet");
        joystick.safeTransferFrom(
            msg.sender,
            address(this),
            joystickId,
            balance,
            ""
        );

        string memory baseURI = _baseURI();
        require(bytes(baseURI).length != 0, "baseURI is not yet set");

        require(availableIds.length >= balance, "no available tokenIds");
        require(totalMinted() + balance <= MAX_SUPPLY, "exceed max supply");

        //check if contract minting is allowed..
        requestMint();

        for (uint256 i = 0; i < balance; i++) {
            uint256 randomInd = randomIndex();

            require(randomInd < availableIds.length);
            uint256 id = availableIds[randomInd];
            availableIds[randomInd] = availableIds[availableIds.length - 1];
            availableIds.pop();
            tokenIdToRandom[totalMinted() + i] = id;
            emit TokenIdToRandom(totalMinted() + i, id);
        }

        //mint
        _safeMint(msg.sender, balance);
        emit TotalMintedChanged(totalMinted());

        _addressTokenMinted[msg.sender] =
            _addressTokenMinted[msg.sender] +
            uint16(balance);
        emit Mint(msg.sender, balance);
    }

    // finish all minting and transfer to treasury and follow holders' direction.
    function finish() external nonReentrant whenNotPaused onlyOwner {
        require(round == ROUND.Holder, "allow only holder's round");

        uint256 left = MAX_SUPPLY - totalMinted();
        require(availableIds.length >= left, "no available tokenIds");

        //check if contract minting is allowed..
        requestMint();

        for (uint256 i = 0; i < left; i++) {
            uint256 randomInd = randomIndex();

            require(randomInd < availableIds.length);
            uint256 id = availableIds[randomInd];
            availableIds[randomInd] = availableIds[availableIds.length - 1];
            availableIds.pop();
            tokenIdToRandom[totalMinted() + i] = id;
            emit TokenIdToRandom(totalMinted() + i, id);
        }

        //mint
        require(treasuryAddress != address(0), "treasury address is not set");
        _safeMint(treasuryAddress, left);
        emit TotalMintedChanged(totalMinted());

        _addressTokenMinted[msg.sender] =
            _addressTokenMinted[msg.sender] +
            uint16(left);
        emit Mint(msg.sender, left);
    }

    function randomIndex() private returns (uint256) {
        uint256 index = random() % availableIds.length;
        return index;
    }

    function random() private returns (uint256) {
        counter++;
        return
            // convert hash to integer
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.difficulty,
                        block.timestamp,
                        block.number,
                        msg.sender,
                        counter
                    )
                )
            );
    }

    function idToRandom(uint256 _tokenId) public view returns (uint256) {
        return tokenIdToRandom[_tokenId];
    }

    ///////////////////
    // Internal Views
    ///////////////////

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIExtended;
    }

    function _extraURI() internal view virtual returns (string memory) {
        return _extraURIExtended;
    }

    /////////////////
    // Public Views
    /////////////////

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (tokenId > lastRevealedTokenId && enableExtraURI == true) {
            string memory extraURI = _extraURI();
            return
                bytes(extraURI).length != 0
                    ? string(
                        abi.encodePacked(extraURI, Strings.toString(tokenId))
                    )
                    : "";
        }

        string memory baseURI = _baseURI();

        if (bytes(specialTokenURIs[tokenId]).length > 0 && enableSpecialURI)
            return specialTokenURIs[tokenId];

        return
            bytes(baseURI).length != 0
                ? string(abi.encodePacked(baseURI, Strings.toString(tokenId)))
                : "";
    }

    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external pure returns (bytes4) {
        return
            bytes4(
                keccak256(
                    "onERC1155Received(address,address,uint256,uint256,bytes)"
                )
            );
    }

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external pure returns (bytes4) {
        return
            bytes4(
                keccak256(
                    "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
                )
            );
    }

    /////////////
    // Fallback
    /////////////

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable {
        revert();
    }
}

