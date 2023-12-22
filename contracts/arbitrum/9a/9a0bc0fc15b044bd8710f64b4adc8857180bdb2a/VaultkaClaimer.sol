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
        bool ended;
    }

    mapping(address => mapping(uint256 => bool)) public hasClaimable;
    mapping(address => bool) public isHandler;
    mapping(uint256 => ClaimableInfo) public claimableInfo;
    mapping(address => bool) public tokenEnabled;
    mapping(address => mapping(uint256 => uint256)) public claimableBalances;
    mapping(uint256 => address[]) public usersCampaign;

    uint256 public campaignID;

    uint256[50] private __gaps;

    event Claimed(uint256 campaignID, address indexed token, address indexed user, uint256 amount);
    event HandlerSet(address handler, bool isActive);
    event TokenEnabled(address token, bool enabled);
    event ClaimableAmountsAdded(uint256 campaignID, address token, uint256 amount, uint256 timestamp);
    event UsersRemoved(uint256 campaignID, address token, uint256 amount, uint256 timestamp);
    event ClaimableAmountsChanged(uint256 campaignID, address token, uint256 amount, uint256 timestamp);
    event CampaignStopped(uint256 campaignID, address token, uint256 amount, uint256 timestamp);
    event UsersAddedToCampaign(uint256 campaignID, address token, uint256 amount, uint256 timestamp,address[] users);

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

    function createCampaign(
        address _token,
        address[] memory _users,
        uint256[] memory _balances
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

        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);

        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        claimable.totalRemainingAmount += _totalAmount;
        claimable.id = _campaignID;
        claimable.tokenAddress = _token;

        address[] memory usersC = new address[](length);
        usersC = _users;
        usersCampaign[_campaignID] = usersC;

        campaignID++;
        
        emit ClaimableAmountsAdded(_campaignID,_token, _totalAmount, block.timestamp);
    }

    function stopCampaign(uint256 _campaignID) external onlyHandler {
        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        address _token = claimable.tokenAddress;
        require(_token != address(0), "Campaign doesnt exist");
        require(claimable.ended == false, "Campaign has ended");

        uint256 allUsers = usersCampaign[_campaignID].length;
        for (uint256 i; i < allUsers; i++) {
            address user = usersCampaign[_campaignID][i];
            hasClaimable[user][_campaignID] = false;
            claimableBalances[user][_campaignID] = 0;
        }

        uint256 _totalAmount = claimable.totalRemainingAmount;
        claimable.totalRemainingAmount = 0;
        claimable.ended = true;
        delete usersCampaign[_campaignID];

        IERC20Upgradeable(_token).safeTransfer(msg.sender, _totalAmount);

        emit CampaignStopped(_campaignID, _token, _totalAmount, block.timestamp);
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
        require(claimable.ended == false, "Campaign has ended");

        uint256 _totalAmount;
        for (uint256 i; i < length; i++) {
            address user = _users[i];
            require(_users[i] != address(0) && hasClaimable[user][_campaignID], "Claimable: Invalid user");
            uint256 balance = _balances[i];

            if (_increase) {
                claimableBalances[user][_campaignID] += balance;
                _totalAmount += balance;
            } else {
                require(balance < claimableBalances[user][_campaignID], "Claimable: removeable balance exceeds user balance, use removeUsersFromCampaign");
                _totalAmount += balance;
                claimableBalances[user][_campaignID] -= balance;
            }
        }

        if (_increase) {
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);
            claimable.totalRemainingAmount += _totalAmount;
        } else {
            IERC20Upgradeable(_token).safeTransfer(msg.sender, _totalAmount);
            claimable.totalRemainingAmount -= _totalAmount;
        }

        emit ClaimableAmountsChanged(_campaignID, _token, _totalAmount, block.timestamp);
    }

    function addUsersToCampaign(
        address _token,
        address[] memory _users,
        uint256[] memory _balances,
        uint256 _campaignID
    ) external onlyHandler {
        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        address _token = claimable.tokenAddress;
        require(_token != address(0), "Campaign doesnt exist");
        uint256 length = _users.length;
        require(length == _balances.length, "Claimable: user and balance array length mismatch");
        require(claimable.ended == false, "Campaign has ended");

        uint256 _totalAmount;
        for (uint256 i; i < length; i++) {
            address user = _users[i];
            require(!hasClaimable[user][_campaignID],"User already has claimable amounts, use editAirdropAmount");
            require(_users[i] != address(0), "Claimable: Invalid address");
            
            uint256 balance = _balances[i];

            claimableBalances[user][_campaignID] += balance;
            hasClaimable[user][_campaignID] = true;
            _totalAmount += balance;
            usersCampaign[_campaignID].push(user);
        }

        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);
        claimable.totalRemainingAmount += _totalAmount;

        emit UsersAddedToCampaign(_campaignID, _token, _totalAmount, block.timestamp,_users);
    }

    function removeUsersFromCampaign(
        address _token,
        address[] memory _users,
        uint256 _campaignID
    ) external onlyHandler {
        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        address _token = claimable.tokenAddress;
        require(_token != address(0), "Campaign doesnt exist");
        require(claimable.ended == false, "Campaign has ended");

        uint256 length = _users.length;

        uint256 _totalAmount;
        for (uint256 i; i < length; i++) {
            require(_users[i] != address(0), "Claimable: Invalid address");
            address user = _users[i];

            _totalAmount += claimableBalances[user][_campaignID];
            hasClaimable[msg.sender][_campaignID] = false;
            claimableBalances[user][_campaignID] = 0;
            usersCampaign[_campaignID][i] = usersCampaign[_campaignID][usersCampaign[_campaignID].length - 1];
            usersCampaign[_campaignID].pop();
        }

        IERC20Upgradeable(_token).safeTransfer(msg.sender, _totalAmount);
        claimable.totalRemainingAmount -= _totalAmount;

        emit UsersRemoved(_campaignID, _token, _totalAmount, block.timestamp);
    }

    // -- Public functions -- //

    function claimAll(uint256 _campaignID) public whenNotPaused {
        uint256 length = campaignID;
        for (uint256 i; i < length; i++) {
            if (hasClaimable[msg.sender][i] && claimableBalances[msg.sender][_campaignID] > 0) {
                claim(i);
            }
        }
    }

    function claim(uint256 _campaignID) public whenNotPaused {
        ClaimableInfo storage claimable = claimableInfo[_campaignID];
        bool ended = claimable.ended;
        if (!ended) {
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
}

