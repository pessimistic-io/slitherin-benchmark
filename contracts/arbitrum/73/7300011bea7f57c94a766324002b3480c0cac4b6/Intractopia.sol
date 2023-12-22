// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ECDSA.sol";
import "./draft-EIP712Upgradeable.sol";
import "./Initializable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ERC2771ContextUpgradeable.sol";
import "./ERC1155Upgradeable.sol";

contract IntractopiaStorage {
    /* ============ TypeHashes and Constants ============ */

    bytes32 public constant ERC1155_CLAIM_TYPEHASH = keccak256(
        "ERC1155Claim(uint96 rewardId,uint96 userId,address userAddress,uint256 amountToClaim)"
    );

    bytes32 public constant ERC1155_DUMMY_CLAIM_TYPEHASH = keccak256(
        "ERC1155DummyClaim(uint96 rewardId,uint96 userId,address userAddress)"
    );

    /* ============ Events ============ */

    event ERC1155SignerUpdate(address oldSigner, address newSigner);

    event ERC1155CollectionLaunch(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 initialSupply
    );

    event ERC1155Claim(
        uint96 rewardId,
        uint96 indexed userId,
        address indexed userAddress,
        uint256 indexed tokenId,
        uint256 amountToClaim
    );

    event ERC1155DummyClaim(
        uint96 indexed rewardId,
        uint96 indexed userId,
        address userAddress
    );
    
    /* ============ Structs ============ */

    /* ============ State Variables ============ */

    // Intract Signer
    address public intractSigner;

    // TokenId 
    uint256 public _currentTokenId = 0;

    // Mapping from tokenId to creator address
	mapping (uint256 => address) public creator;

    // Mapping from tokenId to admin addresses
    mapping (uint256 => mapping (address => bool)) public isAdmin;

    // Mapping from tokenId to current token supply
	mapping (uint256 => uint256) public tokenSupply;

    // rewardId => userAddress => if he has claimed
    mapping(uint96 => mapping(address => bool)) public hasClaimed;

    // rewardId => userId => if he has claimed
    mapping(uint96 => mapping(uint96 => bool)) public hasClaimedUserId;

    // signature => if it has been used
    mapping(bytes32 => bool) public usedDummyClaimHashes;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

contract Intractopia is Initializable, OwnableUpgradeable, PausableUpgradeable, EIP712Upgradeable, ReentrancyGuardUpgradeable, ERC1155Upgradeable, ERC2771ContextUpgradeable, IntractopiaStorage {

    /* ============ Modifiers ============ */

    modifier tokenExists(uint256 _tokenId) {
        require(creator[_tokenId] != address(0), "Intractopia: TokenId does not exist");
        _;
    }

    modifier onlyAdmin(uint256 _tokenId) {
        require(isAdmin[_tokenId][_msgSender()], "Intractopia: Only admin can call this function");
        _;
    }

    /* ============ Initial setup ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _trustedForwarder) ERC2771ContextUpgradeable(_trustedForwarder) {}

    function initialize(address _intractSigner, string calldata _uri) external initializer {
        require(_intractSigner != address(0), "Intractopia: Intract signer address must not be null address");
        __Ownable_init();
        __Pausable_init();
        __EIP712_init("Intractopia", "1.0.0");
        __ReentrancyGuard_init();
        __ERC1155_init(_uri);
        intractSigner = _intractSigner;
        emit ERC1155SignerUpdate(address(0), _intractSigner);
    }

    /* ============ External Functions ============ */

	function createCollection(
		uint256 _initialSupply
	) external virtual whenNotPaused nonReentrant returns (uint256) {
        _currentTokenId += 1;
        uint256 _id = _currentTokenId;
		creator[_id] = _msgSender();
        isAdmin[_id][_msgSender()] = true;
		_mint(_msgSender(), _id, _initialSupply, "");
		tokenSupply[_id] = _initialSupply;
        emit ERC1155CollectionLaunch(_id, _msgSender(), _initialSupply);
		return _id;
	}

    function claim(
        uint96 _rewardId,
        uint96 _userId,
        uint256 _tokenId,
        uint256 _amountToClaim,
        bytes calldata _signature
    ) external virtual whenNotPaused nonReentrant tokenExists(_tokenId) {
        require(_rewardId > 0, "Intractopia: Invalid rewardId");
        require(_userId > 0, "Intractopia: Invalid userId");
        require(_amountToClaim > 0, "ERC20QuestRewards: Invalid amount");

        require(!hasClaimed[_rewardId][_msgSender()], "Intractopia: You have already claimed this reward");
        require(!hasClaimedUserId[_rewardId][_userId], "Intractopia: This userId has already claimed this reward");
        
        require(_verify(
            _hashClaim(_rewardId, _userId, _msgSender(), _amountToClaim),
            _signature
        ), "Intractopia: Invalid signature");

        hasClaimed[_rewardId][_msgSender()] = true;
        hasClaimedUserId[_rewardId][_userId] = true;
        emit ERC1155Claim(_rewardId, _userId, _msgSender(), _tokenId, _amountToClaim);

        _mint(_msgSender(), _tokenId, _amountToClaim, "");
    }

    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _amount,
        bytes memory _data
    ) external virtual nonReentrant onlyAdmin(_tokenId) {
        super._mint(_to, _tokenId, _amount, _data);
        tokenSupply[_tokenId] += _amount;
    }

    function mintBatch(
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _amounts,
        bytes memory _data
    ) external virtual nonReentrant {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 id = _tokenIds[i];
            require(isAdmin[id][_msgSender()], "Intractopia: Only admin can call this function");
            tokenSupply[id] += _amounts[i];
        }
        super._mintBatch(_to, _tokenIds, _amounts, _data);
    }

    /* ============ Owner Functions ============ */

    function updateSigner(address _intractSigner) external onlyOwner {
        require(_intractSigner != address(0), "Intractopia: Invalid address");
        emit ERC1155SignerUpdate(intractSigner, _intractSigner);
        intractSigner = _intractSigner;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // TODO :: uri
    // function setURI(string memory newuri) public onlyOwner {
    //     _setURI(newuri);
    // }
    /*
    function _setURI(string memory newuri) internal virtual {
        _uri = newuri;
    }
    */

    /* ============ Fallback Functions ============ */

    receive() external payable {
        // anonymous transfer: to admin
        (bool success, ) = payable(owner()).call{value: msg.value}(
            new bytes(0)
        );
        require(success, "Intractopia: Transfer failed");
    }

    fallback() external payable {
        if (msg.value > 0) {
            // call non exist function: send to admin
            (bool success, ) = payable(owner()).call{value: msg.value}(new bytes(0));
            require(success, "Intractopia: Transfer failed");
        }
    }

    /* ============ Internal Functions ============ */

    /**
    * @dev generate hash which the Intract signer signs for minting tokens of one collection
    */
   function _hashClaim(
        uint96 _rewardId,
        uint96 _userId,
        address _userAddress,
        uint256 _amountToClaim
    ) internal view returns (bytes32) {
        return
        _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ERC1155_CLAIM_TYPEHASH,
                    _rewardId,
                    _userId,
                    _userAddress,
                    _amountToClaim
                )
            )
        );
    }

    function _hashDummyClaim(
        uint96 _rewardId,
        uint96 _userId,
        address _userAddress
    ) internal view returns (bytes32) {
        return
        _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ERC1155_DUMMY_CLAIM_TYPEHASH,
                    _rewardId,
                    _userId,
                    _userAddress
                )
            )
        );
    }

    function _msgSender()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _verify(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == intractSigner;
    }

}
