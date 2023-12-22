// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

/// @notice contract that allows a treasury contract to send ERC20 this address and allow users to claim it
/// @dev this contract is pausable, and only the owner can pause it

contract VaultkaClaimer is PausableUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct ClaimableInfo {
        address tokenAddress;
        uint256 totalRemainingAmount;
        uint256 id;
    }

    mapping(address => mapping(uint256 => bool)) public hasClaimable;
    mapping(address => bool) public isHandler;
    mapping(uint256 => ClaimableInfo) public claimableInfo;
    mapping(address => bool) public tokenEnabled;
    mapping(address => mapping(uint256 => uint256)) public claimableBalances;

    uint256 public campaignID;

    uint256[50] private __gaps;

    event Claimed(uint256 campaignID, address indexed token, address indexed user, uint256 amount);
    event HandlerSet(address handler, bool isActive);
    event TokenEnabled(address token, bool enabled);
    event ClaimableAmountsAdded(uint256 campaignID, address token, uint256 amount, uint256 timestamp);
    event ClaimableAmountsRemoved(uint256 campaignID, address token, uint256 amount, uint256 timestamp);
    event ClaimableAmountsEdited(uint256 campaignID, address token, uint256 amount, uint256 timestamp);

    ///@notice modifier to check if the caller is a handler
    modifier onlyHandler() {
        require(isHandler[msg.sender], "handler only");
        _;
    }

    ///@custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        isHandler[msg.sender] = true;

        __Pausable_init();
        __Ownable_init();
    }

    // -- Owner and Handler Functions -- //

    function pause() external onlyHandler {
        _pause();
    }

    function unpause() external onlyHandler {
        _unpause();
    }

    function setHandler(address _handler, bool _isActive) external onlyOwner {
        require(_handler != address(0), "Claimable: Invalid address");
        isHandler[_handler] = _isActive;

        emit HandlerSet(_handler, _isActive);
    }

    function whitelistToken(address _token, bool _enabled) external onlyOwner {
        require(_token != address(0), "Claimable: Invalid address");
        tokenEnabled[_token] = _enabled;

        emit TokenEnabled(_token, _enabled);
    }

    function addAirdropAmount(
        address _token,
        address[] memory _users,
        uint256[] memory _balances,
        uint256 _inputTotalAmount
    ) external onlyHandler {
        uint256 length = _users.length;
        require(_token != address(0), "Claimable: token address cannot be zero");
        require(length == _balances.length, "Claimable: user and balance array length mismatch");
        require(tokenEnabled[_token], "Claimable: token not enabled");

        uint256 _totalAmount;
        uint256 _campaignID = campaignID;

        for (uint256 i; i < length; i++) {
            require(_users[i] != address(0), "Claimable: Invalid address");
            address user = _users[i];
            uint256 balance = _balances[i];

            claimableBalances[user][_campaignID] += balance;
            hasClaimable[user][_campaignID] = true;
            _totalAmount += balance;
        }

        require(_inputTotalAmount == _totalAmount, "Claimable: input total amount mismatch");

        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);

        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        claimable.totalRemainingAmount += _totalAmount;
        claimable.id = _campaignID;
        claimable.tokenAddress = _token;

        campaignID++;
        
        emit ClaimableAmountsAdded(_campaignID,_token, _totalAmount, block.timestamp);
    }

    function editAirdropAmount(
        address[] memory _users,
        uint256[] memory _balances,
        uint256 _campaignID,
        bool _increase
    ) external onlyHandler {
        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        address _token = claimable.tokenAddress;
        require(tokenEnabled[_token], "Claimable: token not enabled");
        require(_token != address(0), "Campaign doesnt exist");
        uint256 length = _users.length;
        require(length == _balances.length, "Claimable: user and balance array length mismatch");

        uint256 _totalAmount;
        for (uint256 i; i < length; i++) {
            require(_users[i] != address(0), "Claimable: Invalid address");
            address user = _users[i];
            uint256 balance = _balances[i];
            uint256 oldBalance = claimableBalances[user][_campaignID];

            if (_increase) {
                claimableBalances[user][_campaignID] += balance;
                hasClaimable[user][_campaignID] = true;
                uint256 added = balance - oldBalance;
                _totalAmount += added;
            } else {
                require(oldBalance >= balance, "Claimable: balance exceeds claimable balance");
                uint256 removed = oldBalance - balance;
                _totalAmount += removed;
                claimableBalances[user][_campaignID] = balance;
            }
        }

        if (_increase) {
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);
            claimable.totalRemainingAmount += _totalAmount;
        } else {
            IERC20Upgradeable(_token).safeTransfer(msg.sender, _totalAmount);
            claimable.totalRemainingAmount -= _totalAmount;
        }

        emit ClaimableAmountsEdited(_campaignID, _token, _totalAmount, block.timestamp);
    }

    function removeAirdropAmount(
        address _token,
        address[] memory _users,
        uint256 _campaignID
    ) external onlyHandler {
        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        address _token = claimable.tokenAddress;
        require(_token != address(0), "Campaign doesnt exist");
        require(tokenEnabled[_token], "Claimable: token not enabled");
        uint256 length = _users.length;

        uint256 _totalAmount;
        for (uint256 i; i < length; i++) {
            require(_users[i] != address(0), "Claimable: Invalid address");
            address user = _users[i];

            _totalAmount += claimableBalances[user][_campaignID];
            claimableBalances[user][_campaignID] = 0;
        }

        IERC20Upgradeable(_token).safeTransfer(msg.sender, _totalAmount);
        claimable.totalRemainingAmount -= _totalAmount;

        emit ClaimableAmountsRemoved(_campaignID, _token, _totalAmount, block.timestamp);
    }

    // -- Public functions -- //

    function claim(uint256 _campaignID) public whenNotPaused {
        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        address _token = claimable.tokenAddress;
        require(tokenEnabled[_token], "Claimable: token not enabled");
        require(hasClaimable[msg.sender][_campaignID], "Claimable: user does not have claimable balance");
        require(claimableBalances[msg.sender][_campaignID] > 0, "Nothing to claim");

        uint256 amount = claimableBalances[msg.sender][_campaignID];

        claimableBalances[msg.sender][_campaignID] = 0;
        hasClaimable[msg.sender][_campaignID] = false;
        claimable.totalRemainingAmount -= amount;

        IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);

        emit Claimed(_campaignID, _token, msg.sender, amount);
    }
}

