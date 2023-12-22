// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./ERC1155Burnable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Strings.sol";
import "./Counters.sol";
import "./Address.sol";
import "./Pausable.sol";

contract JoyStick is ERC1155Burnable, Ownable, Pausable, ReentrancyGuard {
    using Strings for string;
    using Address for address;
    using Counters for Counters.Counter;

    event Received(address, uint256);
    event SetAllowContract(bool);
    event Mint(address, uint256, uint256);
    event SetSaleStarts(uint256, bool);
    event SetTokenPrice(uint256, uint256);

    // Contract name
    string public name;
    // Contract symbol
    string public symbol;

    mapping(uint256 => uint256) private _totalSupply;
    mapping(uint256 => address) public creators;

    //////
    //token information
    //////
    // URI's default URI prefix
    string internal baseMetadataURI;
    uint256 private _currentTokenID = 0;

    //////
    // market information
    /////
    bool private allowContract;
    mapping(uint256 => bool) public saleStarts;
    mapping(uint256 => uint256) public tokenPrice;

    //events
    // event URI(string _uri, uint256 indexed _id);
    /**
     * @dev Require msg.sender to be the creator of the token id
     */
    modifier creatorOnly(uint256 _id) {
        require(
            creators[_id] == msg.sender,
            "ERC1155Tradable#creatorOnly: ONLY_CREATOR_ALLOWED"
        );
        _;
    }

    constructor(
        string memory _uri,
        string memory _name,
        string memory _symbol
    ) ERC1155("") {
        name = _name;
        symbol = _symbol;
        baseMetadataURI = _uri;
    }

    //////
    ///team functions
    //////

    function create(
        address _initialOwner,
        uint256 _initialSupply,
        string calldata _uri,
        bytes calldata _data
    ) external onlyOwner returns (uint256) {
        uint256 _id = _getNextTokenID();
        _incrementTokenTypeId();
        creators[_id] = msg.sender;

        if (bytes(_uri).length > 0) {
            emit URI(_uri, _id);
        }

        _mint(_initialOwner, _id, _initialSupply, _data);
        return _id;
    }

    function airdrop(
        address[] calldata _addresses,
        uint256 _id,
        uint256[] calldata _amounts,
        bytes memory data
    ) external onlyOwner {
        require(
            _addresses.length == _amounts.length,
            "airdrop: length mismatch"
        );
        require(exists(_id), "airdrop: nonexistent id");
        //mint
        for (uint256 i = 0; i < _addresses.length; i++) {
            safeTransferFrom(msg.sender, _addresses[i], _id, _amounts[i], data);
        }
    }

    function mintDrop(
        address[] calldata _addresses,
        uint256 _id,
        uint256[] calldata _amounts,
        bytes memory data
    ) external onlyOwner {
        require(
            _addresses.length == _amounts.length,
            "mintDrop: length mismatch"
        );
        require(
            _id > 0 && _id <= _currentTokenID,
            "mintDrop: id does not exist"
        );
        //mint
        for (uint256 i = 0; i < _addresses.length; i++) {
            _mint(_addresses[i], _id, _amounts[i], data);
        }
    }

    ///////
    // market place
    //////
    function mint(
        address _to,
        uint256 _id,
        uint256 quantity
    ) external payable nonReentrant whenNotPaused {
        require(saleStarts[_id] == true, "sale has not started");
        require(quantity > 0, "buy: Quantity zero");
        require(_to != address(0), "buy: cannot send to zero address");

        //check if contract minting is allowed..
        requestMint();

        //payment
        uint256 cost = quantity * tokenPrice[_id];
        require(msg.value == cost, "eth sent incorrect");

        //mint
        _mint(_to, _id, quantity, "");

        emit Mint(_to, _id, quantity);
    }

    /**
     * @dev Change the creator address for given tokens
     * @param _to   Address of the new creator
     * @param _ids  Array of Token IDs to change creator
     */
    function setCreator(address _to, uint256[] memory _ids) public {
        require(
            _to != address(0),
            "ERC1155Tradable#setCreator: INVALID_ADDRESS."
        );
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            _setCreator(_to, id);
        }
    }

    /**
     * @dev Change the creator address for given token
     * @param _to   Address of the new creator
     * @param _id  Token IDs to change creator of
     */
    function _setCreator(address _to, uint256 _id) internal creatorOnly(_id) {
        creators[_id] = _to;
    }

    function setAllowContract(bool _allow) public onlyOwner {
        allowContract = _allow;
        emit SetAllowContract(_allow);
    }

    function setSaleStarts(uint256 _id, bool _bool) public onlyOwner {
        saleStarts[_id] = _bool;
        emit SetSaleStarts(_id, _bool);
    }

    function setTokenPrice(uint256 _id, uint256 _price) public onlyOwner {
        tokenPrice[_id] = _price;
        emit SetTokenPrice(_id, _price);
    }

    ///////
    // Pause
    ///////
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    //////
    //getter functions
    //////

    /**
     * @dev Total amount of tokens in with a given id.
     */
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return _totalSupply[id];
    }

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 id) public view virtual returns (bool) {
        return _totalSupply[id] > 0;
    }

    /***********************************|
  |     Metadata Public Function s    |
  |__________________________________*/

    /**
     * @notice A distinct Uniform Resource Identifier (URI) for a given token.
     * @dev URIs are defined in RFC 3986.
     *      URIs are assumed to be deterministically generated based on token ID
     *      Token IDs are assumed to be represented in their hex format in URIs
     * @return URI string
     */
    function uri(uint256 _id) public view override returns (string memory) {
        require(exists(_id), "ERC1155 uri: nonexistent token id");
        return
            bytes(baseMetadataURI).length != 0
                ? string(
                    abi.encodePacked(baseMetadataURI, Strings.toString(_id))
                )
                : "";
    }

    /**
     * @notice Will update the base URL of token's URI
     * @param _newBaseMetadataURI New base URL of token's URI
     */

    function setBaseMetadataURI(string memory _newBaseMetadataURI)
        external
        onlyOwner
    {
        baseMetadataURI = _newBaseMetadataURI;
    }

    //////
    // hooks
    //////

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        require(!paused(), "ERC1155Pausable: token transfer while paused");

        if (from == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                _totalSupply[ids[i]] += amounts[i];
            }
        }

        if (to == address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                uint256 id = ids[i];
                uint256 amount = amounts[i];
                uint256 supply = _totalSupply[id];

                require(
                    supply >= amount,
                    "ERC1155: burn amount exceeds totalSupply"
                );
                unchecked {
                    _totalSupply[id] = supply - amount;
                }
            }
        }
    }

    //////
    // utils
    //////
    /**
     * @dev calculates the next token ID based on value of _currentTokenID
     * @return uint256 for the next token ID
     */
    function _getNextTokenID() private view returns (uint256) {
        return _currentTokenID + 1;
    }

    /**
     * @dev increments the value of _currentTokenID
     */
    function _incrementTokenTypeId() private {
        _currentTokenID++;
    }

    function requestMint() private view {
        if (!allowContract) {
            require(
                tx.origin == msg.sender,
                "only EOA can mint, not a contract"
            );
        }
    }

    ///////////////
    // Withdraw ETH
    ///////////////

    function withdraw(address treasuryAddress) public onlyOwner {
        require(treasuryAddress != address(0), "withdraw: address(0)");
        uint256 balance = address(this).balance;
        payable(treasuryAddress).transfer(balance);
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

