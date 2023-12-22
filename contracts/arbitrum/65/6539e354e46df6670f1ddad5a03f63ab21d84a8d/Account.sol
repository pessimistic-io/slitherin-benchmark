// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./AccessControlRolesUpgradeable.sol";
import "./AccountRoles.sol";
import "./Signature.sol";
import "./IReferrals.sol";
import "./IFxToken.sol";

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

struct AccountData {
    bool isOpen;
    uint256 userCount;
    mapping(address => AccountUser) users;
}

struct AccountUser {
    mapping(AccountRole => bool) roles;
    /// How many roles the user has in this account.
    uint256 roleCount;
}

/**
 * @notice The Account contract is an NFT that represents a trading account.
 */
contract Account is
    Initializable,
    UUPSUpgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlRolesUpgradeable
{
    using SafeERC20 for IERC20;
    using Signature for bytes32;

    bytes32 public constant MESSAGE_SCOPE =
        keccak256("HANDLE_SYNTH_ACCOUNT_MESSAGE");

    /// @dev Counter for number of NFTs ever minted.
    uint256 public mintCounter;

    /// @dev The base NFT URI.
    string private baseURI;

    /// @dev Address of the Treasury contract which holds funds.
    address public treasury;

    /// @dev Map from account ID to account data.
    mapping(uint256 => AccountData) public accounts;

    /// @dev Mapping from user address to nonce for message signing.
    mapping(address => uint256) private userNonces;

    IReferrals public referrals;

    event BaseUriUpdated(string baseURI);

    event TreasuryUpdated(address treasury);

    event ReferralsUpdated(address referrals);

    event AccountOpened(address indexed recipient, uint256 id);

    event AccountClosed(uint256 indexed id);

    // AccountDeposit(indexed address,indexed address,indexed uint256,uint256)
    event AccountDeposit(
        address indexed depositor,
        address indexed liquidToken,
        uint256 indexed id,
        uint256 amount
    );

    event AccountUserRoleGranted(
        uint256 indexed id,
        address indexed user,
        AccountRole role
    );

    event AccountUserRoleRevoked(
        uint256 indexed id,
        address indexed user,
        AccountRole role
    );

    modifier onlyAccountRole(
        AccountRole authorisedRole,
        uint256 accountId,
        address accountUser,
        bytes calldata signature
    ) {
        consumeAccountRoleSignature(
            accountId,
            accountUser,
            authorisedRole,
            signature
        );
        _;
    }

    /// @dev Proxy initialisation function.
    function initialize(
        string calldata _baseURI,
        string calldata _symbol,
        string calldata _name
    ) public initializer {
        __ReentrancyGuard_init();
        __ERC721Enumerable_init();
        __ERC721_init_unchained(_name, _symbol);
        _setupRoles();
        setBaseURI(_baseURI);
    }

    function setBaseURI(string calldata _baseURI) public onlyAdmin {
        baseURI = _baseURI;
        emit BaseUriUpdated(_baseURI);
    }

    function setTreasury(address _treasury) public onlyAdmin {
        require(_treasury != address(0), "Account: invalid treasury");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setReferrals(address _referrals) public onlyAdmin {
        // Setting to zero address is allowed to disable referral updates.
        referrals = IReferrals(_referrals);
        bool isOperator = referrals.hasRole(OPERATOR_ROLE, address(this));
        require(isOperator, "Account: not operator of referrals");
        emit ReferralsUpdated(_referrals);
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

    function getAccountUser(uint256 id, address user)
        external
        view
        returns (uint256 roleCount)
    {
        AccountUser storage accountUser = accounts[id].users[user];
        roleCount = accountUser.roleCount;
    }

    function doesUserHaveAccountRole(
        uint256 id,
        address user,
        AccountRole role
    ) external view returns (bool) {
        return accounts[id].users[user].roles[role];
    }

    function userNonce(address user) external view returns (uint256) {
        return userNonces[user];
    }

    /**
     * @dev Validates an account role signature by reverting if invalid.
     * @param id The account ID.
     * @param accountUser The user address.
     * @param accountUserRole The account role that is being validated.
     * @param signature The user signature, with payload: `{id}{nonce}{role}`.
     */
    function validateAccountRoleSignature(
        uint256 id,
        address accountUser,
        AccountRole accountUserRole,
        bytes calldata signature
    ) public view {
        validateAccountRolePermission(id, accountUser, accountUserRole);
        bytes32 messageNon191 = keccak256(
            abi.encode(
                MESSAGE_SCOPE,
                userNonces[accountUser],
                id,
                uint8(accountUserRole)
            )
        );
        bytes32 message = messageNon191.getERC191Message();
        message.validateSignature(signature, accountUser);
        require(
            isAccountSignable(id, accountUserRole),
            "Account: valid but closed"
        );
    }

    /**
     * @dev Validates the permission of an account against an input role
     * @param id The account ID.
     * @param accountUser The user address.
     * @param accountUserRole The account role that is being validated.
     */
    function validateAccountRolePermission(
        uint256 id,
        address accountUser,
        AccountRole accountUserRole
    ) private view {
        require(accountUserRole != AccountRole.None, "Account: invalid role");
        AccountData storage account = accounts[id];
        require(isAccountSignable(id, accountUserRole), "Account: not open");
        AccountUser storage user = account.users[accountUser];
        // The user has authority over the role if:
        // - The role is Deposit.
        // - The role is Open, and the account ID is 0.
        // - The user has the same role as the argument role.
        // - The user has the Owner role, as it owns all other roles.
        // However, the owner needs to sign the role required for the
        // action they are doing, even though they only have the Owner role.
        // Otherwise, their signature check will fail in the
        // `validateRoleSignature` function.
        bool hasPermission = accountUserRole == AccountRole.Deposit ||
            (id == 0 && accountUserRole == AccountRole.Open) ||
            user.roles[accountUserRole] ||
            user.roles[AccountRole.Owner];
        require(hasPermission, "Account: insufficient permission");
    }

    function isAccountSignable(uint256 id, AccountRole accountUserRole)
        private
        view
        returns (bool)
    {
        // The account must be open for the signature to be valid.
        // However, the signature is valid for the account ID 0
        // if the role is Open, as a new account does not have
        // an ID yet.
        return
            accounts[id].isOpen ||
            (id == 0 && accountUserRole == AccountRole.Open);
    }

    /**
     * @dev Validates an account role signature and consumes it by increasing
     *      the account's nonce.
     * @param id The account ID.
     * @param accountUser The user address.
     * @param accountUserRole The account role that is being validated.
     * @param signature The user signature, with payload: `{id}{nonce}{role}`.
     */
    function consumeAccountRoleSignature(
        uint256 id,
        address accountUser,
        AccountRole accountUserRole,
        bytes calldata signature
    ) public {
        validateAccountRoleSignature(
            id,
            accountUser,
            accountUserRole,
            signature
        );
        // The signature is valid, so it is consumed by increasing the nonce.
        userNonces[accountUser] += 1;
    }

    /**
     * @dev Opens a new account by minting a new NFT and processing
     *      the initial deposit.
     * @param depositAmount The initial deposit amount.
     * @param recipient The address to be the holder of the new account.
     * @param liquidToken The liquid token this account will trade with.
     * @param openSignature The user's signature for opening the account.
     * @param referralCode An optional, UTF-8 referral code.
     * @param useAllowance Whether to deposit with ERC20 allowance or permit.
     */
    function open(
        uint256 depositAmount,
        address depositor,
        address recipient,
        IERC20 liquidToken,
        bytes calldata openSignature,
        bytes32 referralCode,
        bool useAllowance
    ) public onlyAccountRole(AccountRole.Open, 0, depositor, openSignature) {
        uint256 id = nextTokenId();
        _safeMint(recipient, id, "");
        emit AccountOpened(recipient, id);
        _deposit(id, depositAmount, depositor, liquidToken, useAllowance);
        updateAccountReferral(referralCode, id);
    }

    /**
     * @dev Opens a new account by minting a new NFT and processing
     *      the initial deposit.
     *      Reverts if the input ID does not match the newly created account ID.
     * @param depositAmount The initial deposit amount.
     * @param recipient The address to be the holder of the new account.
     * @param liquidToken The liquid token this account will trade with.
     * @param openSignature The user's signature for opening the account.
     * @param referralCode An optional, UTF-8 referral code.
     */
    function openWithId(
        uint256 id,
        uint256 depositAmount,
        address depositor,
        address recipient,
        IERC20 liquidToken,
        bytes calldata openSignature,
        bytes32 referralCode,
        bool useAllowance
    ) external {
        uint256 actualId = nextTokenId();
        require(id == actualId, "Account: id mismatch");
        open(
            depositAmount,
            depositor,
            recipient,
            liquidToken,
            openSignature,
            referralCode,
            useAllowance
        );
    }

    /**
     * @dev Deposit into an existing account.
     *      Approvals should only be made in the amount of the wanted deposit.
     * @param id The account ID.
     */
    function deposit(
        uint256 id,
        uint256 amount,
        address depositor,
        IERC20 liquidToken,
        bool useAllowance,
        bytes calldata depositorSignature
    )
        public
        nonReentrant
        onlyAccountRole(AccountRole.Deposit, id, depositor, depositorSignature)
    {
        _deposit(id, amount, depositor, liquidToken, useAllowance);
    }

    function _deposit(
        uint256 id,
        uint256 amount,
        address depositor,
        IERC20 liquidToken,
        bool useAllowance
    ) private {
        require(treasury != address(0), "Account: not initialised");
        require(amount > 0, "Account: no deposit");
        require(accounts[id].isOpen, "Account: not open");
        require(depositor != address(this), "Account: invalid depositor");
        if (useAllowance) {
            liquidToken.safeTransferFrom(depositor, treasury, amount);
        } else {
            require(
                liquidToken.balanceOf(depositor) >= amount,
                "Account: balance too low"
            );
            IFxToken(address(liquidToken)).burn(depositor, amount);
            IFxToken(address(liquidToken)).mint(treasury, amount);
        }
        emit AccountDeposit(depositor, address(liquidToken), id, amount);
    }

    function grantAccountUserRole(
        uint256 id,
        address user,
        AccountRole role,
        address owner,
        bytes calldata ownerSignature
    ) external {
        validateAccountRoleManagement(id, user, role, owner, ownerSignature);
        require(
            !accounts[id].users[user].roles[role],
            "Account: user already has role"
        );
        grantAccountUserRoleUnchecked(id, user, role);
    }

    function revokeAccountUserRole(
        uint256 id,
        address user,
        AccountRole role,
        address owner,
        bytes calldata ownerSignature
    ) external {
        validateAccountRoleManagement(id, user, role, owner, ownerSignature);
        require(
            accounts[id].users[user].roles[role],
            "Account: user does not have role"
        );
        revokeAccountUserRoleUnchecked(id, user, role);
    }

    function validateAccountRoleManagement(
        uint256 id,
        address user,
        AccountRole role,
        address owner,
        bytes calldata ownerSignature
    ) private onlyAccountRole(AccountRole.Owner, id, owner, ownerSignature) {
        require(accounts[id].isOpen, "Account: not open");
        require(role != AccountRole.None, "Account: cannot use None role");
        require(role != AccountRole.Owner, "Account: cannot use Owner role");
        require(owner != user, "Account: cannot self manage");
        require(user != address(0), "Account: invalid user address");
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

    function nextTokenId() private view returns (uint256) {
        // Valid NFT IDs start from 1.
        return mintCounter + 1;
    }

    /**
     * @dev Grants an account user's role, without checking for permissions.
     * @param id The account id.
     * @param user The user address for which to grant the role.
     * @param role The role being granted.
     */
    function grantAccountUserRoleUnchecked(
        uint256 id,
        address user,
        AccountRole role
    ) private {
        AccountData storage account = accounts[id];
        assert(account.isOpen);
        AccountUser storage accountUser = account.users[user];
        if (accountUser.roles[role]) {
            return;
        }
        accountUser.roles[role] = true;
        updateAccountUserAndRoleCountForRoleGranted(account, accountUser);
        emit AccountUserRoleGranted(id, user, role);
    }

    /**
     * @dev Revokes an account user's role, without checking for permissions.
     * @param id The account id.
     * @param user The user address for which to revoke the role.
     * @param role The role being revoked.
     */
    function revokeAccountUserRoleUnchecked(
        uint256 id,
        address user,
        AccountRole role
    ) private {
        AccountData storage account = accounts[id];
        assert(account.isOpen);
        AccountUser storage accountUser = account.users[user];
        if (!accountUser.roles[role]) {
            return;
        }
        accountUser.roles[role] = false;
        updateAccountUserAndRoleCountForRoleRevoked(account, accountUser);
        emit AccountUserRoleRevoked(id, user, role);
    }

    function updateAccountUserAndRoleCountForRoleGranted(
        AccountData storage account,
        AccountUser storage accountUser
    ) private {
        uint256 newUserRoleCount = accountUser.roleCount + 1;
        bool hasUserJoinedTheAccount = newUserRoleCount == 1;
        if (hasUserJoinedTheAccount) {
            account.userCount += 1;
        }
        accountUser.roleCount = newUserRoleCount;
    }

    function updateAccountUserAndRoleCountForRoleRevoked(
        AccountData storage account,
        AccountUser storage accountUser
    ) private {
        uint256 newUserRoleCount = accountUser.roleCount - 1;
        bool hasUserLeftTheAccount = newUserRoleCount == 0;
        if (hasUserLeftTheAccount) {
            account.userCount -= 1;
        }
        accountUser.roleCount = newUserRoleCount;
    }

    function initialiseAccountInStorage(uint256 id, address owner) private {
        assert(!accounts[id].isOpen);
        accounts[id].isOpen = true;
        grantAccountUserRoleUnchecked(id, owner, AccountRole.Owner);
    }

    function closeAccountInStorage(uint256 id) private {
        assert(accounts[id].isOpen);
        // The storage remains as it was, except the account is now closed.
        accounts[id].isOpen = false;
        emit AccountClosed(id);
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
            // Ownership is granted in _safeMint.
            return;
        }
        if (to == address(0)) {
            // Token is being burned.
            // Ownership is revoked.
            closeAccountInStorage(firstTokenId);
            return;
        }
        if (from == to) {
            // User is transferring the token to themselves.
            return;
        }
        // Token ownership is being transferred.
        // For security reasons, before a token ownership can be transferred,
        // all users must be removed from the account by the owner.
        AccountData storage account = accounts[firstTokenId];
        require(
            account.userCount == 1,
            "Account: must remove users before transfer"
        );
        // Ownership is transferred.
        revokeAccountUserRoleUnchecked(firstTokenId, from, AccountRole.Owner);
        grantAccountUserRoleUnchecked(firstTokenId, to, AccountRole.Owner);
    }

    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal override {
        super._safeMint(to, tokenId, data);
        initialiseAccountInStorage(tokenId, to);
        mintCounter += 1;
    }

    function updateAccountReferral(bytes32 referralCode, uint256 accountId)
        private
    {
        if (address(referrals) == address(0)) {
            return;
        }
        referrals.setReferralForTradeAccount(referralCode, accountId);
    }

    /// @dev Protected UUPS upgrade authorization function.
    function _authorizeUpgrade(address) internal override onlyOwner {}
}

