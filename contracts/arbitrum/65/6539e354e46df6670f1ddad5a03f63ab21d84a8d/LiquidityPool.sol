// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./AccessControlRolesUpgradeable.sol";
import "./Signature.sol";
import "./LiquidityToken.sol";
import "./ILiquidityTokenFactory.sol";
import "./LiquidityPoolRoles.sol";

/*                                                *\
 *                ,.-"""-.,                       *
 *               /   ===   \                      *
 *              /  =======  \                     *
 *           __|  (o)   (0)  |__                  *
 *          / _|    .---.    |_ \                 *
 *         | /.----/ O O \----.\ |                *
 *          \/     |     |     \/                 *
 *          |                   |                 *
 *          |                   |                 *
 *          |                   |                 *
 *          _\   -.,_____,.-   /_                 *
 *      ,.-"  "-.,_________,.-"  "-.,             *
 *     /          |       |  ╭-╮     \            *
 *    |           l.     .l  ┃ ┃      |           *
 *    |            |     |   ┃ ╰━━╮   |           *
 *    l.           |     |   ┃ ╭╮ ┃  .l           *
 *     |           l.   .l   ┃ ┃┃ ┃  | \,         *
 *     l.           |   |    ╰-╯╰-╯ .l   \,       *
 *      |           |   |           |      \,     *
 *      l.          |   |          .l        |    *
 *       |          |   |          |         |    *
 *       |          |---|          |         |    *
 *       |          |   |          |         |    *
 *       /"-.,__,.-"\   /"-.,__,.-"\"-.,_,.-"\    *
 *      |            \ /            |         |   *
 *      |             |             |         |   *
 *       \__|__|__|__/ \__|__|__|__/ \_|__|__/    *
\*                                                 */

struct PoolData {
    bool isOpen;
    address underlyingToken;
    address liquidityToken;
    address owner;
}

/**
 * @notice The LiquidityPool contract handles liquidity pool creation and configuration through NFTs.
 */
contract LiquidityPool is
    Initializable,
    UUPSUpgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlRolesUpgradeable
{
    using SafeERC20 for IERC20;
    using Signature for bytes32;

    uint256 private constant PRICE_DECIMALS = 8;

    uint256 public constant PRICE_UNIT = 10**PRICE_DECIMALS;

    bytes32 public constant MESSAGE_SCOPE =
        keccak256("HANDLE_SYNTH_LP_MESSAGE");

    /// @dev The base NFT URI.
    string private baseURI;

    /// @dev Address of the Treasury contract which holds funds.
    address public treasury;

    /// @dev Reference to the liquidity token deployment factory.
    ILiquidityTokenFactory public factory;

    /// @dev Map from pool ID to pool data.
    ///      The pool ID is the uint256 value of the pools' token address.
    mapping(uint256 => PoolData) private pools;

    /// @dev Mapping from account address to user nonce for message signing.
    mapping(address => uint256) private userNonces;

    event FactoryUpdated(address factory);

    event BaseUriUpdated(string baseURI);

    event TreasuryUpdated(address treasury);

    event PoolOpened(
        address indexed poolOwner,
        address indexed underlyingToken,
        uint256 poolId
    );

    event PoolClosed(uint256 indexed poolId);

    event LiquidityAdded(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount,
        uint256 liquidityTokenPrice
    );

    event LiquidityRemoved(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount,
        uint256 liquidityTokenPrice
    );

    event PoolOwnershipTransferred(
        uint256 indexed poolId,
        address from,
        address to
    );

    event SetPoolParam(
        uint256 indexed poolId,
        string paramId,
        bytes32 paramValue
    );

    modifier onlyPoolRole(
        uint256 poolId,
        address poolUser,
        LiquidityPoolRole role,
        bytes memory payload,
        bytes calldata signature
    ) {
        consumePoolRoleSignature(poolId, poolUser, role, payload, signature);
        _;
    }

    modifier onlyPoolOwner(
        uint256 poolId,
        address poolUser,
        bytes memory payload,
        bytes calldata signature
    ) {
        consumePoolRoleSignature(
            poolId,
            poolUser,
            LiquidityPoolRole.Owner,
            payload,
            signature
        );
        _;
    }

    /// @dev Proxy initialisation function.
    function initialize(string calldata _baseURI, address _factory)
        public
        initializer
    {
        __ReentrancyGuard_init();
        __ERC721Enumerable_init();
        _setupRoles();
        setBaseURI(_baseURI);
        setFactory(_factory);
    }

    function setBaseURI(string calldata _baseURI) public onlyAdmin {
        baseURI = _baseURI;
        emit BaseUriUpdated(_baseURI);
    }

    function setTreasury(address _treasury) public onlyAdmin {
        require(_treasury != address(0), "Pool: invalid treasury");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setFactory(address _factory) public onlyAdmin {
        require(_factory != address(0), "Pool: invalid factory");
        factory = ILiquidityTokenFactory(_factory);
        emit FactoryUpdated(_factory);
    }

    function getBaseURI() external view returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Nonexistent token");
        return string(abi.encodePacked(baseURI, "/", tokenId, ".json"));
    }

    function getPoolData(uint256 poolId)
        external
        view
        returns (PoolData memory)
    {
        return pools[poolId];
    }

    function userNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }

    /**
     * @dev Validates a pool ownership signature by reverting if invalid.
     * @param id The pool ID.
     * @param poolUser The user address.
     * @param signature The user signature, with payload: `{id}{nonce}{role}`.
     */
    function validatePoolRoleSignature(
        uint256 id,
        address poolUser,
        LiquidityPoolRole role,
        bytes memory payload,
        bytes calldata signature
    ) public view {
        PoolData storage pool = pools[id];
        // Validate that it is a valid owner signing the owner role.
        // The Deposit role is not checked as it is an open role,
        // i.e. anyone can deposit into any pool.
        if (role == LiquidityPoolRole.Owner) {
            require(
                pool.owner == poolUser,
                "LiquidityPool: insufficient permission"
            );
        }
        bytes32 messageNon191 = keccak256(
            abi.encode(
                MESSAGE_SCOPE,
                userNonces[poolUser],
                id,
                uint8(role),
                payload
            )
        );
        bytes32 message = messageNon191.getERC191Message();
        message.validateSignature(signature, poolUser);
        require(pools[id].isOpen, "LiquidityPool: valid but closed");
    }

    /**
     * @dev Validates a pool ownership signature and consumes it by increasing
     *      the user's nonce.
     * @param id The pool ID.
     * @param poolUser The user address.
     * @param signature The user signature, with payload: `{id}{nonce}{role}`.
     */
    function consumePoolRoleSignature(
        uint256 id,
        address poolUser,
        LiquidityPoolRole role,
        bytes memory payload,
        bytes calldata signature
    ) public {
        validatePoolRoleSignature(id, poolUser, role, payload, signature);
        // The signature is valid, so it is consumed by increasing the nonce.
        userNonces[poolUser] += 1;
    }

    /**
     * @dev Opens a new pool by minting a new NFT and deploying an LP ERC20.
     */
    function open(
        IERC20 underlyingToken,
        address poolOwner,
        string calldata liquidityTokenName,
        string calldata liquidityTokenSymbol,
        bytes32 liquidityTokenSalt
    ) public onlyOperator {
        address precomputedTokenAddress = factory.computeAddress(
            liquidityTokenName,
            liquidityTokenSymbol,
            liquidityTokenSalt
        );
        uint256 id = uint256(uint160(precomputedTokenAddress));
        _safeMint(poolOwner, id, "");
        address liquidityToken = factory.deploy(
            liquidityTokenName,
            liquidityTokenSymbol,
            liquidityTokenSalt,
            precomputedTokenAddress
        );
        initialisePoolInStorage(
            id,
            poolOwner,
            address(underlyingToken),
            liquidityToken
        );
        emit PoolOpened(poolOwner, address(underlyingToken), id);
    }

    /**
     * @dev Updates a pool param.
     */
    function setParam(
        uint256 poolId,
        string calldata paramId,
        bytes32 paramValue,
        address poolUser,
        bytes calldata signature
    )
        external
        onlyOperator
        onlyPoolOwner(
            poolId,
            poolUser,
            abi.encodePacked(paramId, paramValue),
            signature
        )
    {
        emit SetPoolParam(poolId, paramId, paramValue);
    }

    /**
     * @dev Deposit into an existing pool.
     * @param poolId The pool ID.
     */
    function deposit(
        uint256 poolId,
        uint256 underlyingTokenAmount,
        uint256 liquidityTokenPrice,
        address depositor,
        address recipient,
        bytes calldata depositorSignature
    ) external nonReentrant onlyOperator {
        require(treasury != address(0), "Pool: not initialised");
        require(underlyingTokenAmount > 0, "Pool: no deposit");
        PoolData storage pool = pools[poolId];
        require(pool.isOpen, "Pool: not open");
        collectDeposit(
            depositor,
            underlyingTokenAmount,
            IERC20(pool.underlyingToken),
            poolId,
            depositorSignature
        );
        uint256 purchasedAmount = (underlyingTokenAmount * PRICE_UNIT) /
            liquidityTokenPrice;
        mintLiquidityToken(recipient, purchasedAmount, poolId);
        emit LiquidityAdded(
            poolId,
            depositor,
            underlyingTokenAmount,
            liquidityTokenPrice
        );
    }

    function collectDeposit(
        address from,
        uint256 amount,
        IERC20 token,
        uint256 poolId,
        bytes calldata depositorSignature
    )
        private
        onlyPoolRole(
            poolId,
            from,
            LiquidityPoolRole.Deposit,
            abi.encodePacked(address(token), amount),
            depositorSignature
        )
    {
        token.safeTransferFrom(from, treasury, amount);
    }

    function mintLiquidityToken(
        address to,
        uint256 amount,
        uint256 poolId
    ) private {
        LiquidityToken token = LiquidityToken(address(uint160(poolId)));
        token.mint(to, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return (interfaceId == type(IERC721EnumerableUpgradeable).interfaceId ||
            interfaceId == type(IAccessControlUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId));
    }

    function initialisePoolInStorage(
        uint256 poolId,
        address poolOwner,
        address underlyingToken,
        address liquidityToken
    ) private {
        PoolData storage pool = pools[poolId];
        assert(!pool.isOpen);
        pool.isOpen = true;
        pool.owner = poolOwner;
        pool.underlyingToken = underlyingToken;
        pool.liquidityToken = liquidityToken;
    }

    function closePoolInStorage(uint256 id) private {
        assert(pools[id].isOpen);
        // The storage remains as it was, except the pool is now closed.
        pools[id].isOpen = false;
        emit PoolClosed(id);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override {
        assert(batchSize == 1);
        if (from == address(0)) {
            // Token is being minted.
            // Ownership is granted in initialisePoolInStorage.
            return;
        }
        if (to == address(0)) {
            // Token is being burned.
            // Ownership is revoked.
            closePoolInStorage(firstTokenId);
            return;
        }
        if (from == to) {
            // User is transferring the token to themselves.
            return;
        }
        // Ownership is transferred.
        PoolData storage pool = pools[firstTokenId];
        pool.owner = to;
        emit PoolOwnershipTransferred(firstTokenId, from, to);
    }

    /// @dev Protected UUPS upgrade authorization function.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

