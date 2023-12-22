// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { EnumerableSet } from "./EnumerableSet.sol";
import { Ownable2Step } from "./Ownable2Step.sol";
import { Pausable } from "./Pausable.sol";
import { IDepositContract } from "./IDepositContract.sol";
import "./CommonError.sol";

contract DepositContract is Ownable2Step, Pausable, IDepositContract {

    uint256 constant SUBSCRIPTION_DURATION = 180 days;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Whitelisting
    EnumerableSet.AddressSet private whitelist;
    mapping(address => EnumerableSet.AddressSet) private contractWhitelisted;

    // Subscriptions
    mapping(address => Subscription) private subscriptionPeriod;

    struct Subscription {
        uint256 startDate;
        uint256 endDate;
        bool isSnap;
    }

    // Funds management
    mapping(address => uint256) private minBalanceLimitClient;
    mapping(address => uint256) private clientFund;
    uint256 private supraFund;
    uint256 private minBalanceLimitSupra;

    // Miscellaneous
    address public generator;
    address public router;
    address public coldWallet;
    address public _tempWallet;
    address public approver;
    address public developer;
    bool public adminFeelsOK;

    /// @dev Emitted when a client is whitelisted.
    /// @param _clientAddress Address of the client that has been whitelisted.
    /// @param _startTime The timestamp representing the start time of the subscription period.
    /// @param _endTime The timestamp representing the end time of the subscription period.
    /// @param _isSnap A boolean flag indicating if the client is a part of the SNAP program or not.
    event ClientWhitelisted(address _clientAddress, uint256 _startTime, uint256 _endTime, bool _isSnap);

    /// @dev Emitted when a client is removed from the whitelist.
    /// @param _clientAddress Address of the client that has been removed from the whitelist.
    /// @param _removedTime The timestamp representing the time at which the client was removed.
    event ClientRemovedFromWhitelist(address _clientAddress, uint256 _removedTime);

    /// @dev Emitted when contracts are removed from the whitelist for a client
    /// @param _clientAddress The address of the client whose contracts were removed
    /// @param _removedTime The timestamp when the contracts were removed
    event ContractsDeletedFromWhitelist(address _clientAddress, uint256 _removedTime);

    /// @dev Emitted when a contract is whitelisted for a client.
    /// @param _clientAddress Address of the client whose contract has been whitelisted.
    /// @param _contractAddress Address of the contract that has been whitelisted.
    /// @param _timeStamp The timestamp representing the time at which the contract was whitelisted.
    event ContractWhitelisted(address _clientAddress, address _contractAddress, uint256 _timeStamp);

    /// @dev Emitted when a client deposits funds into their account.
    /// @param _depositer The address of the client who deposited funds.
    /// @param amount The amount of funds that were deposited.
    event ClientDeposited(address _depositer, uint256 amount);

    /// @dev Emitted when a client withdraws funds from their account.
    /// @param _withdrawer The address of the client who withdrew funds.
    /// @param amount The amount of funds that were withdrawn.
    event ClientWithdrwal(address _withdrawer, uint256 amount);

    /// @dev Emitted when Supra collects funds from a client's account.
    /// @param _fromClient The address of the client from whom funds were collected.
    /// @param amount The amount of funds that were collected.
    event SupraCollected(address _fromClient, uint256 amount);

    /// @dev Emitted when Supra refunds funds to a client's account.
    /// @param _toClient The address of the client to whom funds were refunded.
    /// @param amount The amount of funds that were refunded.
    event SupraRefunded(address _toClient, uint256 amount);

    /// @dev Emitted when the approver confirms the new cold wallet address
    /// @param _coldWalletAddress The new address of the cold wallet
    event ColdWalletConfirmed(address _coldWalletAddress);

    /// @dev Emitted when the client set the minimum balance limit to hold in wallet
    /// @param  _clientAddress The client wallet address through which and for which the limit is to be set
    /// @param limit The value which client wants to be a minimum limit for the specified wallet
    event MinBalanceClientSet(address _clientAddress, uint256 limit);

    /// @dev When approver and deployer are same
    error InvalidApprover();

    /// @dev when minimum balance limit is zero
    error InvalidMinBalanceLimit();

    /// @dev when client/contract is not whitelisted
    error NotWhitelisted();

    /// @dev when client/contract is already whitelisted
    error AlreadyWhitelisted();

    /// @dev when new end time is in the future
    error InvalidEndTime();

    /// @dev when fund transfer fails
    error TransferFailure();

    /// @dev when supra or client funds are less than amount
    error NotEnoughFunds();

    /// @dev when minimum balance limit is less than global limit
    error InvalidBalanceLimit();

    /// @dev only generator can call this
    error GeneratorOnly();

    /// @dev Unauthorized Access
    error UnauthorizedAccess();

    /// @dev only approver can call this
    error ApproverOnly();

    /// @dev when cold wallet proposal is not ready
    error ColdWalletProposalNotReady();

    /// @dev Constructor to initialize contract with provided parameters.
    /// @param _approver Address of the approver who will approve changes.
    /// @param _developer Address of the developer who will manage the contract.
    /// @param _newGenerator Address of the new generator contract.
    /// @param _newRouter Address of the new router contract.
    /// @param _minBalanceLimitSupra Minimum balance limit to execute supra transactions.
    /// The value must be greater than or equal to zero.
    constructor(address _approver, address _developer, address _newGenerator, address _newRouter, uint256 _minBalanceLimitSupra){
        if (_approver == msg.sender) revert InvalidApprover();
        if (_developer == address(0) ||
            _approver == address(0) ||
            _newGenerator == address(0) ||
            _newRouter == address(0)) {
            revert InvalidAddress();
        }
        if (_minBalanceLimitSupra == 0) revert InvalidMinBalanceLimit();

        developer = _developer;
        approver = _approver;
        generator = _newGenerator;
        router = _newRouter;
        minBalanceLimitSupra = _minBalanceLimitSupra;
    }

    modifier checkClientWhitelisted(address _clientAddress) {
        if (!isClientWhitelisted(_clientAddress)) revert NotWhitelisted();
        _ ;
    }

    /**
        #######################################################################################
            :::::::::::::::::::::::: SUPRA ADMIN OPERATIONS ::::::::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Allows SupraAdmin to add a client to the whitelist.
    /// @param _clientAddress The address of the client being added.
    /// @param _isSnap A boolean value indicating whether the client is a Snap user or not.
    function addClientToWhitelist(address _clientAddress, bool _isSnap) external onlyOwner {
        if (isClientWhitelisted(_clientAddress)) revert AlreadyWhitelisted();
        whitelist.add(_clientAddress);
        addSubscriptionInfoByClient(_clientAddress, block.timestamp, block.timestamp + SUBSCRIPTION_DURATION, _isSnap);
        emit ClientWhitelisted(_clientAddress, block.timestamp, block.timestamp + SUBSCRIPTION_DURATION, _isSnap);
    }

    /// @dev Update the end time of a client's subscription
    /// @param _clientAddress The address of the client
    /// @param _newEndTime The new end time for the subscription
    /// - require The client is whitelisted
    /// - require The new end time is in the future
    function updateSubscription(address _clientAddress, uint256 _newEndTime) external onlyOwner checkClientWhitelisted(_clientAddress) {
        if (_newEndTime <= block.timestamp + 2 days) revert InvalidEndTime();
        subscriptionPeriod[_clientAddress].endDate = _newEndTime;
    }

    /// @dev Remove a client from the whitelist
    /// @param _clientAddress The address of the client to remove
    function removeClientFromWhitelist(address _clientAddress) external onlyOwner checkClientWhitelisted(_clientAddress) {
        uint256 _amount = checkClientFund(_clientAddress);
        (bool sent, bytes memory data) = payable(_clientAddress).call{value: _amount}("");
        if (!sent) revert TransferFailure();
        whitelist.remove(_clientAddress);
        emit ClientRemovedFromWhitelist(_clientAddress, block.timestamp);
    }

    /// @dev Remove all contracts associated with a client
    /// @param _clientAddress The address of the client
    function removeAllContractOfClient(address _clientAddress) external onlyOwner {
        contractWhitelisted[_clientAddress].clear();
    }

    /// @dev Allows the owner to claim free node expenses.
    /// Only the owner can do this.
    /// @param _amount The amount to be claimed to coldwallet.
    function claimFreeNodeExpenses(uint256 _amount) external onlyOwner {
        if (coldWallet == address(0)) revert InvalidAddress();
        if (_amount > supraFund) revert NotEnoughFunds();
        supraFund -= _amount;
        (bool sent, bytes memory data) = payable(coldWallet).call{value: _amount}("");
        if (!sent) revert TransferFailure();
    }

    /// @dev Execute a refund from the supra fund to a client
    /// @param _fundReceiver The address of the client receiving the refund
    /// @param _amount The amount to be refunded
    /// - require The client is whitelisted
    /// - require The refund amount is less than or equal to the supra fund
    function executeRefund(address _fundReceiver, uint256 _amount) external onlyOwner checkClientWhitelisted(_fundReceiver){
        if (_amount > supraFund) revert NotEnoughFunds();
        supraFund -= _amount;
        clientFund[_fundReceiver] = clientFund[_fundReceiver] + _amount;
        emit SupraRefunded(_fundReceiver, _amount);
    }

    /// @dev Updates the address of the developer.
    /// Only the owner is authorized to perform this action.
    /// @param _newDeveloper The address of the new developer to be set.
    function updateDeveloper(address _newDeveloper) external onlyOwner {
        if (_newDeveloper == address(0)) revert InvalidAddress();
        developer = _newDeveloper;
    }

    /// @dev Sets the minimum balance limit for SupraAdmin.
    /// @param _limit The new minimum balance limit for SupraAdmin.
    function updateMinBalanceSupra(uint256 _limit) external onlyOwner {
        minBalanceLimitSupra = _limit;
    }

    /// @dev Deposits ETH into the SupraFund contract.
    function depositSupraFund() external payable onlyOwner {
        supraFund += msg.value;
    }

    /// @dev Pauses withdrawals for the contract.
    /// Only the owner is authorized to perform this action.
    /// Emits a {Paused} event.
    function pauseWithdrawal() external onlyOwner {
        _pause();
    }

    /// @dev Resumes withdrawals for the contract.
    /// Only the owner is authorized to perform this action.
    /// Emits an {Unpaused} event.
    function unpauseWithdrawal() external onlyOwner {
        _unpause();
    }

    /// @dev Sets the generator contract address.
    /// Only the owner can do this.
    /// @param _newGenerator The new generator contract address.
    /// @param _newRouter The new router contract address
    function updateGeneratorRouter(address _newGenerator, address _newRouter) external onlyOwner {
        if (!isContract(_newGenerator) || !isContract(_newRouter)) revert AddressIsNotContract();
        if (_newGenerator == address(0) || _newRouter == address(0)) revert InvalidAddress();
        generator = _newGenerator;
        router = _newRouter;
    }

    /**
        #######################################################################################
            :::::::::::::::::::::: WHITELISTED CLIENT OPERATIONS ::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Allows a client to add a contract to their whitelist.
    /// @param _contractAddress The address of the contract being added.
    function addContractToWhitelist(address _contractAddress) external checkClientWhitelisted(msg.sender) {
        if (!isContract(_contractAddress)) revert AddressIsNotContract();
        if (isContractWhitelisted(msg.sender, _contractAddress)) revert AlreadyWhitelisted();
        contractWhitelisted[msg.sender].add(_contractAddress);
        emit ContractWhitelisted(msg.sender, _contractAddress, block.timestamp);
    }

    /// @dev Removes a contract from a client's whitelist.
    /// Only the client who added the contract can remove it.
    /// @param _contractAddress The address of the contract to remove.
    function removeContractFromWhitelist(address _contractAddress) external {
        if (!isContractWhitelisted(msg.sender, _contractAddress)) revert NotWhitelisted();
        contractWhitelisted[msg.sender].remove(_contractAddress);
        emit ContractsDeletedFromWhitelist(_contractAddress, block.timestamp);
    }

    /// @dev Allows a client to deposit funds into their account.
    function depositFundClient() external payable checkClientWhitelisted(msg.sender) {
        clientFund[msg.sender] = clientFund[msg.sender] +  msg.value;
        emit ClientDeposited(msg.sender, msg.value);
    }

    ///  @dev Sets the minimum balance limit for the calling client.
    ///  @param _limit The new minimum balance limit for the calling client.
    function setMinBalanceClient(uint256 _limit) external checkClientWhitelisted(msg.sender) {
        if (_limit <= minBalanceLimitSupra) revert InvalidBalanceLimit();
        minBalanceLimitClient[msg.sender] = _limit;
        emit MinBalanceClientSet(msg.sender, _limit);
    }

    /// @dev Allows a client to withdraw their funds.
    /// @param _amount The amount to be withdrawn.
    /// Emits a ClientWithdrawal event.
    function withdrawFundClient(uint256 _amount) external whenNotPaused {
        if (_amount > checkClientFund(msg.sender)) revert NotEnoughFunds();
        clientFund[msg.sender] = checkClientFund(msg.sender) - _amount;
        (bool sent, bytes memory data) = payable(msg.sender).call{value: _amount}("");
        if (!sent) revert TransferFailure();
        emit ClientWithdrwal(msg.sender, _amount);
    }

    /**
        #######################################################################################
            ::::::::::::::::::::::::: GEERATOR RELATED FUNCTIONS ::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Allows the generator contract to collect funds from a client's balance.
    /// @param _clientAddress The address of the client whose funds are being collected.
    /// @param _amount The amount of funds to be collected.
    function collectFund(address _clientAddress, uint256 _amount) external override {
        if (msg.sender != generator) revert GeneratorOnly();
        if (_amount > clientFund[_clientAddress]) revert NotEnoughFunds();
        clientFund[_clientAddress] = clientFund[_clientAddress]-_amount;
        supraFund = supraFund + _amount;
        emit SupraCollected(_clientAddress,_amount);
    }

    /// @dev Returns the fund balance of the specified client address.
    /// Only authorized callers, including the whitelisted client, developer, owner, and generator, can perform this action.
    /// @param _clientAddress The address of the client whose fund balance is to be checked.
    /// @return The fund balance of the specified client address.
    function checkClientFund(address _clientAddress) public view checkClientWhitelisted(_clientAddress) override returns (uint256) {
        address s = msg.sender;
        if (s != _clientAddress &&
            s != developer &&
            s != owner() &&
            s != generator &&
            s != router) {
            revert UnauthorizedAccess();
        }
        return clientFund[_clientAddress];
    }

    /**
        #######################################################################################
            :::::::::::::::::::::: ROUTER RELATED FUNCTIONS ::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Returns a boolean indicating whether the given client and contract addresses are eligible for interaction.
    /// @param _clientAddress The address of the client.
    /// @param _contractAddress The address of the contract.
    /// @return A boolean indicating whether the given client and contract addresses are eligible for interaction.
    function isContractEligible(address _clientAddress,address _contractAddress) public view checkClientWhitelisted(_clientAddress) override returns (bool) {
        return (isContractWhitelisted(_clientAddress, _contractAddress));
    }

    /// @dev Checks whether the minimum balance for a given client address has been reached.
    /// @param _clientAddress The client address to check.
    /// @return A boolean indicating whether the minimum balance for the given client address has been reached.
    function isMinimumBalanceReached(address _clientAddress) public view checkClientWhitelisted(_clientAddress) override returns (bool) {
        address s = msg.sender;
        if (s != developer &&
            s != owner() &&
            s != generator &&
            s != router) {
            revert UnauthorizedAccess();
        }
        return (checkClientFund(_clientAddress) <= checkMinBalance(_clientAddress));
    }

    /**
        #######################################################################################
            :::::::::::::::::::::: ADMIN + APPROVER OPERATIONS ::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Propose a new cold wallet address
    /// @param _newColdWallet The address of the new cold wallet
    function proposeColdWallet(address _newColdWallet) external onlyOwner {
        _tempWallet = _newColdWallet;
        adminFeelsOK = true;
    }

    /// @dev Confirm a proposed cold wallet address
    /// @notice This function can only be executed by the approver
    /// @notice The proposal must be confirmed by the owner before the cold wallet can be updated
    /// - require The proposal is ready to be confirmed
    function confirmColdWallet() external {
        if (msg.sender != approver) revert ApproverOnly();
        if (!adminFeelsOK) revert ColdWalletProposalNotReady();
        coldWallet = _tempWallet;
        adminFeelsOK = false;
        emit ColdWalletConfirmed(coldWallet);
    }

    /**
        #######################################################################################
            :::::::::::::::::::::: CRON AND SCRIPT RELATED FUNCTIONS ::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Returns an array of whitelisted client addresses along with their respective fund balances and minimum balance requirements.
    /// @return A tuple of three arrays: (1) an array of whitelisted client addresses, (2) an array of their fund balances, and (3) an array of their minimum balance requirements.
    function checkBalanceAllWhitelisted() external view returns (address[] memory, uint256[] memory, uint256[] memory) {
        address s = msg.sender;
        if (s != developer && s != owner()) revert UnauthorizedAccess();
        uint256 count = countTotalWhitelistedClient();
        address[] memory _clients = listAllWhitelistedClient();

        uint256[] memory _funds = new uint256[](count);
        uint256[] memory _minBalance = new uint256[](count);

        for (uint256 loop = 0; loop < count; loop++) {
            address client = _clients[loop];
            _funds[loop] = clientFund[client];
            _minBalance[loop] = checkMinBalance(client);
        }

        return (_clients, _funds, _minBalance);
    }

    /// @dev Returns the minimum balance limit for the SupraAdmin.
    /// @return The minimum balance limit for the SupraAdmin.
    function checkMinBalanceSupra() public view returns (uint256) {
        return minBalanceLimitSupra;
    }

    /// @dev Returns the total number of whitelisted clients.
    /// @return The total number of whitelisted clients.
    function countTotalWhitelistedClient() public view returns (uint256) {
        return whitelist.length();
    }

    /**
        #######################################################################################
            ::::::::::::::::::::::::: RESTRICTED VIEW FUNCTIONS ::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Returns the effective balance for a given client address.
    /// @param _clientAddress The client address to check.
    /// @return The effective balance for the given client address.
    function checkEffectiveBalance(address _clientAddress) public view checkClientWhitelisted(_clientAddress) returns (uint256) {
        address s = msg.sender;
        if (s != _clientAddress || s != developer || s != owner())
            revert UnauthorizedAccess();
        uint256 balance;
        if(checkClientFund(_clientAddress) > checkMinBalance(_clientAddress)){
            balance = checkClientFund(_clientAddress) - checkMinBalance(_clientAddress);
        }
        return balance;
    }

    /// @dev Returns the number of contracts whitelisted by a client.
    /// @param _clientAddress The client address to check.
    /// @return The number of contracts whitelisted by the client.
    function countTotalWhitelistedContractByClient(address _clientAddress) public view checkClientWhitelisted(_clientAddress) returns (uint256) {
        address s = msg.sender;
        if (s != _clientAddress &&
            s != developer &&
            s != owner() &&
            s != generator) {
            revert UnauthorizedAccess();
        }
        return contractWhitelisted[_clientAddress].length();
    }

    /// @dev Get subscription information for a client.
    /// @param _clientAddress The client's address.
    /// @return A tuple containing the start timestamp and the end timestamp of the subscription period.
    function getSubscriptionInfoByClient(address _clientAddress) external view checkClientWhitelisted(_clientAddress) returns (uint256, uint256, bool) {
        address s = msg.sender;
        if (s != _clientAddress &&
            s != developer &&
            s != owner() &&
            s != generator) {
            revert UnauthorizedAccess();
        }
        Subscription memory subscription = subscriptionPeriod[_clientAddress];
        return (subscription.startDate, subscription.endDate, subscription.isSnap);
    }

    /// @dev Check if a contract is whitelisted for a client
    /// @param _clientAddress The address of the client
    /// @param _contractAddress The address of the contract to check
    /// @return A boolean indicating whether the contract is whitelisted
    function isContractWhitelisted(address _clientAddress, address _contractAddress) public view checkClientWhitelisted(_clientAddress) returns (bool) {
        address s = msg.sender;
        if (s != _clientAddress &&
            s != developer &&
            s != owner() &&
            s != generator &&
            s != router) {
            revert UnauthorizedAccess();
        }
        return contractWhitelisted[_clientAddress].contains(_contractAddress);
    }

    /// @dev Returns an array of all whitelisted contracts for a specified client address.
    /// Only authorized callers, including the whitelisted client, developer, and owner, can perform this action.
    /// @param _clientAddress The address of the client whose whitelisted contracts are to be listed.
    /// @return An array of all whitelisted contracts for the specified client address.
    function listAllWhitelistedContractByClient(address _clientAddress) external view checkClientWhitelisted(_clientAddress) returns (address[] memory) {
        address s = msg.sender;
        if (s != _clientAddress && s != developer && s != owner())
            revert UnauthorizedAccess();
        require(_clientAddress != address(0), "User address cannot be zero");
        uint256 totalContracts = contractWhitelisted[_clientAddress].length();

        address[] memory contracts = new address[](totalContracts);
        uint256 count = 0;
        for (count; count < totalContracts; count++) {
            address contractAddress = contractWhitelisted[_clientAddress].at(count);
            contracts[count] = contractAddress;
        }
        if (count == 0) {
            return new address[](0);
        }
        return contracts;
    }

    /// @dev Returns an array of all whitelisted clients.
    /// @return An array of all whitelisted client addresses.
    function listAllWhitelistedClient() public view returns (address[] memory) {
        address s = msg.sender;
        if (s != developer && s != owner()) revert UnauthorizedAccess();

        address[] memory clients = new address[](whitelist.length());
        for (uint256 i = 0; i < whitelist.length(); i++) {
            (address value) = whitelist.at(i);
            clients[i] = value;
        }
        return clients;
    }

    /// @dev Returns the current balance of the SupraFund contract.
    /// @return The current balance of the SupraFund contract.
    function checkSupraFund() external view returns (uint256){
        if (msg.sender != owner() && msg.sender != developer) revert UnauthorizedAccess();
        return supraFund;
    }

    /**
        #######################################################################################
               :::::::::::::::::::::::::: PUBLIC FUNCTIONS :::::::::::::::::::::::::
        #######################################################################################
    */

    /// @dev Checks if a client is whitelisted.
    /// @param _clientAddress The client address to check.
    /// @return True if the client is whitelisted, false otherwise.
    function isClientWhitelisted(address _clientAddress) public view returns (bool) {
        return whitelist.contains(_clientAddress);
    }

    /// @dev Returns the minimum balance limit for a given client address.
    /// @param _clientAddress The client address to check.
    /// @return The minimum balance limit for the given client address.
    function checkMinBalance(address _clientAddress) public view override returns(uint256) {
        uint256 limit;
        if(checkMinBalanceClient(_clientAddress) > checkMinBalanceSupra()){
            limit = checkMinBalanceClient(_clientAddress);
        } else {
            limit = checkMinBalanceSupra();
        }
        return limit;
    }

    /** 
        #######################################################################################
               :::::::::::::::::::::::: INETRNAL FUNCTIONS :::::::::::::::::::::::: 
        #######################################################################################
    */

    /// @dev Returns a boolean indicating whether the given address is a contract or not.
    /// @param _addr The address to be checked.
    /// @return A boolean indicating whether the given address is a contract or not.
    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /// @dev Returns the minimum balance limit for a given client address.
    /// @param _clientAddress The client address to check.
    /// @return The minimum balance limit for the given client address.
    function checkMinBalanceClient(address _clientAddress) internal view returns (uint256) {
        return minBalanceLimitClient[_clientAddress];
    }

    /// @dev Add subscription information for a client
    /// @param _clientAddress The address of the client
    /// @param _start The start timestamp of the subscription
    /// @param _end The end timestamp of the subscription
    /// @param _isSnap A flag indicating whether the subscription is a snapshot subscription
    function addSubscriptionInfoByClient(address _clientAddress, uint256 _start, uint256 _end, bool _isSnap) internal {
        subscriptionPeriod[_clientAddress] = Subscription(_start, _end, _isSnap);
    }


}

