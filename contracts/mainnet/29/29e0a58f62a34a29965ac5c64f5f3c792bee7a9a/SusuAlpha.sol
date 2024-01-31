// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "./ERC721A.sol";
import "./ERC721Holder.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./Base64.sol";
import "./Strings.sol";
import "./AccessControl.sol";
import "./IERC4907.sol";

contract SusuAlpha is
    ERC721A,
    IERC4907,
    ERC721Holder,
    Ownable,
    AccessControl,
    ReentrancyGuard
{
    using Strings for uint256;
    using Strings for uint64;

    address public vaultAddress;

    string public baseURI =
        "https://arweave.net/j4Qsub_JdHdIZzLByyi_vJlAbz4dJNUS1OU_9Jjz0ic/";
    string public hiddenMetadataURI = "";
    string public imageURIExtension = ".png";

    uint256 public upgradeAmount = 5;
    uint256 public constant MAX_SUPPLY = 500;
    uint256 public constant MAX_MINT_WHITELIST = 1;

    bytes32 public merkleRoot =
        0x25abe86353f5cc3b4ba42c3827af94ce90d2e0a0391621586773671422cef528;
    bool public isWhitelistMintActive = false;
    bool public isUniqueImage = true;
    bool public revealed = true;

    uint256[] public trialPassIds;
    uint256[] public blacklist;

    mapping(address => uint256) public totalMinted;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum PassLevel {
        Gold,
        Silver,
        Trial
    }

    struct UserInfo {
        address user; // address of user role
        uint64 expires; // unix timestamp, user expires
    }

    struct PassInfo {
        PassLevel level;
    }

    mapping(uint256 => PassInfo) internal _passes;
    mapping(uint256 => UserInfo) internal _users;

    /// @notice event emitted when a user has upgrade nft
    event UpgradedNFT(address owner, uint256[] tokenIds, uint256 tokenId);

    /// @notice event emitted when a token add or remove on blacklist
    event AddBlacklist(uint256 tokenId);
    event RemoveBlacklist(uint256 tokenId);

    constructor(string memory name_, string memory symbol_)
        ERC721A(name_, symbol_)
    {
        vaultAddress = msg.sender;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
        _setRoleAdmin(DEFAULT_ADMIN_ROLE, OPERATOR_ROLE);
    }

    function whitelistMint(uint256 _quantity, bytes32[] calldata _proof)
        external
        payable
        nonReentrant
    {
        require(isWhitelistMintActive, "Whitelist mint is not active");
        require(isWhiteListed(msg.sender, _proof), "Not whitelisted");
        require(_quantity > 0, "Invalid quantity");
        require(
            totalMinted[msg.sender] + _quantity <= MAX_MINT_WHITELIST,
            "Max mint reached"
        );
        require(totalSupply() + _quantity <= MAX_SUPPLY, "Max supply reached");
        totalMinted[msg.sender] += _quantity;
        _safeMint(msg.sender, _quantity);
    }

    function isWhiteListed(address _account, bytes32[] calldata _proof)
        internal
        view
        returns (bool)
    {
        return _verify(leaf(_account), _proof);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function leaf(address _account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account));
    }

    function _verify(bytes32 _leaf, bytes32[] memory _proof)
        internal
        view
        returns (bool)
    {
        return MerkleProof.verify(_proof, merkleRoot, _leaf);
    }

    function setBaseURI(string memory _newURI) public onlyOwner {
        baseURI = _newURI;
    }

    function setUpgradeAmount(uint256 _upgradeAmount) public onlyOwner {
        require(_upgradeAmount > 1, "Upgrade amount must be greater than 1");
        upgradeAmount = _upgradeAmount;
    }

    function setImageExtension(string memory _newImageURIExtension)
        public
        onlyOwner
    {
        imageURIExtension = _newImageURIExtension;
    }

    function getPassLevel(uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        PassLevel level = _passes[_tokenId].level;
        if (level == PassLevel.Gold) {
            return "Gold";
        } else if (level == PassLevel.Trial) {
            return "Trial";
        }

        return "Silver";
    }

    function _getExpireDate(uint256 _tokenId)
        internal
        view
        returns (string memory)
    {
        PassLevel level = _passes[_tokenId].level;
        if (level == PassLevel.Trial) {
            if (userOf(_tokenId) == address(0)) {
                return "0";
            } else {
                uint64 expireTime = _users[_tokenId].expires;
                return expireTime.toString();
            }
        }
        return "Lifetime";
    }

    function _getExpiredIds()
        internal
        view
        returns (uint256[] memory _tokenIds)
    {
        uint256 expiredAmount = getExpiredAmount();
        require(expiredAmount > 0, "Not expired token");
        uint256[] memory expiredIds = new uint256[](expiredAmount);
        uint256 index = 0;
        for (uint256 i = 0; i < trialPassIds.length; i++) {
            if (uint256(_users[trialPassIds[i]].expires) < block.timestamp) {
                expiredIds[index] = trialPassIds[i];
                index++;
            }
        }
        return expiredIds;
    }

    function getExpiredAmount() public view returns (uint256) {
        uint256 expiredAmount;
        for (uint256 i = 0; i < trialPassIds.length; i++) {
            if (uint256(_users[trialPassIds[i]].expires) < block.timestamp) {
                expiredAmount++;
            }
        }
        return expiredAmount;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function _getImageName(uint256 _tokenId)
        internal
        view
        returns (string memory)
    {
        if (isUniqueImage) {
            return uint256(_passes[_tokenId].level).toString();
        }
        return _tokenId.toString();
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(_tokenId)) revert URIQueryForNonexistentToken();

        if (!revealed) {
            return hiddenMetadataURI;
        }

        string memory currentBaseURI = _baseURI();

        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": "Susu Alpha ',
            getPassLevel(_tokenId),
            " Pass #",
            _tokenId.toString(),
            '",',
            '"image": "',
            currentBaseURI,
            _getImageName(_tokenId),
            imageURIExtension,
            '",',
            '"attributes": [',
            "{"
            '"trait_type": "Level",',
            '"value": "',
            getPassLevel(_tokenId),
            '"',
            "},"
            "{"
            '"trait_type": "Expire",',
            '"value": "',
            _getExpireDate(_tokenId),
            '"',
            "}"
            "]",
            "}"
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(dataURI)
                )
            );
    }

    // NFT upgrade
    function upgradeNFT(uint256[] memory tokenIds)
        external
        nonReentrant
        beforeUpgradeCheck(msg.sender, tokenIds)
    {
        _upgradeNFT(msg.sender, tokenIds);
    }

    function _upgradeNFT(address _user, uint256[] memory _tokenIds) internal {
        for (uint256 i = 1; i < upgradeAmount; i++) {
            approve(address(this), _tokenIds[i]);
            safeTransferFrom(_user, address(this), _tokenIds[i]);
            PassInfo storage trialPass = _passes[_tokenIds[i]];
            trialPass.level = PassLevel.Trial;
            trialPassIds.push(_tokenIds[i]);
        }
        PassInfo storage goldPass = _passes[_tokenIds[0]];
        goldPass.level = PassLevel.Gold;
        emit UpgradedNFT(_user, _tokenIds, _tokenIds[0]);
    }

    modifier beforeUpgradeCheck(address _user, uint256[] memory _tokenIds) {
        require(
            _tokenIds.length == upgradeAmount,
            "Upgrade pass amount is not correct"
        );
        for (uint256 i = 0; i < upgradeAmount; i++) {
            require(
                ownerOf(_tokenIds[i]) == _user,
                "User must be the owner of the token"
            );
            require(
                _passes[_tokenIds[i]].level == PassLevel.Silver,
                "Upgrade pass need silver pass"
            );
        }
        _;
    }

    modifier isTrialPass(uint256 tokenId) {
        require(_passes[tokenId].level == PassLevel.Trial, "Not trial pass");
        _;
    }

    // Admin
    function toggleWhitelistMint() external onlyOwner {
        isWhitelistMintActive = !isWhitelistMintActive;
    }

    function closeMint() external onlyOwner {
        isWhitelistMintActive = false;
    }

    function toggleIsUniqueImage() external onlyOwner {
        isUniqueImage = !isUniqueImage;
    }

    function toggleReveal() external onlyOwner {
        revealed = !revealed;
    }

    // Airdrop.
    function airdrop(address[] memory team, uint256[] memory teamMint)
        external
        onlyOwner
    {
        require(
            team.length == teamMint.length,
            "Team and teamMint are not equal"
        );
        for (uint256 i = 0; i < team.length; i++) {
            require(
                totalSupply() + teamMint[i] <= MAX_SUPPLY,
                "Max supply exceeded"
            );
            _safeMint(team[i], teamMint[i]);
        }
    }

    // Airdrop trial pass
    function airdropTrialPass(
        address[] memory airdropUsers,
        uint64[] memory expireDays
    ) external onlyRole(OPERATOR_ROLE) {
        require(
            airdropUsers.length == expireDays.length,
            "Users and expires are not equal"
        );
        require(
            airdropUsers.length <= getExpiredAmount(),
            "Expired passes are not enough for airdrop"
        );
        uint256[] memory expiredPassIds = _getExpiredIds();
        for (uint256 i = 0; i < airdropUsers.length; i++) {
            _setTrialPassExpires(
                expiredPassIds[i],
                airdropUsers[i],
                expireDays[i]
            );
        }
    }

    function setVaultAddress(address _vaultAddress) public onlyOwner {
        vaultAddress = _vaultAddress;
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        payable(vaultAddress).transfer(balance);
    }

    function _sendValue(address recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Insufficient balance");
        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Unable to send ETH");
    }

    function _setTrialPassExpires(
        uint256 _tokenId,
        address _user,
        uint64 _days
    ) internal onlyRole(OPERATOR_ROLE) {
        uint64 expireTime = uint64(block.timestamp + (_days * 1 days));
        setUser(_tokenId, _user, expireTime);
    }

    function isBlacklist(uint256 tokenId) public view returns (bool) {
        bool isBlack = false;
        for (uint256 i = 0; i < blacklist.length; i++) {
            if (tokenId == blacklist[i]) {
                isBlack = true;
                break;
            }
        }
        return isBlack;
    }

    function removeBlacklist(uint256 tokenId) public onlyOwner {
        require(blacklist.length > 0, "No blacklist");
        uint256 index = 0;
        bool flag = false;
        for (uint256 k = 0; k < blacklist.length; k++) {
            if (blacklist[k] == tokenId) {
                index = k;
                flag = true;
                break;
            }
        }
        if (flag) {
            for (uint256 i = index; i < blacklist.length - 1; i++) {
                blacklist[i] = blacklist[i + 1];
            }
        }
        blacklist.pop();
        emit RemoveBlacklist(tokenId);
    }

    function addBlacklist(uint256 tokenId) public onlyOwner {
        if (tokenId < MAX_SUPPLY) {
            blacklist.push(tokenId);
            emit AddBlacklist(tokenId);
        }
    }

    function setUser(
        uint256 tokenId,
        address user,
        uint64 expires
    ) public virtual isTrialPass(tokenId) onlyRole(OPERATOR_ROLE) {
        require(
            getApproved(tokenId) == address(this) ||
                ownerOf(tokenId) == address(this),
            "ERC4907: transfer caller is not owner nor approved"
        );
        UserInfo storage info = _users[tokenId];
        info.user = user;
        info.expires = expires;
        emit UpdateUser(tokenId, user, expires);
    }

    function userOf(uint256 tokenId) public view virtual returns (address) {
        if (uint256(_users[tokenId].expires) >= block.timestamp) {
            return _users[tokenId].user;
        } else {
            return address(0);
        }
    }

    function userExpires(uint256 tokenId)
        public
        view
        virtual
        returns (uint256)
    {
        return _users[tokenId].expires;
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, AccessControl)
        returns (bool)
    {
        return
            interfaceId == type(IERC4907).interfaceId ||
            ERC721A.supportsInterface(interfaceId) ||
            AccessControl.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfers(
        address from,
        address, /*to*/
        uint256 tokenId,
        uint256 quantity
    ) internal virtual override {
        require(!isBlacklist(tokenId), "The token prohibit transactions");
        if (from == address(0)) {
            for (uint256 i = tokenId; i < tokenId + quantity; i++) {
                PassInfo storage info = _passes[i];
                info.level = PassLevel.Silver;
            }
        }
    }
}

