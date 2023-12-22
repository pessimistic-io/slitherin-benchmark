// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.7;

import "./IRebates.sol";
import "./IRebateHandler.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";

/**
 * @title Rebates
 * @notice This contract is responsible for calculating and
 * distributing rebates
 */
contract Rebates is Ownable, IRebates {
    using SafeERC20 for IERC20;

    /// @dev the address to be used if there is no rebate handler for an action
    address public constant NO_HANDLER = address(0);

    event SetCanRebate(address indexed rebater, bool canRebate);
    event SetRebateHandler(bytes32 indexed action, address indexed handler);
    event Rebate(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );
    event ClaimRebate(
        address indexed token,
        address indexed user,
        address indexed receiver,
        uint256 amount
    );

    /// @dev mapping of whether an address can initiate rebates
    mapping(address => bool) public canInitiateRebate;

    /// @dev mapping of actions to the handler address
    mapping(bytes32 => address) public rebateHandler;

    /// @dev mapping of users to a token to the token's rebate amount for the user
    mapping(address => mapping(address => uint256)) public userTokenRebates;

    /// @dev throws if called by an address that cannot rebate
    modifier onlyRebater() {
        require(canInitiateRebate[msg.sender], "Rebates: Unauthorized caller");
        _;
    }

    /**
     * @dev throws if the caller is not the handler for {action}
     * @param action the action to check
     */
    modifier onlyRebateHandler(bytes32 action) {
        require(
            msg.sender == rebateHandler[action],
            "Rebates: Unauthorized caller"
        );
        _;
    }

    /// @dev see {IRebates-setCanInitiateRebate}
    function setCanInitiateRebate(address rebater, bool _canRebate)
        external
        override
        onlyOwner
    {
        require(
            canInitiateRebate[rebater] != _canRebate,
            "Rebates: State already set"
        );
        canInitiateRebate[rebater] = _canRebate;
        emit SetCanRebate(rebater, _canRebate);
    }

    /// @dev see {IRebates-setRebateHandler}
    function setRebateHandler(bytes32 action, address handler)
        external
        override
        onlyOwner
    {
        require(rebateHandler[action] != handler, "Rebates: State already set");
        rebateHandler[action] = handler;
        emit SetRebateHandler(action, handler);
    }

    /// @dev see {IRebates-initiateRebate}
    function initiateRebate(bytes32 action, bytes calldata params)
        external
        override
        onlyRebater
    {
        address handler = rebateHandler[action];

        // do nothing if there is no rebate handler for this action
        if (handler == NO_HANDLER) return;

        IRebateHandler(handler).executeRebates(action, params);
    }

    /// @dev see {IRebates-registerRebate}
    function registerRebate(
        address rebateReceiver,
        address token,
        uint256 amount,
        bytes32 action
    ) external override onlyRebateHandler(action) {
        require(amount > 0, "Rebates: Amount cannot be zero");

        userTokenRebates[rebateReceiver][token] += amount;
        emit Rebate(rebateReceiver, token, amount);
    }

    /// @dev see {IRebates-claim}
    function claim(address token) external override {
        claimFor(token, msg.sender);
    }

    /// @dev see {IRebates-claimFor}
    function claimFor(address token, address receiver) public override {
        uint256 amountOut = userTokenRebates[msg.sender][token];
        require(amountOut > 0, "Rebates: cannot claim zero");

        userTokenRebates[msg.sender][token] = 0;

        IERC20(token).safeTransfer(receiver, amountOut);
        emit ClaimRebate(token, msg.sender, receiver, amountOut);
    }

    /**
     * @dev withdraws {amount} of {token} to the owner
     * @param token the token to withdraw
     * @param amount the amount of {token} to withdraw
     */
    function ownerWithdraw(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Rebates: cannot withdraw zero");
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}

