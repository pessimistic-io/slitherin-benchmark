// SPDX-License-Identifier: Apache-2.0

// Copyright 2023 CoinSender

/**
 * @title CoinSenderClaim
 * @dev This contract allows for non-custodial transfer of tokens.
 *
 * Company: CoinSender
 * Developed by: Valerii Manchenko
 *
 * The CoinSender contract includes functionalities of tracking token transfers,
 * cancelling pending transfers, and claiming tokens by the recipient.
 * It utilizes OpenZeppelin's contracts library for secure and standardized
 * Ethereum contract development.
 *
 * For questions and further details, contact:
 * - company: CoinSender, https://coinsender.io/
 * - developer: Valeriy Manchenko, vsvalera@gmail.com
 */

pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";

import "./OwnableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";

import "./EnumerableSetUpgradeable.sol";
import "./CountersUpgradeable.sol";


// import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "./ERC2771ContextUpgradeable.sol";

import "./CurrencyTransferLib.sol";

contract CoinSenderClaimV2 is
    Initializable,
    UUPSUpgradeable,
    ERC2771ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable
{

    // Use OpenZeppelin's EnumerableSet for uint256.
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    event CoinSent(address indexed coinAddress, uint256[] id);
    event CoinClaimed(address indexed claimer, uint256 id);
    event CancelTransfer(address indexed sender, uint256 id);
    event BankAddressChanged(address indexed oldBank, address indexed newBank);
    event MinFeeChanged(uint256 oldMinFee, uint256 newMinFee);

    modifier onlyPermittedUser(address user) {
        require(_msgSender() == user || hasRole(OPERATOR_ROLE, _msgSender()), "Not the authorized user or operator");
        _;
    }

    /// @dev transferId => Transfer
    mapping(uint256 => Transfer) private transfers;

    /// @dev id counter for transfers
    CountersUpgradeable.Counter private transferIdCounter;

    /// @dev Declare the maps
    mapping(address => EnumerableSetUpgradeable.UintSet) private senderTransfers;
    mapping(address => EnumerableSetUpgradeable.UintSet) private recipientTransfers;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    string public constant name = "CoinSenderClaim";
    string public constant version = "2";

    address public bank;
    uint256 public minFee;

    struct Transfer {
        uint256 id;
        address recipient;
        address sender;
        address coin;
        uint amount;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {}

    function _authorizeUpgrade(address newImplementation)
    internal
    virtual
    override
    onlyOwner
    {}

    /**
    * @notice Initializes the contract with an owner and a minimum fee
    * @param _owner The owner's address for the contract
    * @param _minFee The minimum fee for contract operations
    */
    function initialize(address _owner, uint256 _minFee) public initializer {
        require(_owner != address(0), "CoinSenderV2: Owner address is not set");

        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __AccessControlEnumerable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(OPERATOR_ROLE, _owner);
        _setupRole(PAUSER_ROLE, _owner);

        transferOwnership(_owner);
        bank = _owner;
        minFee = _minFee;
    }

    receive() external payable {}

    /**
    * @dev Sets the bank address
    *
    * @param _bank The new bank address
    */
    function changeBankAddress(address _bank) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_bank != address(0), "CoinSenderV2: Bank address is not be zero");
        address oldBank = bank;
        bank = _bank;
        emit BankAddressChanged(oldBank, _bank);
    }

    /**
    * @dev Sets the minimum fee
    *
    * @param _minFee The new minimum fee
    */
    function setMinFee(uint256 _minFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldMinFee = minFee;
        minFee = _minFee;
        emit MinFeeChanged(oldMinFee, _minFee);
    }

    /**
    * @dev Sends specified amount of coins to the specified recipients. The function also accounts for a fee
    * that will be deducted from the sent funds.
    *
    * @param _currency The address of the token to be sent. Use address 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE for Ether.
    * @param _recipient An array of recipient addresses. Should be the same length as _amount array.
    * @param _amount An array of amounts to send to each recipient. Should be the same length as _recipient array.
    * @param _fee The fee to be deducted from the sent funds.
    *
    * The sender of the function must have enough tokens or Ether in their account to perform the transfer,
    * including the fee.
    *
    * This function calls an external contract (the ERC20 token or the recipient address). Consider the reentrancy
    * risks and the need for a check-effects-interactions pattern.
    *
    * IMPORTANT: The function assumes that the addresses and amounts have been previously validated and are correct.
    * It doesn't perform additional input validation.
    */
    function sendCoins(address _currency, address[] calldata _recipient, uint256[] calldata _amount, uint256 _fee)
    external payable nonReentrant whenNotPaused
    {
        require(_currency != address(0), "CoinSenderClaim: Token address cannot be zero address");
        require(_recipient.length > 0, "CoinSenderClaim: Recipients array cannot be empty");
        require(_recipient.length == _amount.length, "CoinSenderClaim: Recipients and amounts arrays should have the same length");

        uint256 totalAmount = 0;
        uint256 transferId;
        uint256[] memory ids = new uint256[](_recipient.length);

        for (uint256 i = 0; i < _recipient.length; i++) {
            require(_amount[i] > 0, "CoinSenderClaim: Amount must be greater than 0");
            require(_recipient[i] != _msgSender(), "CoinSenderClaim: You cannot send coins to yourself");
            require(_recipient[i] != address(0), "CoinSenderClaim: Recipient address not be zero");

            transferId = transferIdCounter.current();
            ids[i] = transferId;

            totalAmount += _amount[i];
            transfers[transferId] = Transfer(transferId, _recipient[i], _msgSender(), _currency, _amount[i]);
            _addTransferId(_msgSender(), _recipient[i], transferId);

            transferIdCounter.increment();
        }

        if (_currency == CurrencyTransferLib.NATIVE_TOKEN) {
            require(msg.value >= _fee + totalAmount, "CoinSenderClaim: Insufficient ETH sent to cover fee and total amount");
        }

        _processFee(_fee);

        CurrencyTransferLib.transferCurrency(_currency, _msgSender(), payable(address(this)), totalAmount);

        emit CoinSent(_currency, ids);
    }

    /**
    * @dev Returns an array of pending coin claims for the specified recipient.
    *
    * @param _recipient The address of the recipient to view the pending coin claims for.
    *
    * @return claims An array of `Transfer` structs representing the pending claims.
    *
    * The caller of the function must be the recipient themselves.
    */
    function viewClaimsCoins(address _recipient)
    external view onlyPermittedUser(_recipient) returns (Transfer[] memory)
    {
        return __getTransfers(recipientTransfers[_recipient]);
    }

    /**
    * @dev Returns an array of sent coins for the specified sender.
    *
    * @param _sender The address of the sender to view the sent coins for.
    *
    * @return sentTokens An array of `Transfer` structs representing the sent coins.
    *
    * The caller of the function must be the sender themselves.
    */
    function viewSentCoins(address _sender)
    external view onlyPermittedUser(_sender) returns (Transfer[] memory)
    {
        return __getTransfers(senderTransfers[_sender]);
    }

    /**
    * @dev Allows the caller to claim one or more coin transfers.
    *
    * @param _transferIds An array of transfer IDs to claim.
    * @param _fee The fee to be deducted from the claimed funds.
    *
    * The caller of the function must be the recipient of each of the transfers.
    * Each of the transfers must be in a claimable state.
    */
    function claim(uint256[] calldata _transferIds, uint256 _fee)
    external payable nonReentrant whenNotPaused {
        require(_transferIds.length > 0, "Transfer IDs array cannot be empty");

        _processFee(_fee);

        for (uint256 i = 0; i < _transferIds.length; i++) {
            __claim(_msgSender(), _transferIds[i]);
        }
    }

    /**
    * @dev Allows the caller to cancel one or more coin transfers.
    *
    * @param _transferIds An array of transfer IDs to cancel.
    *
    * The caller of the function must be the sender of each of the transfers.
    * Each of the transfers must be in a cancelable state.
    */
    function cancel(uint256[] calldata _transferIds)
    external nonReentrant
    {
        require(_transferIds.length > 0, "No transfer IDs provided");

        for (uint256 i = 0; i < _transferIds.length; i++) {
            __cancel(_msgSender(), _transferIds[i]);
        }
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function __claim(address _claimant, uint256 _transferId) private {
        Transfer memory transfer = transfers[_transferId];
        require(transfer.amount > 0, "No pending claim found");
        require(transfer.recipient == _claimant, "Claimant is not the recipient of the transfer");
        require(recipientTransfers[_claimant].contains(transfer.id), "The claimant is not the recipient for this transfer ID");

        transfers[_transferId].amount = 0;
        _removeTransferId(transfer.sender, transfer.recipient, _transferId);

        CurrencyTransferLib.transferCurrency(transfer.coin, address(this), payable(_claimant), transfer.amount);

        emit CoinClaimed(transfer.sender, _transferId);
    }

    function __cancel(address _requestor, uint256 _transferId) private {
        Transfer memory transfer = transfers[_transferId];
        require(transfer.amount > 0, "No transfer found");
        require(transfer.sender == _requestor, "Requestor is not the sender of the transfer");
        require(senderTransfers[_requestor].contains(_transferId), "The requestor did not initiate this transfer");

        transfers[_transferId].amount = 0;
        _removeTransferId(transfer.sender, transfer.recipient, _transferId);

        CurrencyTransferLib.transferCurrency(transfer.coin, address(this), payable(transfer.sender), transfer.amount);

        emit CancelTransfer(_msgSender(), _transferId);
    }

    function __getTransfers(EnumerableSetUpgradeable.UintSet storage set) private view returns (Transfer[] memory) {
        Transfer[] memory transfersList = new Transfer[](set.length());

        for (uint i = 0; i < set.length(); i++) {
            transfersList[i] = transfers[set.at(i)];
        }

        return transfersList;
    }

    // Add a transferId to a sender and a recipient
    function _addTransferId(address _sender, address _recipient, uint256 _transferId) private {
        senderTransfers[_sender].add(_transferId);
        recipientTransfers[_recipient].add(_transferId);
    }

    // Remove a transferId from a sender and a recipient
    function _removeTransferId(address _sender, address _recipient, uint256 _transferId) private {
        senderTransfers[_sender].remove(_transferId);
        recipientTransfers[_recipient].remove(_transferId);
    }

    function _processFee(uint256 _amount) private {
        require(_amount >= minFee, "CoinSenderClaim: Fee is below the minimum");
        require(msg.value >= _amount, "CoinSenderClaim: Fee to low");
        CurrencyTransferLib.transferCurrency(CurrencyTransferLib.NATIVE_TOKEN, _msgSender(), payable(bank), _amount);
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

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControlEnumerableUpgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[99] private __gap;

}

