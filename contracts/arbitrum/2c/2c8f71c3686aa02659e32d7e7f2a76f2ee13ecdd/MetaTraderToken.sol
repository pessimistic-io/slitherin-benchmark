// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {ERC20Capped} from "./ERC20Capped.sol";
import {ERC20} from "./ERC20.sol";
import {AccessControlMixin} from "./AccessControlMixin.sol";
import {IChildToken} from "./IChildToken.sol";
import {NativeMetaTransaction} from "./NativeMetaTransaction.sol";
import {ContextMixin} from "./ContextMixin.sol";

contract MetaTraderToken is
    ERC20Capped,
    IChildToken,
    AccessControlMixin,
    NativeMetaTransaction,
    ContextMixin
{
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    struct GrantRequest {
        bytes32[] roles;
        uint256 initiated;
    }
    mapping(address => GrantRequest) grantRequests;
    uint256 public constant MIN_GRANT_REQUEST_DELAY = 45000; // 1 day

    event GrantRequestInitiated(
        bytes32[] indexed roles,
        address indexed account,
        uint256 indexed block
    );
    event GrantRequestCanceled(
        address indexed account,
        uint256 indexed canceled
    );

    constructor(
        address tradingStorage,
        address trading,
        address callbacks,
        address vault,
        address pool,
        address tokenMigration,
        address childManagerProxy
    )
        ERC20Capped(100 * (10**6) * (10**18))
        ERC20("My MetaTrader Token Utility", "uMMT")
    {
        // Token init
        _setupContractId("ChildMintableERC20");
        //_setupDecimals(18);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(DEPOSITOR_ROLE, childManagerProxy);
        _initializeEIP712("My MetaTrader Token");

        // Trading roles
        _setupRole(MINTER_ROLE, tradingStorage);
        _setupRole(BURNER_ROLE, tradingStorage);
        _setupRole(MINTER_ROLE, trading);
        _setupRole(MINTER_ROLE, callbacks);
        _setupRole(MINTER_ROLE, vault);
        _setupRole(MINTER_ROLE, pool);
        _setupRole(MINTER_ROLE, tokenMigration);
    }

    // This is to support Native meta transactions
    // never use msg.sender directly, use _msgSender() instead
    function _msgSender()
        internal
        view
        virtual
        override
        returns (address sender)
    {
        return ContextMixin.msgSender();
    }

    // Disable grantRole AccessControl function (can only be done after timelock)
    function grantRole(bytes32 role, address account)
        public
        override
        only(DEFAULT_ADMIN_ROLE)
    {
        super.grantRole(role, account);
    }

    // Returns true if a grant request was initiated for this account.
    function grantRequestInitiated(address account) public view returns (bool) {
        GrantRequest memory r = grantRequests[account];
        return r.roles.length > 0 && r.initiated > 0;
    }

    // Initiates a request to grant `role` to `account` at current block number.
    function initiateGrantRequest(bytes32[] calldata roles, address account)
        external
        only(DEFAULT_ADMIN_ROLE)
    {
        require(
            !grantRequestInitiated(account),
            "Grant request already initiated for this account."
        );
        grantRequests[account] = GrantRequest(roles, block.number);
        emit GrantRequestInitiated(roles, account, block.number);
    }

    // Cancels a request to grant `role` to `account`
    function cancelGrantRequest(address account)
        external
        only(DEFAULT_ADMIN_ROLE)
    {
        require(
            grantRequestInitiated(account),
            "You must first initiate a grant request for this role and account."
        );
        delete grantRequests[account];
        emit GrantRequestCanceled(account, block.number);
    }

    // Grant the roles precised in the request to account (must wait for the timelock)
    function executeGrantRequest(address account)
        public
        only(DEFAULT_ADMIN_ROLE)
    {
        require(
            grantRequestInitiated(account),
            "You must first initiate a grant request for this role and account."
        );

        GrantRequest memory r = grantRequests[account];
        require(
            block.number >= r.initiated + MIN_GRANT_REQUEST_DELAY,
            "You must wait for the minimum delay after initiating a request."
        );

        for (uint256 i = 0; i < r.roles.length; i++) {
            _setupRole(r.roles[i], account);
        }

        delete grantRequests[account];
    }

    // Mint tokens (called by our ecosystem contracts)
    function mint(address to, uint256 amount) external only(MINTER_ROLE) {
        _mint(to, amount);
    }

    // Burn tokens (called by our ecosystem contracts)
    function burn(address from, uint256 amount) external only(BURNER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required amount for user
     * Make sure minting is done only by this function
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded amount
     */
    function deposit(address user, bytes calldata depositData)
        external
        override
        only(DEPOSITOR_ROLE)
    {
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    /**
     * @notice called when user wants to withdraw tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external {
        _burn(_msgSender(), amount);
    }
}

