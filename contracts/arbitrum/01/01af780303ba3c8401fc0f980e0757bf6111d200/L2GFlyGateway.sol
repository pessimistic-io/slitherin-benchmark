// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import "./CrosschainMessenger.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./ICustomGateway.sol";
import "./IGFly.sol";


/**
 * @title Implementation of a gFLY gateway to be deployed on L2
 */
contract L2GFlyGateway is Initializable, AccessControlUpgradeable, IL2CustomGateway {

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    address internal constant ARB_SYS_ADDRESS = address(100);

    // Exit number (used for tradeable exits)
    uint256 public exitNum;

    // Token bridge state variables
    address public l1GFlyToken;
    address public l2GFlyToken;
    address public l1Gateway;
    address public router;

    // Custom functionality
    bool public allowsWithdrawals;


    /**
     * Emitted when calling sendTxToL1
     * @param from account that submits the L2-to-L1 message
     * @param to account recipient of the L2-to-L1 message
     * @param id id for the L2-to-L1 message
     * @param data data of the L2-to-L1 message
     */
    event TxToL1(
        address indexed from,
        address indexed to,
        uint256 indexed id,
        bytes data
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }


    /**
     * Contract constructor, sets the L2 router to be used in the contract's functions
     * @param router_ L2GatewayRouter address
     * @param dao DAO address
     */
    function initialize(address router_, address dao) external initializer {
        __AccessControl_init();

        _setupRole(ADMIN_ROLE, dao);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

        router = router_;
        allowsWithdrawals = false;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "GFly:ACCESS_DENIED");
        _;
    }

    modifier onlyCounterpartGateway(address l1Counterpart) {
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(l1Counterpart),
            "ONLY_COUNTERPART_GATEWAY"
        );

        _;
    }

    /**
     * Sets the information needed to use the gateway. To simplify the process of testing, this function can be called once
     * by the owner of the contract to set these addresses.
     * @param l1GFlyToken_ address of the gFLY token on L1
     * @param l2GFlyToken_ address of the gFLY token on L2
     * @param l1Gateway_ address of the counterpart gateway (on L1)
     */
    function setTokenBridgeInformation(
        address l1GFlyToken_,
        address l2GFlyToken_,
        address l1Gateway_
    ) public onlyAdmin {
        require(l1GFlyToken == address(0), "Token bridge information already set");
        l1GFlyToken = l1GFlyToken_;
        l2GFlyToken = l2GFlyToken_;
        l1Gateway = l1Gateway_;

        // Allows withdrawals after the information has been set
        allowsWithdrawals = true;
    }

    /// @dev See {ICustomGateway-outboundTransfer}
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        bytes calldata data
    ) public payable returns (bytes memory) {
        return outboundTransfer(l1Token, to, amount, 0, 0, data);
    }

    /// @dev See {ICustomGateway-outboundTransfer}
    function outboundTransfer(
        address l1Token,
        address to,
        uint256 amount,
        uint256, /* _maxGas */
        uint256, /* _gasPriceBid */
        bytes calldata data
    ) public payable override returns (bytes memory res) {
        // Only execute if deposits are allowed
        require(allowsWithdrawals == true, "Withdrawals are currently disabled");

        // The function is marked as payable to conform to the inheritance setup
        // This particular code path shouldn't have a msg.value > 0
        require(msg.value == 0, "NO_VALUE");

        // Only allow the custom token to be bridged through this gateway
        require(l1Token == l1GFlyToken, "Token is not allowed through this gateway");

        (address from, bytes memory extraData) = _parseOutboundData(data);

        // The inboundEscrowAndCall functionality has been disabled, so no data is allowed
        require(extraData.length == 0, "EXTRA_DATA_DISABLED");

        // Escrows L2 tokens before minting on L1
        IGFly(l2GFlyToken).transferFrom(from, address(this), amount);

        // Current exit number for this operation
        uint256 currExitNum = exitNum++;

        // We override the res field to save on the stack
        res = getOutboundCalldata(l1Token, from, to, amount, extraData);

        // Trigger the crosschain message
        uint256 id = _sendTxToL1(
            from,
            l1Gateway,
            res
        );

        emit WithdrawalInitiated(l1Token, from, to, id, currExitNum, amount);
        return abi.encode(id);
    }

    /// @dev See {ICustomGateway-finalizeInboundTransfer}
    function finalizeInboundTransfer(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) public payable override onlyCounterpartGateway(l1Gateway) {
        // Only allow the custom token to be bridged through this gateway
        require(l1Token == l1GFlyToken, "Token is not allowed through this gateway");

        // Abi decode may revert, but the encoding is done by L1 gateway, so we trust it
        (, bytes memory callHookData) = abi.decode(data, (bytes, bytes));
        if (callHookData.length != 0) {
            // callHookData should always be 0 since inboundEscrowAndCall is disabled
            callHookData = bytes("");
        }

        // Releases L2 tokens after burning on L1
        IGFly(l2GFlyToken).transfer(to, amount);

        emit DepositFinalized(l1Token, from, to, amount);
    }

    /// @dev See {ICustomGateway-getOutboundCalldata}
    function getOutboundCalldata(
        address l1Token,
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) public view override returns (bytes memory outboundCalldata) {
        outboundCalldata = abi.encodeWithSelector(
            ICustomGateway.finalizeInboundTransfer.selector,
            l1Token,
            from,
            to,
            amount,
            abi.encode(exitNum, data)
        );

        return outboundCalldata;
    }

    /// @dev See {ICustomGateway-calculateL2TokenAddress}
    function calculateL2TokenAddress(address l1Token) public view override returns (address) {
        if (l1Token == l1GFlyToken) {
            return l2GFlyToken;
        }

        return address(0);
    }

    /// @dev See {ICustomGateway-counterpartGateway}
    function counterpartGateway() public view override returns (address) {
        return l1Gateway;
    }

    /**
     * Parse data received in outboundTransfer
     * @param data encoded data received
     * @return from account that initiated the deposit,
     *         extraData decoded data
     */
    function _parseOutboundData(bytes memory data)
    internal
    view
    returns (
        address from,
        bytes memory extraData
    )
    {
        if (msg.sender == router) {
            // Router encoded
            (from, extraData) = abi.decode(data, (address, bytes));
        } else {
            from = msg.sender;
            extraData = data;
        }
    }

    // --------------------
    // Custom methods
    // --------------------
    /**
     * Disables the ability to deposit funds
     */
    function disableWithdrawals() external onlyAdmin {
        allowsWithdrawals = false;
    }

    /**
     * Enables the ability to deposit funds
     */
    function enableWithdrawals() external onlyAdmin {
        require(l1GFlyToken != address(0), "Token bridge information has not been set yet");
        allowsWithdrawals = true;
    }

    /**
     * Creates an L2-to-L1 message to send over to L1 through ArbSys
     * @param from account that is sending funds from L2
     * @param to account to be credited with the tokens in the destination layer
     * @param data encoded data for the L2-to-L1 message
     * @return id id for the L2-to-L1 message
     */
    function _sendTxToL1(
        address from,
        address to,
        bytes memory data
    ) internal returns (uint256) {
        uint256 id = ArbSys(ARB_SYS_ADDRESS).sendTxToL1(to, data);

        emit TxToL1(from, to, id, data);
        return id;
    }
}
