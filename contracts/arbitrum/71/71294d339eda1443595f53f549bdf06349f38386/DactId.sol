pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IReferralHub.sol";

/**
 * @title DACT-ID NFT
 * DACT-ID NFT - ERC721 contract that has minting functionality for users
 */

contract DactId is ERC721Upgradeable, OwnableUpgradeable {
    using SafeMath for uint256;

    struct UserInfo {
        bytes32 id;
        string info;
        uint256 createdAt;
        uint256 updatedAt;
    }

    mapping(uint256 => UserInfo) public users;
    mapping(bytes32 => uint256) public userIndexById;
    mapping(address => bool) public whitelists;

    /// @dev Events of the contract
    event Minted(uint256 tokenId, address minter);

    uint256 private _nextTokenId = 0;

    string public baseUri;

    uint256 public maxNftPerAddress = 1;
    bool public isTransferEnabled;
    bool public isWhitelistingMode;
    bool private isInitialized = false;
    address public referralHub;

    modifier onlyWhitelisted() {
        require(
            msg.sender == owner ||
                !isWhitelistingMode ||
                whitelists[msg.sender],
            "Dact NFT: NOT_WHITELISTED"
        );
        _;
    }

    modifier onlyInitializing() {
        require(!isInitialized, "initialized");
        _;
        isInitialized = true;
    }

    /// @notice Contract constructor
    constructor() public {}

    function initialize(
        string memory _name,
        string memory _symbol
    ) public onlyInitializing {
        __ERC721__init(_name, _symbol, type(uint256).max, type(uint256).max);
        __Ownable_init();
    }

    /// @inheritdoc	ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Upgradeable) returns (bool) {
        return ERC721Upgradeable.supportsInterface(interfaceId);
    }

    function setBaseUrl(string memory _baseUrl) external onlyOwner {
        super._setBaseURI(_baseUrl);
        baseUri = _baseUrl;
    }

    function setWhitelistMode(bool _mode) external onlyOwner {
        isWhitelistingMode = _mode;
    }

    function setWhitelistAddresses(
        address[] calldata _addrs
    ) external onlyOwner {
        for (uint256 i = 0; i < _addrs.length; i++) {
            whitelists[_addrs[i]] = true;
        }
    }

    function removeWhitelistAddresses(
        address[] calldata _addrs
    ) external onlyOwner {
        for (uint256 i = 0; i < _addrs.length; i++) {
            whitelists[_addrs[i]] = false;
        }
    }

    /**
     * @dev Mints a token to an address with a tokenURI.
     */
    function mint(
        bytes32 id,
        string calldata info,
        bytes32 referred
    ) external onlyWhitelisted returns (uint256) {
        uint256 newTokenId = getNextTokenId();

        address _sender = _msgSender();

        require(balanceOf(_sender) < maxNftPerAddress, "-"); // If NFTs are already exist, revert

        _safeMint(_sender, 1);

        require(userIndexById[id] == 0, "Id already exist");

        users[newTokenId].id = id;
        users[newTokenId].info = info;
        users[newTokenId].createdAt = block.timestamp;
        users[newTokenId].updatedAt = block.timestamp;

        userIndexById[id] = newTokenId + 1;

        _incrementTokenId();

        if (userIndexById[referred] > 0) {
            IReferralHub(referralHub).addReferral(
                userIndexById[referred].sub(1),
                newTokenId
            );
        }
        emit Minted(newTokenId, _sender);
        return newTokenId;
    }

    function claimReferral(uint256 _tokenId) external returns (uint256) {
        require(ownerOf(_tokenId) == _msgSender(), "invalid owner");
        IReferralHub(referralHub).claimReferral(_tokenId, _msgSender());
    }

    function getReferral(uint256 _tokenId) external view returns (uint256) {
        return IReferralHub(referralHub).getReferral(_tokenId);
    }

    function getReferredUsers(
        uint256 _tokenId
    )
        external
        view
        returns (UserInfo[] memory, address[] memory, uint256[] memory)
    {
        uint256[] memory userIds = IReferralHub(referralHub).getReferredUsers(
            _tokenId
        );
        UserInfo[] memory fls = new UserInfo[](userIds.length);
        address[] memory addrs = new address[](userIds.length);
        uint256[] memory tokenIds = new uint256[](userIds.length);

        for (uint256 i = 0; i < userIds.length; i++) {
            fls[i] = users[userIds[i]];
            addrs[i] = ownerOf(userIds[i]);
            tokenIds[i] = userIds[i];
        }
        return (fls, addrs, tokenIds);
    }

    function updateUserInfo(
        uint256 _tokenId,
        bytes32 id,
        string calldata info
    ) external {
        require(ownerOf(_tokenId) == _msgSender(), "invalid owner");

        UserInfo storage _user = users[_tokenId];
        if (_user.id != id) {
            require(userIndexById[id] == 0, "Id already exist");
            userIndexById[_user.id] = 0;
        }

        _user.id = id;
        _user.info = info;
        _user.updatedAt = block.timestamp;

        userIndexById[id] = _tokenId + 1;
    }

    function setMaxNftPerAddress(uint256 _nftCount) public onlyOwner {
        maxNftPerAddress = _nftCount;
    }

    function setTransferMode(bool _isEnabled) public onlyOwner {
        isTransferEnabled = _isEnabled;
    }

    function setReferralHub(address _referralHub) public onlyOwner {
        referralHub = _referralHub;
    }

    /**
     * @dev calculates the next token ID based on value of _nextTokenId
     * @return uint256 for the next token ID
     */
    function getNextTokenId() public view returns (uint256) {
        return _nextTokenId;
    }

    /**
     * @dev increments the value of _nextTokenId
     */
    function _incrementTokenId() private {
        _nextTokenId++;
    }

    function isApproved(
        uint256 _tokenId,
        address _operator
    ) public view returns (bool) {
        return
            isApprovedForAll(ownerOf(_tokenId), _operator) ||
            getApproved(_tokenId) == _operator;
    }

    function _beforeTokenTransfers(
        address from,
        address,
        uint256,
        uint256
    ) internal override {
        require(from == address(0) || isTransferEnabled, "+");
    }

    uint256[49] private __gap;
}

