// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IERC20.sol";
import "./Math.sol";
import "./IBilling.sol";
import "./Governed.sol";

/**
 * @title Billing Contract
 * @dev The billing contract allows for Graph Tokens to be added by a user. The token can then
 * be pulled by a permissioned user named 'gateway'. It is owned and controlled by the 'governor'.
 */

contract Billing is IBilling, Governed {
    // -- State --

    // The contract for interacting with The Graph Token
    IERC20 private immutable graphToken;
    // The gateway address
    address public gateway;

    // maps user address --> user billing balance
    mapping(address => uint256) public userBalances;

    // -- Events --

    /**
     * @dev User adds tokens
     */
    event TokensAdded(address indexed user, uint256 amount);
    /**
     * @dev User removes tokens
     */
    event TokensRemoved(address indexed user, address indexed to, uint256 amount);

    /**
     * @dev Gateway pulled tokens from a user
     */
    event TokensPulled(address indexed user, uint256 amount);

    /**
     * @dev Gateway address updated
     */
    event GatewayUpdated(address indexed newGateway);

    /**
     * @dev Tokens rescued by the gateway
     */
    event TokensRescued(address indexed to, address indexed token, uint256 amount);

    /**
     * @dev Constructor function
     * @param _gateway   Gateway address
     * @param _token     Graph Token address
     * @param _governor  Governor address
     */
    constructor(
        address _gateway,
        IERC20 _token,
        address _governor
    ) Governed(_governor) {
        _setGateway(_gateway);
        graphToken = _token;
    }

    /**
     * @dev Check if the caller is the gateway.
     */
    modifier onlyGateway() {
        require(msg.sender == gateway, "Caller must be gateway");
        _;
    }

    /**
     * @dev Set the new gateway address
     * @param _newGateway  New gateway address
     */
    function setGateway(address _newGateway) external override onlyGovernor {
        _setGateway(_newGateway);
    }

    /**
     * @dev Set the new gateway address
     * @param _newGateway  New gateway address
     */
    function _setGateway(address _newGateway) internal {
        require(_newGateway != address(0), "Gateway cannot be 0");
        gateway = _newGateway;
        emit GatewayUpdated(gateway);
    }

    /**
     * @dev Add tokens into the billing contract
     * Ensure graphToken.approve() is called on the billing contract first
     * @param _amount  Amount of tokens to add
     */
    function add(uint256 _amount) external override {
        _add(msg.sender, msg.sender, _amount);
    }

    /**
     * @dev Add tokens into the billing contract for any user
     * Ensure graphToken.approve() is called on the billing contract first
     * @param _to  Address that tokens are being added to
     * @param _amount  Amount of tokens to add
     */
    function addTo(address _to, uint256 _amount) external override {
        _add(msg.sender, _to, _amount);
    }

    /**
     * @dev Add tokens into the billing contract in bulk
     * Ensure graphToken.approve() is called on the billing contract first
     * @param _to  Array of addresses where to add tokens
     * @param _amount  Array of amount of tokens to add to each account
     */
    function addToMany(address[] calldata _to, uint256[] calldata _amount) external override {
        require(_to.length == _amount.length, "Lengths not equal");

        // Get total amount to add
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amount.length; i++) {
            require(_amount[i] > 0, "Must add more than 0");
            totalAmount += _amount[i];
        }
        require(graphToken.transferFrom(msg.sender, address(this), totalAmount), "Add transfer failed");

        // Add each amount
        for (uint256 i = 0; i < _to.length; i++) {
            address user = _to[i];
            require(user != address(0), "user != 0");
            userBalances[user] += _amount[i];
            emit TokensAdded(user, _amount[i]);
        }
    }

    /**
     * @dev Add tokens into the billing contract
     * Ensure graphToken.approve() is called on the billing contract first
     * @param _from  Address that is sending tokens
     * @param _user  User that is adding tokens
     * @param _amount  Amount of tokens to add
     */
    function _add(
        address _from,
        address _user,
        uint256 _amount
    ) private {
        require(_amount != 0, "Must add more than 0");
        require(_user != address(0), "user != 0");
        require(graphToken.transferFrom(_from, address(this), _amount), "Add transfer failed");
        userBalances[_user] = userBalances[_user] + _amount;
        emit TokensAdded(_user, _amount);
    }

    /**
     * @dev Remove tokens from the billing contract
     * @param _user  Address that tokens are being removed from
     * @param _amount  Amount of tokens to remove
     */
    function remove(address _user, uint256 _amount) external override {
        require(_amount != 0, "Must remove more than 0");
        require(userBalances[msg.sender] >= _amount, "Too much removed");
        userBalances[msg.sender] = userBalances[msg.sender] - _amount;
        require(graphToken.transfer(_user, _amount), "Remove transfer failed");
        emit TokensRemoved(msg.sender, _user, _amount);
    }

    /**
     * @dev Gateway pulls tokens from the billing contract
     * @param _user  Address that tokens are being pulled from
     * @param _amount  Amount of tokens to pull
     * @param _to Destination to send pulled tokens
     */
    function pull(
        address _user,
        uint256 _amount,
        address _to
    ) external override onlyGateway {
        uint256 maxAmount = _pull(_user, _amount);
        _sendTokens(_to, maxAmount);
    }

    /**
     * @dev Gateway pulls tokens from many users in the billing contract
     * @param _users  Addresses that tokens are being pulled from
     * @param _amounts  Amounts of tokens to pull from each user
     * @param _to Destination to send pulled tokens
     */
    function pullMany(
        address[] calldata _users,
        uint256[] calldata _amounts,
        address _to
    ) external override onlyGateway {
        require(_users.length == _amounts.length, "Lengths not equal");
        uint256 totalPulled;
        for (uint256 i = 0; i < _users.length; i++) {
            uint256 userMax = _pull(_users[i], _amounts[i]);
            totalPulled = totalPulled + userMax;
        }
        _sendTokens(_to, totalPulled);
    }

    /**
     * @dev Gateway pulls tokens from the billing contract. Uses Math.min() so that it won't fail
     * in the event that a user removes in front of the gateway pulling
     * @param _user  Address that tokens are being pulled from
     * @param _amount  Amount of tokens to pull
     */
    function _pull(address _user, uint256 _amount) internal returns (uint256) {
        uint256 maxAmount = Math.min(_amount, userBalances[_user]);
        if (maxAmount > 0) {
            userBalances[_user] = userBalances[_user] - maxAmount;
            emit TokensPulled(_user, maxAmount);
        }
        return maxAmount;
    }

    /**
     * @dev Allows the Gateway to rescue any ERC20 tokens sent to this contract by accident
     * @param _to  Destination address to send the tokens
     * @param _token  Token address of the token that was accidentally sent to the contract
     * @param _amount  Amount of tokens to pull
     */
    function rescueTokens(
        address _to,
        address _token,
        uint256 _amount
    ) external onlyGateway {
        require(_to != address(0), "Cannot send to address(0)");
        require(_amount != 0, "Cannot rescue 0 tokens");
        IERC20 token = IERC20(_token);
        require(token.transfer(_to, _amount), "Rescue tokens failed");
        emit TokensRescued(_to, _token, _amount);
    }

    /**
     * @dev Send tokens to a destination account
     * @param _to Address where to send tokens
     * @param _amount Amount of tokens to send
     */
    function _sendTokens(address _to, uint256 _amount) internal {
        if (_amount > 0) {
            require(_to != address(0), "Cannot transfer to empty address");
            require(graphToken.transfer(_to, _amount), "Token transfer failed");
        }
    }
}

