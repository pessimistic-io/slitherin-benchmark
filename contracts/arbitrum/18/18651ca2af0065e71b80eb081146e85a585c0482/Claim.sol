// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { Pausable } from "./Pausable.sol";
import { Ownable } from "./Ownable.sol";

/// @notice contract that allows a treasury contract to send ERC20 this address and allow users to claim it
/// @dev this contract is pausable, and only the owner can pause it

contract Claim is Pausable, Ownable {
    using SafeERC20 for IERC20;

    struct ClaimableInfo {
        uint256 id;
        address tokenAddress;
        uint256 totalRemainingAmount; //total amount of the claimable balance
        uint256 claimablePeriod;
        uint256 startTimestamp;
    }
    uint256 public constant MAX_CLAIMABLE_PERIOD = 730 days; // 2 years
    uint256 public constant MIN_CLAIMABLE_PERIOD = 7 days;

    uint256 public currentId; //id for the claimable balance

    //user address => claimableId => amount
    mapping(address => mapping(uint256 => uint256)) public claimableBalances;
    //ids => tokenAddress
    mapping(uint256 => ClaimableInfo) public claimableInfo;

    mapping(address => mapping(uint256 => bool)) public hasClaimable;

    mapping(address => bool) public isHandler;

    event TransferExpired(uint256 indexed id, address indexed token, address indexed user, uint256 amount);

    event Claimed(uint256 indexed id, address indexed token, address indexed user, uint256 amount);

    event ClaimableRoundAdded(
        uint256 indexed id,
        address indexed token,
        uint256 totalRemainingAmount,
        uint256 claimablePeriod,
        uint256 startTimestamp
    );

    event HandlerSet(address handler, bool isActive);

    ///@notice modifier to check if the caller is a leverage vault
    modifier onlyHandler() {
        require(isHandler[msg.sender], "handler only");
        _;
    }

    constructor() {
        isHandler[msg.sender] = true;
    }

    /// @notice set the handler, only owner can call this function
    /// @param _handler handler address
    /// @param _isActive whether the handler is active
    function setHandler(address _handler, bool _isActive) external onlyOwner {
        //Implement zero address checks
        require(_handler != address(0), "Claimable: Invalid address");
        isHandler[_handler] = _isActive;
        emit HandlerSet(_handler, _isActive);
    }

    /// @notice function to pause the contract, only handler can call this function
    function pause() external onlyHandler {
        _pause();
    }

    //add upaused function
    /// @notice function to unpause the contract, only handler can call this function
    function unpause() external onlyHandler {
        _unpause();
    }

    /// @notice let treasury notifiy users of a claimable balance, the input will be token address, a user array and a balance array
    /// @dev the user array and balance array will be the same length, and the index of the user will be the same as the index of the balance
    /// @dev only ERC20 token can be notified, no native asset
    /// @param _token token address
    /// @param claimablePeriod the period of time that the user can claim the balance
    /// @param _users user array
    /// @param _balances balance array
    function notifyClaimable(
        address _token,
        uint256 claimablePeriod,
        address[] memory _users,
        uint256[] memory _balances,
        uint256 _inputTotalAmount
    ) external onlyHandler {
        //require the claimablePeriod to be within the max and min claimable period
        require(
            claimablePeriod <= MAX_CLAIMABLE_PERIOD && claimablePeriod >= MIN_CLAIMABLE_PERIOD,
            "Claimable: invalid period"
        );
        uint256 length = _users.length;
        require(_token != address(0), "Claimable: token address cannot be zero");
        require(length == _balances.length, "Claimable: user and balance array length mismatch");

        uint256 _currentId = currentId;
        uint256 _totalAmount;

        for (uint256 i; i < length; i++) {
            //Implement zero address checks
            require(_users[i] != address(0), "Claimable: Invalid address");
            address user = _users[i];
            uint256 balance = _balances[i];

            claimableBalances[user][_currentId] = balance;
            hasClaimable[user][_currentId] = true;
            _totalAmount += balance;
        }
        ClaimableInfo storage claimable = claimableInfo[_currentId];
        claimable.id = _currentId;
        claimable.tokenAddress = _token;
        claimable.totalRemainingAmount = _totalAmount;
        claimable.claimablePeriod = claimablePeriod;
        claimable.startTimestamp = block.timestamp;

        require(_inputTotalAmount == _totalAmount, "Claimable: input total amount mismatch");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _totalAmount);

        currentId++;

        emit ClaimableRoundAdded(claimable.id, _token, _totalAmount, claimablePeriod, block.timestamp);
    }

    /// @notice let handler notifiy users of a claimable balance and transfer the amount into this contract, the input will be token address, a user array and a balance array

    /// @param id the id of the claimable balance
    /// @param claimablePeriod the period of time that the user can claim the balance
    /// @param _users user array
    /// @param _balances balance array
    ///@dev the claimablePeriod will replace the old claimablePeriod if the id already exists
    function notifyAdditionalClaimable(
        uint256 id,
        uint256 claimablePeriod,
        address[] memory _users,
        uint256[] memory _balances,
        uint256 _inputTotalAmount
    ) external onlyHandler {
        require(
            claimablePeriod <= MAX_CLAIMABLE_PERIOD && claimablePeriod >= MIN_CLAIMABLE_PERIOD,
            "Claimable: invalid period"
        );

        uint256 length = _users.length;
        require(length == _balances.length, "Claimable: user and balance array length mismatch");
        //checking if the id exists
        require(claimableInfo[id].id == id, "Claimable: id does not exist");

        uint256 _totalAmount;
        for (uint256 i; i < length; i++) {
            //Implement zero address checks
            require(_users[i] != address(0), "Claimable: Invalid address");
            address user = _users[i];
            uint256 balance = _balances[i];

            claimableBalances[user][id] += balance;
            hasClaimable[user][id] = true;
            _totalAmount += balance;
        }
        require(_inputTotalAmount == _totalAmount, "Claimable: input total amount mismatch");
        ClaimableInfo storage claimable = claimableInfo[id];
        claimable.totalRemainingAmount += _totalAmount;
        claimable.claimablePeriod = claimablePeriod;
        claimable.startTimestamp = block.timestamp;

        IERC20(claimableInfo[id].tokenAddress).safeTransferFrom(msg.sender, address(this), _totalAmount);

        emit ClaimableRoundAdded(id, claimableInfo[id].tokenAddress, _totalAmount, claimablePeriod, block.timestamp);
    }

    /// @notice let users claim their claimable balances in batch
    /// @param _ids the ids of the claimable balance
    function claimMultiple(uint256[] memory _ids) external whenNotPaused {
        uint256 len = _ids.length;
        for (uint256 i = 0; i < len; i++) {
            claim(_ids[i]);
        }
    }

    /// @notice check if the claimable balance is expired, if it is, then let owner claim the balance of a specific id
    /// @param _id the id of the claimable balance
    /// @param _to the address that will receive the expired balance
    function transferExpired(uint256 _id, address _to) external onlyHandler {
        //Implement zero address checks
        require(_to != address(0), "Claimable: Invalid address");
        ClaimableInfo storage claimable = claimableInfo[_id];
        require(block.timestamp > claimable.startTimestamp + claimable.claimablePeriod, "claim not expired");
        uint256 amount = claimable.totalRemainingAmount;
        claimable.totalRemainingAmount = 0;
        IERC20(claimable.tokenAddress).safeTransfer(_to, amount);
        emit TransferExpired(_id, claimable.tokenAddress, _to, amount);
    }

    /// @notice withdraw the token to the owner
    /// @param token token address
    function withdrawToken(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
    }

    /// @notice let users claim their claimable balance
    /// @param _id the id of the claimable balance

    //create a view function to check the claimable balance of a user
    function checkClaimableBalance(uint256 _id, address _user) external view returns (uint256) {
        return claimableBalances[_user][_id];
    }

    function claim(uint256 _id) public whenNotPaused {
        require(hasClaimable[msg.sender][_id], "Claimable: user does not have claimable balance");

        ClaimableInfo storage claimable = claimableInfo[_id];
        require(
            block.timestamp <= claimable.startTimestamp + claimable.claimablePeriod,
            "Claimable: claimable period ended"
        );

        uint256 amount = claimableBalances[msg.sender][_id];
        // require(amount > 0, "Claimable: claimable balance already claimed");

        claimableBalances[msg.sender][_id] = 0;
        hasClaimable[msg.sender][_id] = false;
        claimable.totalRemainingAmount -= amount;

        IERC20(claimable.tokenAddress).safeTransfer(msg.sender, amount);
        emit Claimed(_id, claimable.tokenAddress, msg.sender, amount);
    }
}

